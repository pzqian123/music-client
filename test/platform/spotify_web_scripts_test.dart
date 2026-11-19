import 'package:flutter_test/flutter_test.dart';
import 'package:music_client/domain/models.dart';
import 'package:music_client/platform/spotify_web_scripts.dart';
import 'package:music_client/platform/web_playback_engine.dart';
import 'package:music_client/platform/web_player_engine.dart';
import 'package:music_client/presentation/widgets/hidden_web_player.dart';

/// 可编程的假桥：记录脚本与导航，回放预置的页面状态。
class _FakeBridge implements WebPlayerBridge {
  @override
  bool isAttached = true;

  final List<String> scripts = <String>[];
  final List<String> openedTracks = <String>[];
  final List<String> homes = <String>[];

  String stateJson =
      '{"hasMedia":true,"paused":false,"position":12.5,"duration":236.3,'
      '"mediaSessionTitle":"Love Story","mediaSessionArtist":"Taylor Swift",'
      '"nowPlaying":"Love Story","source":"element"}';

  String searchJson = '{"items":[]}';

  String Function(String source)? scriptResponder;

  @override
  Future<WebPlayerState> readState() async => decodeState(stateJson);

  @override
  Future<String> runScript(String source) async {
    scripts.add(source);
    if (scriptResponder != null) {
      final response = scriptResponder!(source);
      if (response.isNotEmpty) return response;
    }
    if (source.contains('tracklist-row')) return searchJson;
    if (source.contains('action-bar-row') || source.contains('play-button')) {
      return 'clicked';
    }
    return '';
  }

  @override
  Future<void> openTrack(WebPlayerTarget target, String providerTrackId) async {
    openedTracks.add('${target.service.name}:$providerTrackId');
  }

  @override
  Future<void> openHomeFor(WebPlayerTarget target) async {
    homes.add(target.homeUrl);
  }

  @override
  Future<String> clickOfficialPlay() async => 'clicked';

  @override
  Future<String> clickSongPagePlay() async => 'clicked';

  @override
  Future<String> pageTitle() async => 'Love Story • Taylor Swift';

  @override
  Future<List<OfficialSearchResult>> searchNetease(
    String query, {
    Duration wait = const Duration(milliseconds: 10),
  }) async => const [];

  @override
  Future<void> toggle() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}
}

