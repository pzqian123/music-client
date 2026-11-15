import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_client/application/music_controller.dart';
import 'package:music_client/application/playback_clock.dart';
import 'package:music_client/domain/lyrics.dart';
import 'package:music_client/domain/models.dart';
import 'package:music_client/domain/playback.dart';
import 'package:music_client/platform/official_handoff.dart';
import 'package:music_client/platform/secure_credentials.dart';
import 'package:music_client/platform/web_playback_engine.dart';
import 'package:music_client/platform/web_player_engine.dart';
import 'package:music_client/platform/web_player_scripts.dart';
import 'package:music_client/presentation/widgets/hidden_web_player.dart';
import 'package:music_client/providers/fake_netease_provider.dart';
import 'package:music_client/providers/fake_spotify_provider.dart';
import 'package:music_client/providers/http_client_port.dart';
import 'package:music_client/providers/music_provider.dart';
import 'package:music_client/providers/spotify_provider.dart';

/// 可脚本化的测试 Provider：用于验证并发与竞态。
class ScriptedProvider implements MusicProvider {
  ScriptedProvider(this.service);

  @override
  final MusicService service;

  final List<Completer<List<ProviderTrack>>> pending = [];

  @override
  String get displayName => service.displayName;

  @override
  bool get isDemo => true;

  @override
  ProviderCapabilities get capabilities => ProviderCapabilities.none;

  @override
  ProviderSnapshot get snapshot => ProviderSnapshot(
    service: service,
    state: ProviderState.connected,
    capabilities: ProviderCapabilities.none,
  );

  @override
  Future<List<ProviderTrack>> search(String query) {
    final completer = Completer<List<ProviderTrack>>();
    pending.add(completer);
    return completer.future;
  }

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<LyricTimeline?> lyricsFor(String providerTrackId) async => null;

  @override
  Future<PlaybackStartResult> startPlayback(String providerTrackId) async =>
      const PlaybackStartResult.started();

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {}

  @override
  Uri? officialHandoff(String providerTrackId) => null;
}

class _WebSearchBridge implements WebPlayerBridge {
  @override
  bool get isAttached => true;

  @override
  Future<WebPlayerState> readState() async => const WebPlayerState.empty();

  @override
  Future<void> toggle() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> openTrack(WebPlayerTarget target, String id) async {}

  @override
  Future<String> clickOfficialPlay() async => 'no-play-button';

  @override
  Future<String> clickSongPagePlay() async => 'no-play-button';

  @override
  Future<String> pageTitle() async => '';

  @override
  Future<void> openHomeFor(WebPlayerTarget target) async {}

  @override
  Future<String> runScript(String source) async =>
      jsonEncode({'status': 'ok', 'items': <Object>[]});

  @override
  Future<List<OfficialSearchResult>> searchNetease(
    String query, {
    Duration wait = const Duration(milliseconds: 0),
  }) async =>
      const [
        OfficialSearchResult(
          id: 'web-1',
          title: '晴天',
          artist: '周杰伦',
          duration: '4:29',
        ),
      ];
}

class _MutableWebBridge implements WebPlayerBridge {
  _MutableWebBridge(this.tracksById);

  final Map<String, Track> tracksById;
  WebPlayerState current = const WebPlayerState.empty();

  @override
  bool get isAttached => true;

  @override
  Future<WebPlayerState> readState() async => current;

  @override
  Future<void> openTrack(WebPlayerTarget target, String id) async {
    final track = tracksById[id];
    if (track == null) return;
    current = WebPlayerState(
      hasMedia: true,
      paused: false,
      position: Duration.zero,
      duration: track.duration,
      nowPlaying: track.title,
    );
  }

  @override
  Future<void> toggle() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {
    current = WebPlayerState(
      hasMedia: current.hasMedia,
      paused: current.paused,
      ended: current.ended,
      position: position,
      duration: current.duration,
      volume: current.volume,
      pageTitle: current.pageTitle,
      nowPlaying: current.nowPlaying,
      source: current.source,
    );
  }

  @override
  Future<String> clickOfficialPlay() async => 'clicked';

  @override
  Future<String> clickSongPagePlay() async => 'clicked';

  @override
  Future<String> pageTitle() async => current.pageTitle;

  @override
  Future<void> openHomeFor(WebPlayerTarget target) async {}

  @override
  Future<String> runScript(String source) async =>
      jsonEncode({'status': 'ok', 'items': <Object>[]});

  @override
  Future<List<OfficialSearchResult>> searchNetease(
    String query, {
    Duration wait = const Duration(milliseconds: 0),
  }) async =>
      const [];
}

class _OfficialQueueWebBridge extends _MutableWebBridge {
  _OfficialQueueWebBridge(super.tracksById);

