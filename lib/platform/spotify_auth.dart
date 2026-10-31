/// Spotify 官方 OAuth（Authorization Code + PKCE）。
///
/// 只做授权与令牌管理，播放能力另行判断：
/// Spotify 不向第三方提供音频流，客户端内播放需要 Web Playback SDK（Premium）。
library;

import 'dart:convert';

import 'auth_keys.dart';
import 'oauth_flow.dart';
import 'pkce.dart';
import 'secure_credentials.dart';
import '../providers/http_client_port.dart';

const spotifyScopes = <String>[
  'user-read-playback-state',
  'user-modify-playback-state',
  'user-read-currently-playing',
  'playlist-read-private',
];

class SpotifyTokens {
  final String accessToken;
  final String? refreshToken;
  final DateTime expiresAt;
  final String scope;

  const SpotifyTokens({
    required this.accessToken,
    required this.expiresAt,
    this.refreshToken,
    this.scope = '',
  });

  /// 提前 60 秒视为过期，避免边界失败。
  bool isExpiredAt(DateTime now) =>
      now.isAfter(expiresAt.subtract(const Duration(seconds: 60)));

  bool get isExpired => isExpiredAt(DateTime.now());

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        if (refreshToken != null) 'refresh_token': refreshToken,
        'expires_at': expiresAt.toIso8601String(),
        'scope': scope,
      };

  String encode() => jsonEncode(toJson());

  static SpotifyTokens fromJson(Map<String, dynamic> json) {
    return SpotifyTokens(
      accessToken: json['access_token'] as String? ?? '',
      refreshToken: json['refresh_token'] as String?,
      expiresAt:
          DateTime.tryParse(json['expires_at'] as String? ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0),
      scope: json['scope'] as String? ?? '',
    );
  }

  static SpotifyTokens? tryDecode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return fromJson(decoded);
    } catch (_) {
      return null;
    }
    return null;
  }
}

class SpotifyAuth {
  SpotifyAuth({
    required this.clientId,
    required this.credentials,
    required HttpFetcher httpFetcher,
    required BrowserLauncher browserLauncher,
    DateTime Function()? now,
  })  : _fetcher = httpFetcher,
        _launcher = browserLauncher,
        _now = now ?? DateTime.now;

  final String clientId;
  final SecureCredentials credentials;
  final HttpFetcher _fetcher;
  final BrowserLauncher _launcher;
  final DateTime Function() _now;

  static final Uri authorizeEndpoint =
      Uri.parse('https://accounts.spotify.com/authorize');
  static final Uri tokenEndpoint =
      Uri.parse('https://accounts.spotify.com/api/token');

  Uri buildAuthorizeUrl({
    required PkcePair pkce,
    required String state,
    required Uri redirectUri,
  }) {
    return authorizeEndpoint.replace(
      queryParameters: {
        'client_id': clientId,
        'response_type': 'code',
        'redirect_uri': redirectUri.toString(),
        'code_challenge_method': pkce.method,
        'code_challenge': pkce.challenge,
        'state': state,
        'scope': spotifyScopes.join(' '),
        'show_dialog': 'false',
      },
    );
  }

  /// 完整登录：开浏览器 → 回环回调 → 换取令牌 → 写入安全存储。
  Future<SpotifyTokens> signIn({Duration timeout = const Duration(minutes: 5)}) async {
    if (clientId.isEmpty) {
      throw const OAuthException('未配置 Spotify 客户端 ID');
    }
    final pkce = generatePkcePair();
    final state = generateState();

    final server = await LocalOAuthServer.start();
    SpotifyTokens tokens;
    try {
      final url = buildAuthorizeUrl(
        pkce: pkce,
        state: state,
        redirectUri: server.redirectUri,
      );
      final opened = await _launcher(url);
      if (!opened) {
        throw const OAuthException('无法打开系统浏览器，请检查默认浏览器设置');
      }
      final callback = await server.waitForCallback(
        expectedState: state,
        timeout: timeout,
      );
      if (!callback.isSuccess) {
        throw OAuthException(
          callback.error == 'access_denied'
              ? '你取消了 Spotify 授权'
              : 'Spotify 授权失败：${callback.error ?? '未知错误'}',
        );
      }
      tokens = await exchangeCode(
        code: callback.code!,
        verifier: pkce.verifier,
        redirectUri: server.redirectUri,
      );
    } finally {
      // waitForCallback 正常路径会关闭服务器；异常路径由此兜底。
      try {
        await server.close();
      } catch (_) {
        // 已关闭则忽略。
      }
    }

    await credentials.write(spotifyTokenStorageKey, tokens.encode());
    return tokens;
  }

  Future<SpotifyTokens> exchangeCode({    required String code,
    required String verifier,
    required Uri redirectUri,
  }) async {
    final response = await _fetcher(
      tokenEndpoint,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      contentType: 'application/x-www-form-urlencoded',
      body: Uri(queryParameters: {
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': redirectUri.toString(),
        'client_id': clientId,
        'code_verifier': verifier,
      }).query,
    );
    final tokens = _parseTokenResponse(response);
    await credentials.write(spotifyTokenStorageKey, tokens.encode());
    return tokens;
  }

  Future<SpotifyTokens> refresh(SpotifyTokens current) async {
    final refreshToken = current.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      throw const OAuthException('没有刷新令牌，请重新登录');
    }
    final response = await _fetcher(
      tokenEndpoint,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      contentType: 'application/x-www-form-urlencoded',
      body: Uri(queryParameters: {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': clientId,
      }).query,
    );
    final parsed = _parseTokenResponse(response);
    // 刷新响应可能不返回新的 refresh_token，沿用旧的。
    final merged = SpotifyTokens(
      accessToken: parsed.accessToken,
      refreshToken: parsed.refreshToken ?? refreshToken,
      expiresAt: parsed.expiresAt,
      scope: parsed.scope.isEmpty ? current.scope : parsed.scope,
    );
    await credentials.write(spotifyTokenStorageKey, merged.encode());
    return merged;
  }

  SpotifyTokens _parseTokenResponse(HttpResponse response) {
    if (response.statusCode != 200) {
      String detail = 'HTTP ${response.statusCode}';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final error = decoded['error'];
          final description = decoded['error_description'];
          if (error is String) {
            detail = description is String ? '$error: $description' : error;
          }
        }
      } catch (_) {
        // body 不是 JSON 时用状态码。
      }
      throw OAuthException('Spotify 授权失败（$detail）');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const OAuthException('Spotify 返回了无法解析的令牌响应');
    }
    final accessToken = decoded['access_token'] as String?;
    if (accessToken == null || accessToken.isEmpty) {
      throw const OAuthException('Spotify 未返回访问令牌');
    }
    final expiresIn = (decoded['expires_in'] as num?)?.toInt() ?? 3600;
    return SpotifyTokens(
      accessToken: accessToken,
      refreshToken: decoded['refresh_token'] as String?,
      expiresAt: _now().add(Duration(seconds: expiresIn)),
      scope: decoded['scope'] as String? ?? '',
    );
  }

  Future<SpotifyTokens?> loadTokens() async {
    return SpotifyTokens.tryDecode(
      await credentials.read(spotifyTokenStorageKey),
    );
  }

  /// 需要时自动刷新，返回可用令牌。
  Future<SpotifyTokens?> ensureFresh() async {
    final tokens = await loadTokens();
    if (tokens == null) return null;
    if (!tokens.isExpiredAt(_now())) return tokens;
    return refresh(tokens);
  }

  Future<void> signOut() => credentials.delete(spotifyTokenStorageKey);
}