void main() {
  group('Spotify 搜索结果解析', () {
    const raw = '''
    {
      "count": 2,
      "href": "https://open.spotify.com/search/love/tracks",
      "items": [
        {
          "id": "63gCdrDtZlt1PMIGrzYEqt",
          "title": "Love Options",
          "artist": "BESTie",
          "duration": "3:14",
          "cover": "https://i.scdn.co/image/ab67616d00004851ffffd73723e720ebc9117046"
        },
        {
          "id": "1D4PL9B8gOg78jiHg3FvBb",
          "title": "Love Story",
          "artist": "Taylor Swift",
          "duration": "3:56",
          "cover": "https://i.scdn.co/image/ab67616d0000485160cb9332e8c8c7d8e50854b3"
        }
      ]
    }
    ''';

    test('解析曲目 ID / 标题 / 艺人 / 时长 / 封面', () {
      final results = parseSpotifySearch(raw);
      expect(results.length, 2);
      expect(results.first.id, '63gCdrDtZlt1PMIGrzYEqt');
      expect(results.first.title, 'Love Options');
      expect(results.first.artist, 'BESTie');
      expect(results.first.duration, '3:14');
      expect(results.last.title, 'Love Story');
    });

    test('非法/空输入返回空列表', () {
      expect(parseSpotifySearch(''), isEmpty);
      expect(parseSpotifySearch('not-json'), isEmpty);
      expect(parseSpotifySearch('{"items":null}'), isEmpty);
      expect(
        parseSpotifySearch('{"items":[{"id":"","title":"x"}]}'),
        isEmpty,
      );
    });

    test('转换为带 Spotify 来源的 Track（封面升级到 640px）', () {
      final track = trackFromSpotifyResult(
        const SpotifySearchResult(
          id: '1D4PL9B8gOg78jiHg3FvBb',
          title: 'Love Story',
          artist: 'Taylor Swift',
          duration: '3:56',
          cover: 'https://i.scdn.co/image/ab67616d0000485160cb9332e8c8c7d8e50854b3',
        ),
      );

      expect(track.id, 'spotify-web-1D4PL9B8gOg78jiHg3FvBb');
      expect(track.duration, const Duration(minutes: 3, seconds: 56));
      expect(track.artworkUrl, contains('ab67616d0000b273'));
      final source = track.sourceFor(MusicService.spotify);
      expect(source?.providerTrackId, '1D4PL9B8gOg78jiHg3FvBb');
      expect(source?.playable, isTrue);
      expect(
        source?.officialHandoffUri.toString(),
        'https://open.spotify.com/track/1D4PL9B8gOg78jiHg3FvBb',
      );
      expect(track.preferredSource?.service, MusicService.spotify);
    });
  });

  group('Spotify 注入脚本', () {
    test('搜索脚本指向曲目页签并编码关键词', () {
      final script = spotifySearchScript('Taylor Swift');
      expect(script, contains('open.spotify.com/search/Taylor%20Swift/tracks'));
    });

    test('排序/播放/登录脚本使用已验证的 data-testid', () {
      expect(spotifyParseSearchScript, contains('tracklist-row'));
      expect(spotifyParseSearchScript, contains('a[href*="/track/"]'));
      expect(spotifyTrackPlayScript, contains('play-button'));
      expect(spotifyTrackPlayScript, contains('already-playing'));
      expect(spotifyTogglePlayScript, contains('control-button-playpause'));
      expect(
        spotifySkipScript(forward: true),
        contains('control-button-skip-forward'),
      );
      expect(
        spotifySkipScript(forward: false),
        contains('control-button-skip-back'),
      );
      expect(spotifyLoginStateScript, contains('user-widget-link'));
    });

    test('封面尺寸段升级', () {
      expect(
        upgradeSpotifyCover(
          'https://i.scdn.co/image/ab67616d00004851ffffd73723e720ebc9117046',
        ),
        'https://i.scdn.co/image/ab67616d0000b273ffffd73723e720ebc9117046',
      );
      expect(upgradeSpotifyCover(''), '');
    });
  });

  group('WebPlaybackEngine 服务切换', () {
    test('useService 导航到对应官方首页', () async {
      final bridge = _FakeBridge();
      final engine = WebPlaybackEngine(bridge: bridge);
      expect(engine.target.homeUrl, 'https://music.163.com');

      await engine.useService(MusicService.spotify);
      expect(engine.service, MusicService.spotify);
      expect(engine.target.homeUrl, 'https://open.spotify.com');
      expect(bridge.homes, ['https://open.spotify.com']);
      engine.dispose();
    });

    test('Spotify 模式下的搜索会走官方搜索页并解析结果', () async {
      final bridge = _FakeBridge();
      bridge.searchJson =
          '{"items":[{"id":"abc123","title":"Love Story",'
          '"artist":"Taylor Swift","duration":"3:56","cover":""}]}';
      final engine = WebPlaybackEngine(bridge: bridge);
      await engine.useService(MusicService.spotify);

      final tracks = await engine.searchWeb('love');
      expect(bridge.scripts.first, contains('/search/love/tracks'));
      expect(tracks.single.title, 'Love Story');
      expect(tracks.single.sourceFor(MusicService.spotify)?.providerTrackId,
          'abc123');
      engine.dispose();
    });

    test('Spotify 播放会打开曲目页并点播放按钮', () async {
      final bridge = _FakeBridge();
      final engine = WebPlaybackEngine(bridge: bridge);
      await engine.useService(MusicService.spotify);

      final track = trackFromSpotifyResult(
        const SpotifySearchResult(
          id: '1D4PL9B8gOg78jiHg3FvBb',
          title: 'Love Story',
          artist: 'Taylor Swift',
          duration: '3:56',
        ),
      );

      final ok = await engine.playTrack(track);
      expect(ok, isTrue);
      expect(bridge.openedTracks, ['spotify:1D4PL9B8gOg78jiHg3FvBb']);
      expect(
        bridge.scripts.any((s) => s.contains('action-bar-row')),
        isTrue,
      );
      expect(engine.state.mediaSessionTitle, 'Love Story');
      engine.dispose();
    });

    test('网易云模式下不会解析 Spotify 的队列', () async {
      final bridge = _FakeBridge();
      final engine = WebPlaybackEngine(bridge: bridge);
      expect(await engine.fetchNeteaseQueue(), isEmpty);
      await engine.useService(MusicService.spotify);
      expect(await engine.fetchNeteaseQueue(), isEmpty);
      engine.dispose();
    });
  });
}
