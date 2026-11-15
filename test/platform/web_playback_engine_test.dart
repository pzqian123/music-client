import 'package:flutter_test/flutter_test.dart';
import 'package:music_client/domain/models.dart';
import 'package:music_client/platform/web_playback_engine.dart';
import 'package:music_client/presentation/widgets/hidden_web_player.dart';

void main() {
  group('parseClockDuration', () {
    test('解析 mm:ss', () {
      expect(parseClockDuration('4:38'), const Duration(minutes: 4, seconds: 38));
      expect(parseClockDuration('03:57'), const Duration(minutes: 3, seconds: 57));
    });

    test('无时间文本返回 0', () {
      expect(parseClockDuration(''), Duration.zero);
      expect(parseClockDuration('未知'), Duration.zero);
    });
  });

  group('trackFromOfficialResult', () {
    test('转换为带网易云来源的 Track', () {
      const result = OfficialSearchResult(
        id: '2652820720',
        title: '晴天(深情版)',
        artist: 'Lucky小爱',
        duration: '4:38',
      );
      final track = trackFromOfficialResult(result);

      expect(track.id, 'netease-web-2652820720');
      expect(track.title, '晴天(深情版)');
      expect(track.artist, 'Lucky小爱');
      expect(track.duration, const Duration(minutes: 4, seconds: 38));
      expect(track.sources.single.service, MusicService.netease);
      expect(track.sources.single.providerTrackId, '2652820720');
      expect(track.sources.single.playable, isTrue);
      expect(
        track.sources.single.officialHandoffUri.toString(),
        contains('music.163.com'),
      );
    });

    test('preferredSource 选中网易云来源', () {
      final track = trackFromOfficialResult(
        const OfficialSearchResult(id: '1', title: 't', artist: 'a'),
      );
      expect(track.preferredSource?.service, MusicService.netease);
    });
  });

  group('官方播放列表', () {
    test('解析曲目 ID、标题、艺人和当前项', () {
      final items = parseOfficialQueue('''
      {
        "items": [
          {
            "id": "3312508535",
            "title": "少女的祈祷",
            "artist": "杨千嬅",
            "duration": "03:38",
            "selected": true
          },
          {
            "id": "67467",
            "title": "K歌之王",
            "artist": "陈奕迅",
            "duration": "03:42"
          }
        ]
      }
      ''');

      expect(items.length, 2);
      expect(items.first.id, '3312508535');
      expect(items.first.title, '少女的祈祷');
      expect(items.first.artist, '杨千嬅');
      expect(items.first.selected, isTrue);
    });

    test('官方列表项转换为可播放网易云 Track', () {
      final track = trackFromOfficialQueueItem(
        const OfficialQueueItem(
          id: '67467',
          title: 'K歌之王',
          artist: '陈奕迅',
          duration: '03:42',
        ),
      );

      expect(track.duration, const Duration(minutes: 3, seconds: 42));
      expect(track.sourceFor(MusicService.netease)?.playable, isTrue);
      expect(
        track.sourceFor(MusicService.netease)?.providerTrackId,
        '67467',
      );
    });
  });
}
