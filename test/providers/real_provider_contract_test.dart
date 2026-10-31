import 'package:flutter_test/flutter_test.dart';
import 'package:music_client/domain/models.dart';
import 'package:music_client/platform/secure_credentials.dart';
import 'package:music_client/providers/http_client_port.dart';
import 'package:music_client/providers/music_provider.dart';
import 'package:music_client/providers/netease_provider.dart';
import 'package:music_client/providers/spotify_provider.dart';

const _searchJson = '''
{
  "tracks": {
    "items": [
      {
        "id": "abc123",
        "name": "夜空中最亮的星",
        "duration_ms": 252000,
        "artists": [{"name": "逃跑计划"}],
        "album": {"name": "世界"}
      }
    ]
  }
}
''';

void main() {
  group('SpotifyProvider', () {
    test('未配置 clientId 时 connect 抛 notConfigured', () async {
      final provider = SpotifyProvider(
        clientId: null,
        credentials: InMemoryCredentials(),
      );
      expect(
        provider.connect,
        throwsA(
          isA<ProviderException>().having(
            (e) => e.kind,
            'kind',
            ProviderErrorKind.notConfigured,
          ),
        ),
      );
    });

    test('无令牌时 search 抛 unauthorized', () async {
      final provider = SpotifyProvider(
        clientId: 'demo-client',
        credentials: InMemoryCredentials(),
        fetcher: (uri, {headers, body, contentType}) async => const HttpResponse(200, '{}'),
      );
      expect(
        () => provider.search('夜空'),
        throwsA(
          isA<ProviderException>().having(
            (e) => e.kind,
            'kind',
            ProviderErrorKind.unauthorized,
          ),
        ),
      );
    });

    test('200 响应解析为标准化 ProviderTrack', () async {
      final credentials = InMemoryCredentials();
      await credentials.write(MusicService.spotify.storageKey, 'token');

      Uri? requested;
      final provider = SpotifyProvider(
        clientId: 'demo-client',
        credentials: credentials,
        fetcher: (uri, {headers, body, contentType}) async {
          requested = uri;
          expect(headers?['Authorization'], 'Bearer token');
          return const HttpResponse(200, _searchJson);
        },
      );

      final tracks = await provider.search('夜空');
      expect(tracks.length, 1);
      expect(tracks.single.providerTrackId, 'abc123');
      expect(tracks.single.artist, '逃跑计划');
      expect(tracks.single.duration, const Duration(milliseconds: 252000));
      expect(tracks.single.playable, isFalse);
      expect(requested!.host, 'api.spotify.com');
      expect(requested!.queryParameters['q'], '夜空');
    });

    test('401 标记 expired 并抛 unauthorized', () async {
      final credentials = InMemoryCredentials();
      await credentials.write(MusicService.spotify.storageKey, 'token');
      final provider = SpotifyProvider(
        clientId: 'demo-client',
        credentials: credentials,
        fetcher: (uri, {headers, body, contentType}) async => const HttpResponse(401, '{}'),
      );

      await expectLater(provider.search('x'), throwsA(isA<ProviderException>()));
      expect(provider.snapshot.state, ProviderState.expired);
    });

    test('429 抛 rateLimited', () async {
      final credentials = InMemoryCredentials();
      await credentials.write(MusicService.spotify.storageKey, 'token');
      final provider = SpotifyProvider(
        clientId: 'demo-client',
        credentials: credentials,
        fetcher: (uri, {headers, body, contentType}) async => const HttpResponse(429, '{}'),
      );

      expect(
        () => provider.search('x'),
        throwsA(
          isA<ProviderException>().having(
            (e) => e.kind,
            'kind',
            ProviderErrorKind.rateLimited,
          ),
        ),
      );
    });

    test('空查询直接返回空，不发起请求', () async {
      var called = false;
      final provider = SpotifyProvider(
        clientId: 'demo-client',
        credentials: InMemoryCredentials(),
        fetcher: (uri, {headers, body, contentType}) async {
          called = true;
          return const HttpResponse(200, '{}');
        },
      );

      expect(await provider.search('   '), isEmpty);
      expect(called, isFalse);
    });

    test('客户端内播放明确返回 notSupported', () async {
      final provider = SpotifyProvider(
        clientId: 'demo-client',
        credentials: InMemoryCredentials(),
      );
      final result = await provider.startPlayback('abc123');
      expect(result.outcome, PlaybackStartOutcome.notSupported);
      expect(result.isStarted, isFalse);
    });

    test('能力声明不含客户端内播放', () {
      final provider = SpotifyProvider(
        clientId: 'demo-client',
        credentials: InMemoryCredentials(),
      );
      expect(provider.isDemo, isFalse);
      expect(provider.capabilities.inAppPlayback, isFalse);
      expect(provider.capabilities.officialHandoff, isTrue);
    });
  });

  group('NeteaseProvider', () {
    test('connect 抛 notConfigured 并说明原因', () async {
      final provider = NeteaseProvider(credentials: InMemoryCredentials());
      expect(
        provider.connect,
        throwsA(
          isA<ProviderException>().having(
            (e) => e.kind,
            'kind',
            ProviderErrorKind.notConfigured,
          ),
        ),
      );
    });

    test('未获资质时 search 抛 notSupported', () async {
      final provider = NeteaseProvider(credentials: InMemoryCredentials());
      expect(
        () => provider.search('夜空'),
        throwsA(
          isA<ProviderException>().having(
            (e) => e.kind,
            'kind',
            ProviderErrorKind.notSupported,
          ),
        ),
      );
    });

    test('客户端内播放明确返回 notSupported', () async {
      final provider = NeteaseProvider(credentials: InMemoryCredentials());
      final result = await provider.startPlayback('1');
      expect(result.outcome, PlaybackStartOutcome.notSupported);
    });

    test('官方跳转地址指向官方站点', () {
      final provider = NeteaseProvider(credentials: InMemoryCredentials());
      expect(
        provider.officialHandoff('123')!.toString(),
        'https://music.163.com/song?id=123',
      );
    });
  });
}
