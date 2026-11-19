import 'package:flutter_test/flutter_test.dart';
import 'package:music_client/application/music_controller.dart';
import 'package:music_client/application/playback_clock.dart';
import 'package:music_client/domain/models.dart';
import 'package:music_client/platform/official_handoff.dart';
import 'package:music_client/platform/secure_credentials.dart';
import 'package:music_client/platform/web_playback_engine.dart';
import 'package:music_client/platform/web_player_engine.dart';
import 'package:music_client/presentation/widgets/hidden_web_player.dart';

/// 每家的假桥：按服务返回搜索结果 / 歌词，并记录播放调用。
class _ServiceBridge implements WebPlayerBridge {
  _ServiceBridge(this.service);

  final MusicService service;
  final List<String> playedTracks = [];
  bool paused = true;

  @override
  bool get isAttached => true;

  WebPlayerState _state = const WebPlayerState.empty();

  @override
  Future<WebPlayerState> readState() async => _state;

  @override
  Future<void> openTrack(WebPlayerTarget target, String id) async {
    playedTracks.add(id);
    _state = WebPlayerState(
      hasMedia: true,
      paused: false,
      position: const Duration(seconds: 3),
      duration: const Duration(minutes: 3, seconds: 56),
      mediaSessionTitle: 'Love Story',
      mediaSessionArtist: 'Taylor Swift',
      nowPlaying: 'Love Story',
    );
  }

  @override
  Future<String> runScript(String source) async {
    if (service == MusicService.spotify) {
      if (source.contains('tracklist-row')) {
        return '{"items":[{"id":"sp-love","title":"Love Story",'
            '"artist":"Taylor Swift","duration":"3:56","cover":""}]}';
      }
      if (source.contains('action-bar-row') || source.contains('play-button')) {
        return 'clicked';
      }
      if (source.contains('user-widget-link')) {
        return '{"loggedIn":true,"hasPlayerBar":true}';
      }
      return '';
    }
    // 网易云：搜索返回同曲，歌词脚本返回带时间戳的 LRC。
    if (source.contains('srchsongst')) {
      return '{"items":[{"id":"ne-love","title":"Love Story",'
          '"artist":"Taylor Swift","duration":"03:55"}]}';
    }
    if (source.contains('__dshLyric')) {
      return '{"status":"ok","lrc":"[00:01.00]We were both young"}';
    }
    if (source.contains('__dshLyricRead') ||
        source.contains('window.__dshLyric ||')) {
      return '{"status":"ok","lrc":"[00:01.00]We were both young"}';
    }
    return '';
  }

  @override
  Future<List<OfficialSearchResult>> searchNetease(
    String query, {
    Duration wait = const Duration(milliseconds: 10),
  }) async {
    return const [
      OfficialSearchResult(
        id: 'ne-love',
        title: 'Love Story',
        artist: 'Taylor Swift',
        duration: '03:55',
      ),
    ];
  }

  @override
  Future<void> openHomeFor(WebPlayerTarget target) async {}

  @override
  Future<String> clickOfficialPlay() async => 'clicked';

  @override
  Future<String> clickSongPagePlay() async => 'clicked';

  @override
  Future<String> pageTitle() async => '';

  @override
  Future<void> toggle() async {
    paused = !paused;
  }

  @override
  Future<void> play() async {
    paused = false;
  }

  @override
  Future<void> pause() async {
    paused = true;
  }

  @override
  Future<void> seek(Duration position) async {}
}

class _ManualClock implements PlaybackClock {
  final List<Duration> _positions = [];
  @override
  Stream<Duration> get positions => const Stream.empty();
  @override
  void start() {}
  @override
  void pause() {}
  @override
  void seek(Duration position) {
    _positions.add(position);
  }

  @override
  Future<void> dispose() async {}
}

class _NoHandoff implements OfficialHandoff {
  const _NoHandoff();
  @override
  Future<bool> open(Uri uri) async => true;
}

