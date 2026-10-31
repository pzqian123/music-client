import 'package:flutter_test/flutter_test.dart';
import 'package:music_client/domain/dedupe.dart';
import 'package:music_client/domain/models.dart';

ProviderTrack _spot(
  String id,
  String title, {
  String artist = '逃跑计划',
  Duration duration = const Duration(minutes: 4, seconds: 12),
  Set<String> markers = const {},
}) {
  return ProviderTrack(
    service: MusicService.spotify,
    providerTrackId: id,
    title: title,
    artist: artist,
    album: '世界',
    duration: duration,
    versionMarkers: markers,
  );
}

ProviderTrack _netease(
  String id,
  String title, {
  String artist = '逃跑计划',
  Duration duration = const Duration(minutes: 4, seconds: 12),
  Set<String> markers = const {},
}) {
  return ProviderTrack(
    service: MusicService.netease,
    providerTrackId: id,
    title: title,
    artist: artist,
    album: '世界',
    duration: duration,
    versionMarkers: markers,
  );
}

void main() {
  group('标准化', () {
    test('去标点、小写、压缩空格', () {
      expect(normalizeTitle('  Hello ， World!! '), 'hello world');
    });

    test('全角转半角', () {
      expect(normalizeTitle('ＡＢＣ'), 'abc');
    });

    test('括号内版本标记被移除', () {
      expect(normalizeTitle('夜空中最亮的星 (Live)'), '夜空中最亮的星');
    });

    test('艺人标准化去除多余空格', () {
      expect(normalizeArtist('  逃跑计划  '), '逃跑计划');
    });
  });

  group('mergeProviderTracks', () {
    test('同曲不同大小写与空格合并为一条，保留两个来源', () {
      final result = mergeProviderTracks([
        _spot('sp-1', '夜空中最亮的星'),
        _netease('ne-1', '  夜空中最亮的星 '),
      ]);
      expect(result.tracks.length, 1);
      expect(result.tracks.single.sources.length, 2);
      expect(result.confidence.values.single, 0.95);
    });

    test('时长差 5 秒仍合并，置信度 0.85', () {
      final result = mergeProviderTracks([
        _spot('sp-1', '晴天', duration: const Duration(minutes: 4, seconds: 29)),
        _netease('ne-1', '晴天',
            duration: const Duration(minutes: 4, seconds: 34)),
      ]);
      expect(result.tracks.length, 1);
      expect(result.confidence.values.single, 0.85);
    });

    test('时长差超过 8 秒不合并', () {
      final result = mergeProviderTracks([
        _spot('sp-1', '晴天', duration: const Duration(seconds: 200)),
        _netease('ne-1', '晴天', duration: const Duration(seconds: 215)),
      ]);
      expect(result.tracks.length, 2);
    });

    test('版本标记不同不合并', () {
      final result = mergeProviderTracks([
        _spot('sp-1', '夜空中最亮的星'),
        _netease('ne-1', '夜空中最亮的星 (Live)'),
      ]);
      expect(result.tracks.length, 2);
      final live = result.tracks.firstWhere((t) => t.versionMarkers.contains('live'));
      expect(live.versionMarkers, contains('live'));
    });

    test('艺人不同不合并', () {
      final result = mergeProviderTracks([
        _spot('sp-1', '晴天'),
        _netease('ne-1', '晴天', artist: '周杰伦'),
      ]);
      expect(result.tracks.length, 2);
    });

    test('provider 显式传入 versionMarkers 也参与判定', () {
      final result = mergeProviderTracks([
        _spot('sp-1', '晴天'),
        _netease('ne-1', '晴天', markers: {'remix'}),
      ]);
      expect(result.tracks.length, 2);
    });

    test('全角标题与半角标题能匹配', () {
      final result = mergeProviderTracks([
        _spot('sp-1', 'Ｈｅｌｌｏ'),
        _netease('ne-1', 'hello'),
      ]);
      expect(result.tracks.length, 1);
    });

    test('合并后 id 唯一', () {
      final result = mergeProviderTracks([
        _spot('sp-1', '晴天', duration: const Duration(seconds: 100)),
        _netease('ne-1', '晴天', duration: const Duration(seconds: 130)),
        _spot('sp-2', '晴天', duration: const Duration(seconds: 300)),
      ]);
      final ids = result.tracks.map((t) => t.id).toList();
      expect(ids.length, ids.toSet().length);
    });

    test('来源按枚举顺序稳定排列且去重', () {
      final result = mergeProviderTracks([
        _netease('ne-1', '晴天'),
        _spot('sp-1', '晴天'),
        _spot('sp-1', '晴天'),
      ]);
      expect(result.tracks.length, 1);
      expect(
        result.tracks.single.sources.map((s) => s.service).toList(),
        [MusicService.spotify, MusicService.netease],
      );
    });

    test('空输入返回空结果', () {
      final result = mergeProviderTracks(const []);
      expect(result.tracks, isEmpty);
      expect(result.confidence, isEmpty);
    });
  });
}
