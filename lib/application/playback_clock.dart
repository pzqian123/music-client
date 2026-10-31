/// 播放时钟抽象：首版用假时钟驱动歌词，不接真实音频。
library;

import 'dart:async';

abstract class PlaybackClock {
  Stream<Duration> get positions;
  void start();
  void pause();
  void seek(Duration position);
  Future<void> dispose();
}

/// 测试与演示用的手动时钟：只有显式 emit 才推进。
class ManualClock implements PlaybackClock {
  final _controller = StreamController<Duration>.broadcast();
  Duration _position = Duration.zero;

  Duration get position => _position;

  @override
  Stream<Duration> get positions => _controller.stream;

  @override
  void start() {}

  @override
  void pause() {}

  @override
  void seek(Duration position) {
    _position = position < Duration.zero ? Duration.zero : position;
    if (!_controller.isClosed) _controller.add(_position);
  }

  /// 测试里推进到指定位置。
  void emit(Duration position) => seek(position);

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}

/// 运行期时钟：每 [tick] 推进一次。
class TimerClock implements PlaybackClock {
  TimerClock({this.tick = const Duration(milliseconds: 100)});

  final Duration tick;
  final _controller = StreamController<Duration>.broadcast();
  Timer? _timer;
  Duration _position = Duration.zero;

  Duration get position => _position;

  @override
  Stream<Duration> get positions => _controller.stream;

  @override
  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(tick, (_) {
      _position += tick;
      if (!_controller.isClosed) _controller.add(_position);
    });
  }

  @override
  void pause() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void seek(Duration position) {
    _position = position < Duration.zero ? Duration.zero : position;
    if (!_controller.isClosed) _controller.add(_position);
  }

  @override
  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    await _controller.close();
  }
}
