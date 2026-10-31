/// 播放状态与队列：不可变状态机，不依赖 Flutter。
library;

import 'models.dart';

enum PlaybackStatus { idle, loading, playing, paused, blocked, error }

/// 无法播放的具体原因，界面据此给出不同提示与动作。
enum BlockReason {
  notAuthorized,
  notSupported,
  regionRestricted,
  requiresSubscription,
  network,
  unknown,
}

class PlaybackState {
  final List<Track> queue;
  final int queueIndex;
  final Duration position;
  final PlaybackStatus status;
  final BlockReason? blockReason;
  final MusicService? activeService;
  final String? message;

  PlaybackState({
    List<Track> queue = const [],
    this.queueIndex = -1,
    this.position = Duration.zero,
    this.status = PlaybackStatus.idle,
    this.blockReason,
    this.activeService,
    this.message,
  }) : queue = List.unmodifiable(queue);

  const PlaybackState.idle()
      : queue = const [],
        queueIndex = -1,
        position = Duration.zero,
        status = PlaybackStatus.idle,
        blockReason = null,
        activeService = null,
        message = null;

  Track? get current {
    if (queueIndex < 0 || queueIndex >= queue.length) return null;
    return queue[queueIndex];
  }

  bool get isPlaying => status == PlaybackStatus.playing;

  bool get hasPrevious => queueIndex > 0;

  bool get hasNext => queueIndex >= 0 && queueIndex < queue.length - 1;

  PlaybackState copyWith({
    List<Track>? queue,
    int? queueIndex,
    Duration? position,
    PlaybackStatus? status,
    BlockReason? blockReason,
    bool clearBlock = false,
    MusicService? activeService,
    String? message,
  }) {
    return PlaybackState(
      queue: queue ?? this.queue,
      queueIndex: queueIndex ?? this.queueIndex,
      position: position ?? this.position,
      status: status ?? this.status,
      blockReason: clearBlock ? null : (blockReason ?? this.blockReason),
      activeService: activeService ?? this.activeService,
      message: message ?? this.message,
    );
  }

  @override
  String toString() =>
      'PlaybackState(status: $status, index: $queueIndex, '
      'position: $position, queue: ${queue.length})';
}

/// 纯函数状态机：所有转换返回新实例。
class PlaybackMachine {
  const PlaybackMachine();

  PlaybackState enqueue(PlaybackState state, Track track) {
    final queue = List<Track>.from(state.queue)..add(track);
    final index = state.queueIndex < 0 ? 0 : state.queueIndex;
    return PlaybackState(
      queue: queue,
      queueIndex: index,
      position: state.position,
      status: state.status,
      blockReason: state.blockReason,
      activeService: state.activeService,
      message: state.message,
    );
  }

  PlaybackState playAt(PlaybackState state, int index) {
    if (state.queue.isEmpty) return state;
    final clamped = index.clamp(0, state.queue.length - 1);
    final track = state.queue[clamped];
    return PlaybackState(
      queue: state.queue,
      queueIndex: clamped,
      position: Duration.zero,
      status: PlaybackStatus.loading,
      activeService: track.preferredSource?.service,
    );
  }

  PlaybackState pause(PlaybackState state) {
    if (state.status != PlaybackStatus.playing) return state;
    return state.copyWith(status: PlaybackStatus.paused);
  }

  PlaybackState resume(PlaybackState state) {
    if (state.status != PlaybackStatus.paused) return state;
    if (state.current == null) return state;
    return state.copyWith(status: PlaybackStatus.playing);
  }

  PlaybackState next(PlaybackState state) {
    if (state.queue.isEmpty) return state;
    if (state.queueIndex >= state.queue.length - 1) return state;
    return playAt(state, state.queueIndex + 1);
  }

  PlaybackState previous(PlaybackState state) {
    if (state.queue.isEmpty) return state;
    if (state.position > const Duration(seconds: 3)) {
      return state.copyWith(position: Duration.zero);
    }
    if (state.queueIndex <= 0) {
      return state.copyWith(position: Duration.zero);
    }
    return playAt(state, state.queueIndex - 1);
  }

  PlaybackState switchSource(PlaybackState state, MusicService service) {
    final track = state.current;
    if (track == null) return state;
    if (track.sourceFor(service) == null) return state;
    return PlaybackState(
      queue: state.queue,
      queueIndex: state.queueIndex,
      position: state.position,
      status: PlaybackStatus.loading,
      activeService: service,
    );
  }

  PlaybackState block(
    PlaybackState state,
    BlockReason reason,
    String message,
  ) {
    return PlaybackState(
      queue: state.queue,
      queueIndex: state.queueIndex,
      position: state.position,
      status: PlaybackStatus.blocked,
      blockReason: reason,
      activeService: state.activeService,
      message: message,
    );
  }

  PlaybackState fail(PlaybackState state, String message) {
    return PlaybackState(
      queue: state.queue,
      queueIndex: state.queueIndex,
      position: state.position,
      status: PlaybackStatus.error,
      activeService: state.activeService,
      message: message,
    );
  }

  PlaybackState tick(PlaybackState state, Duration delta) {
    if (state.status != PlaybackStatus.playing) return state;
    final track = state.current;
    if (track == null) return state;
    final next = state.position + delta;
    final clamped = next > track.duration ? track.duration : next;
    return state.copyWith(position: clamped < Duration.zero ? Duration.zero : clamped);
  }
}
