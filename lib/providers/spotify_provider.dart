/// Spotify 真实接入骨架。
///
/// 只允许官方 Web API：搜索与元数据。客户端内播放需要 Web Playback SDK，
/// 桌面端不可用，因此固定返回 notSupported；歌词接口不公开，返回 null。
/// 详见 docs/provider-integration.md。
library;

import 'dart:convert';

import '../domain/lyrics.dart';
import '../domain/models.dart';
import '../platform/auth_keys.dart';
import '../platform/oauth_flow.dart';
import '../platform/secure_credentials.dart';
import '../platform/spotify_auth.dart';
import 'http_client_port.dart';
import 'music_provider.dart';

typedef SpotifyAuthFactory = SpotifyAuth Function(String clientId);

class SpotifyProvider implements MusicProvider {
  SpotifyProvider({
    this.clientId,
    required this.credentials,
    HttpFetcher? fetcher,
    this.auth,
    this.authFactory,
  }) : _fetcher = fetcher ?? disabledFetcher;

  final SecureCredentials credentials;
  final HttpFetcher _fetcher;
  final SpotifyAuthFactory? authFactory;

  String? clientId;
  SpotifyAuth? auth;
  ProviderState _state = ProviderState.disconnected;
  String? _message;

  static const _capabilities = ProviderCapabilities(
    search: true,
    metadata: true,
    lyrics: false,
    inAppPlayback: false,
    officialHandoff: true,
  );

  @override
  MusicService get service => MusicService.spotify;

  @override
  String get displayName => 'Spotify';

  @override
  bool get isDemo => false;

  @override
  ProviderCapabilities get capabilities => _capabilities;

  @override
  ProviderSnapshot get snapshot => ProviderSnapshot(
    service: service,
    state: _state,
    capabilities: _capabilities,
    message: _message,
  );

  bool get isConfigured => (clientId ?? '').isNotEmpty;

  /// 保存公共 Client ID，并据此重建 PKCE 授权器。
  Future<void> configureClientId(String value) async {
    final trimmed = value.trim();
    await credentials.write(spotifyClientIdStorageKey, trimmed);
    clientId = trimmed;
    auth = trimmed.isEmpty ? null : authFactory?.call(trimmed);
    _state = ProviderState.disconnected;
    _message = null;
  }

  /// 恢复运行时保存的 Client ID；编译参数中的 ID 作为初始默认值。
  Future<void> restoreClientId() async {
    final stored = await credentials.read(spotifyClientIdStorageKey);
    if (stored == null || stored.trim().isEmpty) return;
    clientId = stored.trim();
    auth = authFactory?.call(clientId!);
    _state = ProviderState.disconnected;
    _message = null;
  }

  @override
  Future<void> connect() async {
    if (!isConfigured) {
      _state = ProviderState.error;
      _message = '未配置 Spotify 客户端 ID';
      throw const ProviderException(
        '未配置 Spotify 客户端 ID',
        kind: ProviderErrorKind.notConfigured,
      );
    }
    final spotifyAuth = auth;
    if (spotifyAuth == null) {
      _state = ProviderState.error;
      _message = 'Spotify 授权未初始化';
      throw const ProviderException(
        'Spotify 授权未初始化，请检查应用启动配置',
        kind: ProviderErrorKind.notConfigured,
      );
    }

    _state = ProviderState.connecting;
    _message = null;
    try {
      await spotifyAuth.signIn();
      _state = ProviderState.connected;
    } on OAuthException catch (error) {
      _state = ProviderState.error;
      _message = error.message;
      throw ProviderException(
        error.message,
        kind: ProviderErrorKind.unauthorized,
      );
    }
  }

  @override
  Future<void> disconnect() async {
    if (auth != null) {
      await auth!.signOut();
    }
    await credentials.delete(service.storageKey);
    _state = ProviderState.disconnected;
    _message = null;
  }

  /// 应用启动时恢复安全存储中的登录状态；无令牌时保持未连接。
  Future<bool> restoreSession() async {
    final spotifyAuth = auth;
    if (spotifyAuth == null || !isConfigured) return false;
    try {
      final tokens = await spotifyAuth.ensureFresh();
      if (tokens == null) {
        _state = ProviderState.disconnected;
        _message = null;
        return false;
      }
      _state = ProviderState.connected;
      _message = null;
      return true;
    } on OAuthException catch (error) {
      _state = ProviderState.expired;
      _message = error.message;
      return false;
    }
  }