  @override
  Future<String> runScript(String source) async {
    if (source == neteaseQueueReadScript) {
      return jsonEncode({
        'items': [
          {
            'id': 'ne-first',
            'title': '夜空中最亮的星',
            'artist': '逃跑计划',
            'duration': '04:12',
          },
          {
            'id': 'ne-second',
            'title': '晴天',
            'artist': '周杰伦',
            'duration': '04:29',
          },
        ],
      });
    }
    if (source == neteaseQueuePlayScript('ne-second')) {
      final track = tracksById['ne-second']!;
      current = WebPlayerState(
        hasMedia: true,
        paused: false,
        position: Duration.zero,
        duration: track.duration,
        nowPlaying: track.title,
        nowPlayingId: 'ne-second',
        mediaSessionTitle: track.title,
        mediaSessionArtist: track.artist,
      );
      return 'clicked';
    }
    return super.runScript(source);
  }
}

class _Harness {
  _Harness() {
    spotify = FakeSpotifyProvider();
    netease = FakeNeteaseProvider();
    clock = ManualClock();
    handoff = FakeHandoff();
    controller = MusicController(
      providers: [spotify, netease],
      clock: clock,
      credentials: InMemoryCredentials(),
      handoff: handoff,
    );
  }

  late final FakeSpotifyProvider spotify;
  late final FakeNeteaseProvider netease;
  late final ManualClock clock;
  late final FakeHandoff handoff;
  late final MusicController controller;
}

