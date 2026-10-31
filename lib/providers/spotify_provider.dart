/// Spotify 真实接入骨架。
///
/// 只允许官方 Web API：搜索与元数据。客户端内播放需要 Web Playback SDK，
/// 桌面端不可用，因此固定返回 notSupported；歌词接口不公开，返回 null。
/// 详见 docs/provider-integration.md。
library;

import 'dart:convert';

import '../domain/lyrics.dart';
import '../domain/models.dart';
import '../platform/secure_credentials.dart';
import 'http_client_port.dart';
import 'music_provider.dart';

class SpotifyProvider implements MusicProvider {
  SpotifyProvider({
    required this.clientId,
    required this.credentials,
    HttpFetcher? fetcher,
  }) : _fetcher = fetcher ?? disabledFetcher;

  final String? clientId;
  final SecureCredentials credentials;
  final HttpFetcher _fetcher;

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
    _state = ProviderState.error;
    _message = '官方授权流程尚未接入';
    throw const ProviderException(
      'Spotify 官方 OAuth 尚未接入，请参考 docs/provider-integration.md',
      kind: ProviderErrorKind.notConfigured,
    );
  }

  @override
  Future<void> disconnect() async {
    await credentials.delete(service.storageKey);
    _state = ProviderState.disconnected;
    _message = null;
  }

  @override
  Future<List<ProviderTrack>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final token = await credentials.read(service.storageKey);
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

    final response = await _fetcher(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );

    switch (response.statusCode) {
      case 200:
        _state = ProviderState.connected;
        return _parseTracks(response.body);
      case 401:
        _state = ProviderState.expired;
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
