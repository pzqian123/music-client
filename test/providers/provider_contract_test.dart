import 'package:flutter_test/flutter_test.dart';
import 'package:music_client/domain/lyrics.dart';
import 'package:music_client/domain/models.dart';
import 'package:music_client/providers/fake_netease_provider.dart';
import 'package:music_client/providers/fake_spotify_provider.dart';
import 'package:music_client/providers/music_provider.dart';

void main() {
  group('FakeSpotifyProvider', () {
    late FakeSpotifyProvider provider;

    setUp(() => provider = FakeSpotifyProvider());

    test('身份与能力', () {
      expect(provider.service, MusicService.spotify);
      expect(provider.displayName, 'Spotify');
      expect(provider.isDemo, isTrue);
      expect(provider.capabilities.search, isTrue);
      expect(provider.capabilities.inAppPlayback, isFalse);
      expect(provider.capabilities.officialHandoff, isTrue);
      expect(provider.snapshot.state, ProviderState.connected);
    });

    test('空查询返回空列表', () async {
      expect(await provider.search('   '), isEmpty);
    });

    test('按标题与艺人匹配', () async {
      final byTitle = await provider.search('夜空中');
      expect(byTitle.length, 2); // 原曲 + Live 版
      final byArtist = await provider.search('queen');
      expect(byArtist.single.providerTrackId, 'sp-4');
    });

    test('客户端内播放返回 requiresSubscription', () async {
      final result = await provider.startPlayback('sp-1');
      expect(result.outcome, PlaybackStartOutcome.requiresSubscription);
      expect(result.isStarted, isFalse);
      expect(result.message, isNotNull);
    });

    test('shouldFail 时抛 ProviderException', () async {
      provider.shouldFail = true;
      expect(
        () => provider.search('夜空'),
        throwsA(isA<ProviderException>()),
      );
    });

    test('歌词：行级与无歌词', () async {
      final lineLevel = await provider.lyricsFor('sp-1');
      expect(lineLevel, isNotNull);
      expect(lineLevel!.mode, LyricSyncMode.line);

      final none = await provider.lyricsFor('sp-4');
      expect(none, isNull);
    });

    test('官方跳转地址存在', () {
      expect(provider.officialHandoff('sp-1'), isNotNull);
      expect(provider.officialHandoff('不存在'), isNull);
    });
  });

  group('FakeNeteaseProvider', () {
    late FakeNeteaseProvider provider;

    setUp(() => provider = FakeNeteaseProvider());

    test('身份与能力', () {
      expect(provider.service, MusicService.netease);
      expect(provider.displayName, '网易云音乐');
      expect(provider.capabilities.inAppPlayback, isTrue);
      expect(provider.snapshot.state, ProviderState.connected);
    });

    test('客户端内播放返回 started', () async {
      final result = await provider.startPlayback('ne-1');
      expect(result.outcome, PlaybackStartOutcome.started);
      expect(result.isStarted, isTrue);
    });

    test('歌词四种状态齐备', () async {
      final word = await provider.lyricsFor('ne-1');
      expect(word, isNotNull);
      expect(word!.mode, LyricSyncMode.word);

      final staticLyrics = await provider.lyricsFor('ne-3');
      expect(staticLyrics!.mode, LyricSyncMode.static);

      expect(await provider.lyricsFor('ne-4'), isNull);
    });

    test('disconnect 后状态为未连接', () async {
      await provider.disconnect();
      expect(provider.snapshot.state, ProviderState.disconnected);
      await provider.connect();
      expect(provider.snapshot.state, ProviderState.connected);
    });
  });

  test('两个 Provider 的错误互不影响', () async {
    final spotify = FakeSpotifyProvider()..shouldFail = true;
    final netease = FakeNeteaseProvider();

    await expectLater(spotify.search('晴天'), throwsA(isA<ProviderException>()));
    final results = await netease.search('晴天');
    expect(results, isNotEmpty);
  });
}