void main() {
  test('重复播放入队同一首歌不会产生重复条目', () async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);

    await harness.controller.searchFor('夜空');
    final track = harness.controller.search.results.first;

    await harness.controller.selectTrack(track);
    final queueLength = harness.controller.playback.queue.length;
    await harness.controller.selectTrack(track);

    expect(harness.controller.playback.queue.length, queueLength);
    expect(
      harness.controller.playback.queue.where((t) => t.id == track.id).length,
      1,
    );
  });

  test('enqueue 同一首歌只入队一次', () async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);

    await harness.controller.searchFor('夜空');
    final track = harness.controller.search.results.first;

    harness.controller.enqueue(track);
    harness.controller.enqueue(track);

    expect(harness.controller.playback.queue.length, 1);
  });

  test('再次点击已在队列中的歌会跳到该曲目而不是追加', () async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);

    await harness.controller.searchFor('夜空');
    final results = harness.controller.search.results;
    if (results.length < 2) return;

    await harness.controller.selectTrack(results[0]);
    await harness.controller.selectTrack(results[1]);
    await harness.controller.selectTrack(results[0]);

    expect(harness.controller.playback.queue.length, 2);
    expect(harness.controller.playback.queueIndex, 0);
    expect(harness.controller.playback.current?.id, results[0].id);
  });

  test('搜索会合并两个服务的同曲', () async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);

    await harness.controller.searchFor('夜空');

    final results = harness.controller.search.results;
    expect(results, isNotEmpty);
    final merged = results.firstWhere(
      (track) => track.sources.length == 2,
      orElse: () => fail('没有找到合并后的曲目'),
    );
    expect(merged.title, contains('夜空'));
    expect(harness.controller.search.errors, isEmpty);
  });

  test('单个服务失败时另一方结果仍可见', () async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);
    harness.spotify.shouldFail = true;

    await harness.controller.searchFor('晴天');

    expect(harness.controller.search.results, isNotEmpty);
    expect(
      harness.controller.search.errors.containsKey(MusicService.spotify),
      isTrue,
    );
    expect(
      harness.controller.search.errors.containsKey(MusicService.netease),
      isFalse,
    );
  });

  test('空查询清空结果且不进入加载态', () async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);

    await harness.controller.searchFor('晴天');
    expect(harness.controller.search.results, isNotEmpty);

    await harness.controller.searchFor('   ');
    expect(harness.controller.search.results, isEmpty);
    expect(harness.controller.search.loading, isFalse);
  });

  test('过期搜索结果不会覆盖新结果', () async {
    final scripted = ScriptedProvider(MusicService.spotify);
    final controller = MusicController(
      providers: [scripted],
      clock: ManualClock(),
      credentials: InMemoryCredentials(),
      handoff: FakeHandoff(),
    );
    addTearDown(controller.dispose);

    final first = controller.searchFor('a');
    final second = controller.searchFor('b');
    expect(scripted.pending.length, 2);

    scripted.pending[0].complete([
      const ProviderTrack(
        service: MusicService.spotify,
        providerTrackId: 'a-1',
        title: 'A 的结果',
        artist: 'x',
        album: 'x',
        duration: Duration(minutes: 3),
      ),
    ]);
    scripted.pending[1].complete([
      const ProviderTrack(
        service: MusicService.spotify,
        providerTrackId: 'b-1',
        title: 'B 的结果',
        artist: 'x',
        album: 'x',
        duration: Duration(minutes: 3),
      ),
    ]);
    await Future.wait([first, second]);

    expect(controller.search.query, 'b');
    expect(controller.search.results.single.title, 'B 的结果');
  });

  test('默认选择可播放来源并进入播放态', () async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);

    await harness.controller.searchFor('夜空中');
    final track = harness.controller.search.results.firstWhere(
      (item) => item.sources.length == 2,
    );

    await harness.controller.selectTrack(track);

    expect(harness.controller.playback.status, PlaybackStatus.playing);
    expect(harness.controller.playback.activeService, MusicService.netease);
    expect(harness.controller.playback.current, track);
  });

  test('选择无权限的来源时进入 blocked 并记录原因', () async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);

    await harness.controller.searchFor('夜空中');
    final track = harness.controller.search.results.firstWhere(
      (item) => item.sources.length == 2,
    );

    await harness.controller.selectTrack(track, service: MusicService.spotify);

    expect(harness.controller.playback.status, PlaybackStatus.blocked);
    expect(
      harness.controller.playback.blockReason,
      BlockReason.requiresSubscription,
    );
    expect(harness.controller.playback.message, isNotNull);
  });

  test('选中逐字歌词曲目后加载 word 时间轴', () async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);

    await harness.controller.searchFor('夜空');
    final track = harness.controller.search.results.firstWhere(
      (item) => item.sources.length == 2,
    );
    await harness.controller.selectTrack(track);

    expect(harness.controller.lyrics, isNotNull);
    expect(harness.controller.lyrics!.mode, LyricSyncMode.word);
  });

  test('沉浸模式切换不影响播放状态', () async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);

    await harness.controller.searchFor('夜空');
    final track = harness.controller.search.results.firstWhere(
      (item) => item.sources.length == 2,
    );
    await harness.controller.selectTrack(track);
    final statusBefore = harness.controller.playback.status;
    final positionBefore = harness.controller.playback.position;

    harness.controller.toggleImmersive();
    expect(harness.controller.viewMode, ViewMode.immersive);
    expect(harness.controller.playback.status, statusBefore);
    expect(harness.controller.playback.position, positionBefore);

    harness.controller.toggleImmersive();
    expect(harness.controller.viewMode, ViewMode.split);
  });

  test('手动时钟推进会更新播放位置', () async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);

    await harness.controller.searchFor('夜空');
    final track = harness.controller.search.results.firstWhere(
      (item) => item.sources.length == 2,
    );
    await harness.controller.selectTrack(track);

    harness.clock.emit(const Duration(seconds: 8));
    await Future<void>.delayed(Duration.zero);

    expect(harness.controller.playback.position, const Duration(seconds: 8));
  });

  test('断开连接后状态回到未连接', () async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);

    await harness.controller.disconnect(MusicService.spotify);

    expect(
      harness.controller.providerStates[MusicService.spotify]!.state,
      ProviderState.disconnected,
    );
  });

  test('暂停后时钟推进不再改变位置', () async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);

    await harness.controller.searchFor('夜空');
    final track = harness.controller.search.results.firstWhere(
      (item) => item.sources.length == 2,
    );
    await harness.controller.selectTrack(track);

    await harness.controller.togglePlayPause();
    expect(harness.controller.playback.status, PlaybackStatus.paused);

    harness.clock.emit(const Duration(seconds: 30));
    await Future<void>.delayed(Duration.zero);

    expect(harness.controller.playback.position, Duration.zero);
  });

  test('播放到结尾会自动进入下一条队列曲目', () async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);

    await harness.controller.searchFor('夜空');
    final first = harness.controller.search.results.firstWhere(
      (track) => !track.versionMarkers.contains('live'),
    );
    await harness.controller.searchFor('晴天');
    final second = harness.controller.search.results.first;

    await harness.controller.selectTrack(first);
    harness.controller.enqueue(second);
    harness.clock.emit(first.duration);
    await Future<void>.delayed(const Duration(milliseconds: 250));

    expect(harness.controller.playback.current?.id, second.id);
    expect(harness.controller.playback.status, PlaybackStatus.playing);
  });

  test('官方网易云结果会与 Spotify 真实搜索结果合并', () async {
    final credentials = InMemoryCredentials();
    await credentials.write(MusicService.spotify.storageKey, 'spotify-token');
    final spotify = SpotifyProvider(
      clientId: 'client-id',
      credentials: credentials,
      fetcher: (uri, {headers, body, contentType}) async {
        expect(headers?['Authorization'], 'Bearer spotify-token');
        return HttpResponse(
          200,
          jsonEncode({
            'tracks': {
              'items': [
                {
                  'id': 'spotify-1',
                  'name': '晴天',
                  'duration_ms': 269000,
                  'artists': [
                    {'name': '周杰伦'},
                  ],
                  'album': {'name': '叶惠美'},
                },
              ],
            },
          }),
        );
      },
    );
    final engine = WebPlaybackEngine(bridge: _WebSearchBridge());
    final controller = MusicController(
      providers: [spotify],
      clock: ManualClock(),
      credentials: credentials,
      handoff: FakeHandoff(),
      webEngine: engine,
    );
    addTearDown(controller.dispose);
    addTearDown(engine.dispose);

    await controller.searchFor('晴天');

    expect(controller.usedOfficialSearch, isTrue);
    final merged = controller.search.results.firstWhere(
      (track) =>
          track.sourceFor(MusicService.spotify) != null &&
          track.sourceFor(MusicService.netease) != null,
    );
    expect(merged.sources.length, 2);
    expect(controller.search.errors, isEmpty);
  });

  test('官方网页自行播放队列外曲目时会接入队列并同步标题进度', () async {
    final first = Track(
      id: 'ne-first',
      title: '夜空中最亮的星',
      artist: '逃跑计划',
      album: '世界',
      duration: const Duration(minutes: 4, seconds: 12),
      sources: [
        TrackSource(
          service: MusicService.netease,
          providerTrackId: 'ne-first',
          playable: true,
        ),
      ],
    );
    final second = Track(
      id: 'ne-second',
      title: '晴天',
      artist: '周杰伦',
      album: '叶惠美',
      duration: const Duration(minutes: 4, seconds: 29),
      sources: [
        TrackSource(
          service: MusicService.netease,
          providerTrackId: 'ne-second',
          playable: true,
        ),
      ],
    );
    final bridge = _MutableWebBridge({
      'ne-first': first,
      'ne-second': second,
    });
    final engine = WebPlaybackEngine(
      bridge: bridge,
      pollInterval: const Duration(milliseconds: 20),
    );
    final controller = MusicController(
      providers: const [],
      clock: ManualClock(),
      credentials: InMemoryCredentials(),
      handoff: FakeHandoff(),
      webEngine: engine,
    );
    addTearDown(controller.dispose);
    addTearDown(engine.dispose);

    await controller.selectTrack(first);
    bridge.current = WebPlayerState(
      hasMedia: true,
      paused: false,
      position: const Duration(seconds: 7),
      duration: second.duration,
      // 官方播放栏偶尔仍显示旧标题；歌曲 ID 已经是新曲目。
      nowPlaying: first.title,
      nowPlayingId: 'ne-second',
      mediaSessionTitle: second.title,
      mediaSessionArtist: second.artist,
    );
    await engine.toggle();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      controller.playback.current
          ?.sourceFor(MusicService.netease)
          ?.providerTrackId,
      'ne-second',
    );
    expect(controller.playback.queueIndex, 1);
    expect(controller.playback.queue.length, 2);
    expect(controller.playback.position, const Duration(seconds: 7));
  });

  test('读取官方播放列表后可从客户端队列直接点击切歌', () async {
    final first = Track(
      id: 'ne-first',
      title: '夜空中最亮的星',
      artist: '逃跑计划',
      album: '世界',
      duration: const Duration(minutes: 4, seconds: 12),
      sources: [
        TrackSource(
          service: MusicService.netease,
          providerTrackId: 'ne-first',
          playable: true,
        ),
      ],
    );
    final second = Track(
      id: 'ne-second',
      title: '晴天',
      artist: '周杰伦',
      album: '叶惠美',
      duration: const Duration(minutes: 4, seconds: 29),
      sources: [
        TrackSource(
          service: MusicService.netease,
          providerTrackId: 'ne-second',
          playable: true,
        ),
      ],
    );
    final bridge = _OfficialQueueWebBridge({
      'ne-first': first,
      'ne-second': second,
    });
    final engine = WebPlaybackEngine(
      bridge: bridge,
      pollInterval: const Duration(milliseconds: 20),
    );
    final controller = MusicController(
      providers: const [],
      clock: ManualClock(),
      credentials: InMemoryCredentials(),
      handoff: FakeHandoff(),
      webEngine: engine,
    );
    addTearDown(controller.dispose);
    addTearDown(engine.dispose);

    await controller.selectTrack(first);
    await controller.refreshQueue();

    expect(controller.usesOfficialQueue, isTrue);
    expect(controller.playback.queue.length, 2);
    expect(controller.playback.queue.first.title, '夜空中最亮的星');
    expect(controller.playback.queue.last.title, '晴天');

    await controller.playAt(1);

    expect(
      controller.playback.current
          ?.sourceFor(MusicService.netease)
          ?.providerTrackId,
      'ne-second',
    );
    expect(controller.playback.queueIndex, 1);
    expect(controller.playback.status, PlaybackStatus.playing);
  });
}
