import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_client/platform/auth_keys.dart';
import 'package:music_client/platform/oauth_flow.dart';
import 'package:music_client/platform/pkce.dart';
import 'package:music_client/platform/secure_credentials.dart';
import 'package:music_client/platform/spotify_auth.dart';
import 'package:music_client/providers/http_client_port.dart';

const _tokenJson = '''
{
  "access_token": "access-1234567890abcdef",
  "token_type": "Bearer",
  "expires_in": 3600,
  "refresh_token": "refresh-1234567890abcdef",
  "scope": "user-read-playback-state"
}
''';

void main() {
  group('PKCE', () {
    test('verifier 长度与字符集符合 RFC 7636', () {
      final verifier = generateCodeVerifier();
      expect(verifier.length, 64);
      expect(RegExp(r'^[A-Za-z0-9\-._~]+$').hasMatch(verifier), isTrue);
    });

    test('challenge 为 BASE64URL 且不含补位', () {
      final challenge = codeChallengeFor('abc123');
      expect(challenge.contains('='), isFalse);
      expect(challenge.contains('+'), isFalse);
      expect(challenge.contains('/'), isFalse);
    });

    test('已知向量：challenge 与 verifier 一一对应', () {
      // RFC 7636 附录 B 的示例 verifier。
      const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
      expect(
        codeChallengeFor(verifier),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      );
    });

    test('state 随机且长度固定', () {
      expect(generateState().length, 24);
      expect(generateState(), isNot(generateState()));
    });
  });

  group('本地回环回调', () {
    test('收到授权码后返回成功并携带 state', () async {
      final server = await LocalOAuthServer.start();
      const state = 'test-state';

      final future = server.waitForCallback(
        expectedState: state,
        timeout: const Duration(seconds: 5),
      );

      final response = await HttpClient().getUrl(
        Uri.parse('${server.redirectUri}?code=abc&state=$state'),
      );
      await response.close();

      final result = await future;
      expect(result.isSuccess, isTrue);
      expect(result.code, 'abc');
    });

    test('state 不匹配时返回错误而不是授权码', () async {
      final server = await LocalOAuthServer.start();

      final future = server.waitForCallback(
        expectedState: 'expected',
        timeout: const Duration(seconds: 5),
      );

      final request = await HttpClient().getUrl(
        Uri.parse('${server.redirectUri}?code=abc&state=wrong'),
      );
      await request.close();

      final result = await future;
      expect(result.isSuccess, isFalse);
      expect(result.error, 'state_mismatch');
    });

    test('浏览器拒绝打开时抛 OAuthException', () async {
      final server = await LocalOAuthServer.start();
      await server.close();

      expect(
        () => runLoopbackOAuth(
          authorizationUrl: Uri.parse('https://example.com/authorize'),
          expectedState: 'x',
          launcher: (_) async => false,
        ),
        throwsA(isA<OAuthException>()),
      );
    });
  });

  group('SpotifyAuth', () {
    late InMemoryCredentials credentials;

    setUp(() => credentials = InMemoryCredentials());

    test('授权 URL 带 PKCE 与 state，且 scope 正确', () {
      final auth = SpotifyAuth(
        clientId: 'client-abc',
        credentials: credentials,
        httpFetcher: disabledFetcher,
        browserLauncher: (_) async => true,
      );
      final pkce = generatePkcePair();
      final url = auth.buildAuthorizeUrl(
        pkce: pkce,
        state: 'st-1',
        redirectUri: Uri.parse('http://127.0.0.1:8080/callback'),
      );

      expect(url.host, 'accounts.spotify.com');
      expect(url.queryParameters['client_id'], 'client-abc');
      expect(url.queryParameters['response_type'], 'code');
      expect(url.queryParameters['code_challenge_method'], 'S256');
      expect(url.queryParameters['code_challenge'], pkce.challenge);
      expect(url.queryParameters['state'], 'st-1');
      expect(url.queryParameters.containsKey('scope'), isFalse);
      expect(
        url.queryParameters['redirect_uri'],
        'http://127.0.0.1:8080/callback',
      );
    });

    test('用授权码换取令牌并写入安全存储', () async {
      Uri? posted;
      String? postedBody;
      final auth = SpotifyAuth(
        clientId: 'client-abc',
        credentials: credentials,
        httpFetcher: (uri, {headers, body, contentType}) async {
          posted = uri;
          postedBody = body;
          return const HttpResponse(200, _tokenJson);
        },
        browserLauncher: (_) async => true,
        now: () => DateTime(2026, 1, 1, 12),
      );

      final tokens = await auth.exchangeCode(
        code: 'the-code',
        verifier: 'the-verifier',
        redirectUri: Uri.parse('http://127.0.0.1:8080/callback'),
      );

      expect(posted!.host, 'accounts.spotify.com');
      expect(posted!.path, '/api/token');
      expect(postedBody, contains('grant_type=authorization_code'));
      expect(postedBody, contains('code_verifier=the-verifier'));
      expect(tokens.accessToken, 'access-1234567890abcdef');
      expect(tokens.refreshToken, 'refresh-1234567890abcdef');
      expect(tokens.expiresAt, DateTime(2026, 1, 1, 13));

      final stored = await credentials.read(spotifyTokenStorageKey);
      expect(stored, isNotNull);
      expect(stored, contains('access-1234567890abcdef'));
    });

    test('令牌接口非 200 时抛 OAuthException 并带错误原因', () async {
      final auth = SpotifyAuth(
        clientId: 'client-abc',
        credentials: credentials,
        httpFetcher: (uri, {headers, body, contentType}) async =>
            const HttpResponse(400, '{"error":"invalid_grant"}'),
        browserLauncher: (_) async => true,
      );

      expect(
        () => auth.exchangeCode(
          code: 'bad',
          verifier: 'v',
          redirectUri: Uri.parse('http://127.0.0.1:1/callback'),
        ),
        throwsA(
          isA<OAuthException>().having(
            (e) => e.message,
            'message',
            contains('invalid_grant'),
          ),
        ),
      );
    });

    test('刷新令牌沿用旧 refresh_token 并更新存储', () async {
      final auth = SpotifyAuth(
        clientId: 'client-abc',
        credentials: credentials,
        httpFetcher: (uri, {headers, body, contentType}) async {
          expect(body, contains('grant_type=refresh_token'));
          return const HttpResponse(
            200,
            '{"access_token":"new-access-token-123456","expires_in":3600}',
          );
        },
        browserLauncher: (_) async => true,
      );

      final refreshed = await auth.refresh(
        SpotifyTokens(
          accessToken: 'old',
          refreshToken: 'keep-me',
          expiresAt: DateTime(2020),
        ),
      );

      expect(refreshed.accessToken, 'new-access-token-123456');
      expect(refreshed.refreshToken, 'keep-me');
      final stored = SpotifyTokens.tryDecode(
        await credentials.read(spotifyTokenStorageKey),
      );
      expect(stored!.refreshToken, 'keep-me');
    });

    test('没有 refresh_token 时刷新直接报错', () async {
      final auth = SpotifyAuth(
        clientId: 'client-abc',
        credentials: credentials,
        httpFetcher: disabledFetcher,
        browserLauncher: (_) async => true,
      );

      expect(
        () => auth.refresh(
          SpotifyTokens(accessToken: 'a', expiresAt: DateTime(2020)),
        ),
        throwsA(isA<OAuthException>()),
      );
    });

    test('过期判定提前 60 秒', () {
      final tokens = SpotifyTokens(
        accessToken: 'a',
        expiresAt: DateTime(2026, 1, 1, 12, 0, 30),
      );
      expect(tokens.isExpiredAt(DateTime(2026, 1, 1, 12, 0, 0)), isTrue);
      expect(tokens.isExpiredAt(DateTime(2026, 1, 1, 11, 59, 0)), isFalse);
    });

    test('损坏的存储内容不会抛异常', () {
      expect(SpotifyTokens.tryDecode('not-json'), isNull);
      expect(SpotifyTokens.tryDecode(''), isNull);
      expect(SpotifyTokens.tryDecode(null), isNull);
    });
  });
}