void main() {
  MusicController buildController(
    Map<MusicService, WebPlaybackEngine> engines,
  ) {
    return MusicController(
      providers: const [],
      clock: _ManualClock(),
      credentials: InMemoryCredentials(),
      handoff: const _NoHandoff(),
      webEngines: engines,
    );
  }

  test('一次搜索同时返回两个平台的官方页面结果', () async {
    final neteaseBridge = _ServiceBridge(MusicService.netease);
    final spotifyBridge = _ServiceBridge(MusicService.spotify);
    final engines = {
      MusicService.netease: WebPlaybackEngine(
        bridge: neteaseBridge,
        initialService: MusicService.netease,
        pollInterval: const Duration(milliseconds: 20),
      ),
      MusicService.spotify: WebPlaybackEngine(
        bridge: spotifyBridge,
        initialService: MusicService.spotify,
        pollInterval: const Duration(milliseconds: 20),
      ),
    };
    final controller = buildController(engines);
    addTearDown(controller.dispose);
    for (final engine in engines.values) {
      addTearDown(engine.dispose);
    }

    await controller.searchFor('love');

    expect(controller.usedOfficialSearch, isTrue);
    final services = controller.search.results
        .expand((track) => track.sources)
        .map((source) => source.service)
        .toSet();
    expect(services.contains(MusicService.netease), isTrue);
    expect(services.contains(MusicService.spotify), isTrue);
    // 两家同曲会被合并成一条、带两个来源。
    expect(
      controller.search.results.any((track) => track.sources.length == 2),
      isTrue,
    );
  });

  test('Spotify 播放时会去网易云取同曲歌词', () async {
    final neteaseEngine = WebPlaybackEngine(
      bridge: _ServiceBridge(MusicService.netease),
      initialService: MusicService.netease,
      pollInterval: const Duration(milliseconds: 20),
    );
    final spotifyEngine = WebPlaybackEngine(
      bridge: _ServiceBridge(MusicService.spotify),
      initialService: MusicService.spotify,
      pollInterval: const Duration(milliseconds: 20),
    );
    final controller = buildController({
      MusicService.netease: neteaseEngine,
      MusicService.spotify: spotifyEngine,
    });
    addTearDown(controller.dispose);
    addTearDown(neteaseEngine.dispose);
    addTearDown(spotifyEngine.dispose);

    final track = Track(
      id: 'spotify-web-sp-love',
      title: 'Love Story',
      artist: 'Taylor Swift',
      album: '',
      duration: const Duration(minutes: 3, seconds: 56),
      sources: const [
        TrackSource(
          service: MusicService.spotify,
          providerTrackId: 'sp-love',
          playable: true,
        ),
      ],
    );

    await controller.selectTrack(track);

    expect(controller.playback.activeService, MusicService.spotify);
    expect(spotifyEngine.service, MusicService.spotify);
    // 歌词来自网易云页面（跨服务匹配），不是空的。
    expect(controller.lyrics, isNotNull);
    expect(controller.lyrics!.lines, isNotEmpty);
  });

  test('切到另一家播放会先暂停上一家', () async {
    final neteaseBridge = _ServiceBridge(MusicService.netease);
    final spotifyBridge = _ServiceBridge(MusicService.spotify);
    final neteaseEngine = WebPlaybackEngine(
      bridge: neteaseBridge,
      initialService: MusicService.netease,
      pollInterval: const Duration(milliseconds: 20),
    );
    final spotifyEngine = WebPlaybackEngine(
      bridge: spotifyBridge,
      initialService: MusicService.spotify,
      pollInterval: const Duration(milliseconds: 20),
    );
    final controller = buildController({
      MusicService.netease: neteaseEngine,
      MusicService.spotify: spotifyEngine,
    });
    addTearDown(controller.dispose);
    addTearDown(neteaseEngine.dispose);
    addTearDown(spotifyEngine.dispose);

    final neteaseTrack = Track(
      id: 'netease-web-ne-1',
      title: '晴天',
      artist: '周杰伦',
      album: '',
      duration: const Duration(minutes: 4, seconds: 29),
      sources: const [
        TrackSource(
          service: MusicService.netease,
          providerTrackId: 'ne-1',
          playable: true,
        ),
      ],
    );
    final spotifyTrack = Track(
      id: 'spotify-web-sp-1',
      title: 'Love Story',
      artist: 'Taylor Swift',
      album: '',
      duration: const Duration(minutes: 3, seconds: 56),
      sources: const [
        TrackSource(
          service: MusicService.spotify,
          providerTrackId: 'sp-1',
          playable: true,
        ),
      ],
    );

    await controller.selectTrack(neteaseTrack);
    expect(controller.playback.activeService, MusicService.netease);

    await controller.selectTrack(spotifyTrack);
    expect(controller.playback.activeService, MusicService.spotify);
    // 上一家被暂停，保证同一时刻只有一家在出声。
    expect(neteaseBridge.paused, isTrue);
  });
}
