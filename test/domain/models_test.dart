import 'package:flutter_test/flutter_test.dart';
import 'package:music_client/domain/models.dart';

Track _track({List<TrackSource>? sources}) {
  return Track(
    id: 'k',
    title: '夜空中最亮的星',
    artist: '逃跑计划',
    album: '世界',
    duration: const Duration(minutes: 4, seconds: 12),
    sources: sources ?? const [],
  );
}

void main() {
  group('TrackSource 与 Track', () {
    test('sourceFor 命中与未命中', () {
      const source = TrackSource(
        service: MusicService.netease,
        providerTrackId: 'ne-1',
        playable: true,
      );
      final track = _track(sources: [source]);

      expect(track.sourceFor(MusicService.netease), same(source));
      expect(track.sourceFor(MusicService.spotify), isNull);
    });

    test('preferredSource 优先可播放来源', () {
      const spotify = TrackSource(
        service: MusicService.spotify,
        providerTrackId: 'sp-1',
        playable: false,
      );
      const netease = TrackSource(
        service: MusicService.netease,
        providerTrackId: 'ne-1',
        playable: true,
      );
      final track = _track(sources: [spotify, netease]);

      expect(track.preferredSource, netease);
      expect(track.hasPlayableSource, isTrue);
    });

    test('preferredSource 在全部不可播放时返回第一个', () {
      const a = TrackSource(
        service: MusicService.spotify,
        providerTrackId: 'sp-1',
        playable: false,
      );
      const b = TrackSource(
        service: MusicService.netease,
        providerTrackId: 'ne-1',
        playable: false,
      );
      final track = _track(sources: [a, b]);

      expect(track.preferredSource, a);
      expect(track.hasPlayableSource, isFalse);
    });

    test('preferredSource 在无来源时返回 null', () {
      expect(_track().preferredSource, isNull);
    });

    test('Track 相等性按 id', () {
      final a = _track();
      final b = _track();
      final c = Track(
        id: 'other',
        title: 'x',
        artist: 'y',
        album: 'z',
        duration: Duration.zero,
      );
      expect(a, b);
      expect(a, isNot(c));
    });

    test('sources 不可被外部修改', () {
      final track = _track(sources: const [
        TrackSource(
          service: MusicService.spotify,
          providerTrackId: 'sp-1',
          playable: true,
        ),
      ]);
      expect(() => track.sources.add(track.sources.first), throwsUnsupportedError);
    });
  });

  group('ProviderCapabilities', () {
    test('copyWith 只改指定项', () {
      const caps = ProviderCapabilities(
        search: true,
        metadata: true,
        lyrics: false,
        inAppPlayback: false,
        officialHandoff: true,
      );
      final updated = caps.copyWith(inAppPlayback: true);
      expect(updated.inAppPlayback, isTrue);
      expect(updated.search, isTrue);
      expect(updated.lyrics, isFalse);
    });

    test('none 全部为 false', () {
      expect(ProviderCapabilities.none.search, isFalse);
      expect(ProviderCapabilities.none.inAppPlayback, isFalse);
    });
  });
}