  @override
  Future<List<ProviderTrack>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    if (!isConfigured) return const [];

    var token = await _accessToken();
    if (token == null || token.isEmpty) {
      _state = ProviderState.expired;
      throw const ProviderException(
        '尚未完成 Spotify 授权',
        kind: ProviderErrorKind.unauthorized,
      );
    }

    final uri = Uri.https('api.spotify.com', '/v1/search', {
      'q': trimmed,
      'type': 'track',
      'limit': '20',
      'market': 'from_token',
    });

    var response = await _fetcher(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );

    // 令牌可能在到期前被服务端撤销。刷新一次后重试，避免用户立即重新登录。
    if (response.statusCode == 401 && auth != null) {
      final current = await auth!.loadTokens();
      if (current != null) {
        try {
          final refreshed = await auth!.refresh(current);
          token = refreshed.accessToken;
          response = await _fetcher(
            uri,
            headers: {'Authorization': 'Bearer $token'},
          );
        } on OAuthException catch (error) {
          _state = ProviderState.expired;
          _message = error.message;
        }
      }
    }

    switch (response.statusCode) {
      case 200:
        _state = ProviderState.connected;
        _message = null;
        return _parseTracks(response.body);
      case 401:
        _state = ProviderState.expired;
        _message = 'Spotify 授权已过期，请重新连接';
        throw const ProviderException(
          'Spotify 授权已过期，请重新连接',
          kind: ProviderErrorKind.unauthorized,
        );
      case 403:
        throw const ProviderException(
          'Spotify 拒绝了该请求（可能是地区或权限限制）',
          kind: ProviderErrorKind.forbidden,
        );
      case 429:
        throw const ProviderException(
          'Spotify 请求过于频繁，请稍后重试',
          kind: ProviderErrorKind.rateLimited,
        );
      default:
        throw ProviderException(
          'Spotify 请求失败（HTTP ${response.statusCode}）',
          kind: ProviderErrorKind.unknown,
        );
    }
  }

  Future<String?> _accessToken() async {
    final spotifyAuth = auth;
    if (spotifyAuth == null) {
      return credentials.read(service.storageKey);
    }
    try {
      final tokens = await spotifyAuth.ensureFresh();
      return tokens?.accessToken;
    } on OAuthException catch (error) {
      _state = ProviderState.expired;
      _message = error.message;
      return null;
    }
  }

  List<ProviderTrack> _parseTracks(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return const [];
    final tracksNode = decoded['tracks'];
    if (tracksNode is! Map<String, dynamic>) return const [];
    final items = tracksNode['items'];
    if (items is! List) return const [];

    final tracks = <ProviderTrack>[];
    for (final item in items) {
      if (item is! Map<String, dynamic>) continue;
      final id = item['id'];
      final name = item['name'];
      if (id is! String || name is! String) continue;

      final artists = item['artists'];
      var artist = '未知艺人';
      if (artists is List && artists.isNotEmpty) {
        final first = artists.first;
        if (first is Map<String, dynamic> && first['name'] is String) {
          artist = first['name'] as String;
        }
      }

      var album = '';
      final albumNode = item['album'];
      if (albumNode is Map<String, dynamic> && albumNode['name'] is String) {
        album = albumNode['name'] as String;
      }

      tracks.add(
        ProviderTrack(
          service: service,
          providerTrackId: id,
          title: name,
          artist: artist,
          album: album,
          duration: Duration(
            milliseconds: (item['duration_ms'] as num?)?.toInt() ?? 0,
          ),
          officialHandoffUri: Uri.parse('spotify:track:$id'),
          playable: false,
        ),
      );
    }
    return tracks;
  }

  @override
  Future<LyricTimeline?> lyricsFor(String providerTrackId) async => null;

  @override
  Future<PlaybackStartResult> startPlayback(String providerTrackId) async {
    return const PlaybackStartResult(
      PlaybackStartOutcome.notSupported,
      message: 'Spotify 客户端内播放需要 Web Playback SDK，桌面端暂不支持',
    );
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {}

  @override
  Uri? officialHandoff(String providerTrackId) =>
      Uri.tryParse('https://open.spotify.com/track/$providerTrackId');
}
