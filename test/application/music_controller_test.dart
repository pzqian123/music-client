import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_client/application/music_controller.dart';
import 'package:music_client/application/playback_clock.dart';
import 'package:music_client/domain/lyrics.dart';
import 'package:music_client/domain/models.dart';
import 'package:music_client/domain/playback.dart';
import 'package:music_client/platform/official_handoff.dart';
import 'package:music_client/platform/secure_credentials.dart';
import 'package:music_client/providers/fake_netease_provider.dart';
import 'package:music_client/providers/fake_spotify_provider.dart';
import 'package:music_client/providers/music_provider.dart';

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
}
