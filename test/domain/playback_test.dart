import 'package:flutter_test/flutter_test.dart';
import 'package:music_client/domain/models.dart';
import 'package:music_client/domain/playback.dart';

Track _track(
  String id, {
  bool playable = true,
  MusicService service = MusicService.netease,
  Duration duration = const Duration(minutes: 3),
}) {
  return Track(
    id: id,
    title: id,
    artist: 'artist',
    album: 'album',
    duration: duration,
    sources: [
      TrackSource(service: service, providerTrackId: id, playable: playable),
    ],
  );
}

void main() {
  const machine = PlaybackMachine();

  test('空队列下所有操作安全', () {
    const idle = PlaybackState.idle();
    expect(machine.pause(idle).status, PlaybackStatus.idle);
    expect(machine.resume(idle).status, PlaybackStatus.idle);
    expect(machine.next(idle).queueIndex, -1);
    expect(machine.previous(idle).queueIndex, -1);
    expect(machine.playAt(idle, 3).status, PlaybackStatus.idle);
    expect(machine.tick(idle, const Duration(seconds: 1)).position, Duration.zero);
    expect(idle.current, isNull);
  });

  test('入队保留顺序', () {
    var state = PlaybackState.idle();
    state = machine.enqueue(state, _track('a'));
    state = machine.enqueue(state, _track('b'));
    expect(state.queue.map((t) => t.id).toList(), ['a', 'b']);
    expect(state.queueIndex, 0);
  });

  test('playAt 越界时夹紧', () {
    var state = PlaybackState.idle();
    state = machine.enqueue(state, _track('a'));
    state = machine.enqueue(state, _track('b'));

    expect(machine.playAt(state, 99).queueIndex, 1);
    expect(machine.playAt(state, -5).queueIndex, 0);
  });

  test('playAt 使用 preferredSource 作为活动来源', () {
    var state = PlaybackState.idle();
    state = machine.enqueue(
      state,
      Track(
        id: 'x',
        title: 'x',
        artist: 'y',
        album: 'z',
        duration: const Duration(minutes: 3),
        sources: const [
          TrackSource(
            service: MusicService.spotify,
            providerTrackId: 'sp',
            playable: false,
          ),
          TrackSource(
            service: MusicService.netease,
            providerTrackId: 'ne',
            playable: true,
          ),
        ],
      ),
    );
    state = machine.playAt(state, 0);
    expect(state.activeService, MusicService.netease);
  });

  test('next 在末尾保持不动', () {
    var state = PlaybackState.idle();
    state = machine.enqueue(state, _track('a'));
    state = machine.enqueue(state, _track('b'));
    state = machine.playAt(state, 1);
    final result = machine.next(state);
    expect(result.queueIndex, 1);
  });

  test('previous 在超过 3 秒时回到本曲开头', () {
    var state = PlaybackState.idle();
    state = machine.enqueue(state, _track('a'));
    state = machine.enqueue(state, _track('b'));
    state = machine.playAt(state, 1);
    state = state.copyWith(position: const Duration(seconds: 10));

    final result = machine.previous(state);
    expect(result.queueIndex, 1);
    expect(result.position, Duration.zero);
  });

  test('previous 在开头附近回到上一首', () {
    var state = PlaybackState.idle();
    state = machine.enqueue(state, _track('a'));
    state = machine.enqueue(state, _track('b'));
    state = machine.playAt(state, 1);
    state = state.copyWith(position: const Duration(seconds: 1));

    expect(machine.previous(state).queueIndex, 0);
  });

  test('暂停不推进位置，继续后恢复播放态', () {
    var state = PlaybackState.idle();
    state = machine.enqueue(state, _track('a'));
    state = machine.playAt(state, 0).copyWith(status: PlaybackStatus.playing);

    final paused = machine.pause(state);
    expect(paused.status, PlaybackStatus.paused);
    expect(machine.tick(paused, const Duration(seconds: 5)).position, Duration.zero);
    expect(machine.resume(paused).status, PlaybackStatus.playing);
  });

  test('tick 不超过曲目时长', () {
    var state = PlaybackState.idle();
    state = machine.enqueue(
      state,
      _track('a', duration: const Duration(seconds: 10)),
    );
    state = machine.playAt(state, 0).copyWith(status: PlaybackStatus.playing);

    final result = machine.tick(state, const Duration(seconds: 30));
    expect(result.position, const Duration(seconds: 10));
  });

  test('block 记录原因与提示且不改变位置', () {
    var state = PlaybackState.idle();
    state = machine.enqueue(state, _track('a'));
    state = machine.playAt(state, 0).copyWith(position: const Duration(seconds: 7));

    final blocked = machine.block(
      state,
      BlockReason.requiresSubscription,
      '该账号无客户端内播放权限',
    );
    expect(blocked.status, PlaybackStatus.blocked);
    expect(blocked.blockReason, BlockReason.requiresSubscription);
    expect(blocked.message, isNotNull);
    expect(blocked.position, const Duration(seconds: 7));
  });

  test('switchSource 保留队列与曲目，仅改活动来源', () {
    var state = PlaybackState.idle();
    final track = Track(
      id: 'x',
      title: 'x',
      artist: 'y',
      album: 'z',
      duration: const Duration(minutes: 3),
      sources: const [
        TrackSource(
          service: MusicService.spotify,
          providerTrackId: 'sp',
          playable: true,
        ),
        TrackSource(
          service: MusicService.netease,
          providerTrackId: 'ne',
          playable: true,
        ),
      ],
    );
    state = machine.enqueue(state, track);
    state = machine.playAt(state, 0);

    final switched = machine.switchSource(state, MusicService.spotify);
    expect(switched.activeService, MusicService.spotify);
    expect(switched.queueIndex, 0);
    expect(switched.current?.id, 'x');

    final unsupported = machine.switchSource(state, MusicService.netease);
    expect(unsupported.activeService, MusicService.netease);
  });

  test('switchSource 对不存在的来源保持不变', () {
    var state = PlaybackState.idle();
    state = machine.enqueue(state, _track('a', service: MusicService.netease));
    state = machine.playAt(state, 0);
    final result = machine.switchSource(state, MusicService.spotify);
    expect(result.activeService, MusicService.netease);
  });
}
