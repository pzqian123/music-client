/// 网页播放引擎：把「隐藏的官方页面」封装成一个可测试的播放后端。
///
/// 与 UI 无关，通过 [WebPlayerBridge] 与真实 WebView 通信，测试可注入假实现。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/models.dart';
import '../presentation/widgets/hidden_web_player.dart';
import 'web_player_engine.dart';

/// WebView 桥的最小接口，便于测试替换。
abstract interface class WebPlayerBridge {
  bool get isAttached;
  Future<WebPlayerState> readState();
  Future<void> toggle();
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> openTrack(WebPlayerTarget target, String providerTrackId);
  Future<String> clickOfficialPlay();
  Future<String> runScript(String source);
  Future<List<OfficialSearchResult>> searchNetease(
    String query, {
    Duration wait,
  });
}

/// 把 [WebPlayerHandle] 适配成 [WebPlayerBridge]。
class HandleWebPlayerBridge implements WebPlayerBridge {
  HandleWebPlayerBridge(this.handle);

  final WebPlayerHandle handle;

  @override
  bool get isAttached => handle.isAttached;

  @override
  Future<WebPlayerState> readState() => handle.readState();

  @override
  Future<void> toggle() => handle.toggle();

  @override
  Future<void> play() => handle.play();

  @override
  Future<void> pause() => handle.pause();

  @override
  Future<void> seek(Duration position) => handle.seek(position);

  @override
  Future<void> openTrack(WebPlayerTarget target, String providerTrackId) =>
      handle.openTrack(target, providerTrackId);

  @override
  Future<String> clickOfficialPlay() => handle.clickOfficialPlay();

  @override
  Future<String> runScript(String source) => handle.runScript(source);

  @override
  Future<List<OfficialSearchResult>> searchNetease(
    String query, {
    Duration wait = const Duration(milliseconds: 2600),
  }) =>
      handle.searchNetease(query, wait: wait);
}

/// 把 `mm:ss` 文本转成时长。
Duration parseClockDuration(String text) {
  final match = RegExp(r'(\d{1,3}):(\d{2})').firstMatch(text);
  if (match == null) return Duration.zero;
  final minutes = int.tryParse(match.group(1)!) ?? 0;
  final seconds = int.tryParse(match.group(2)!) ?? 0;
  return Duration(minutes: minutes, seconds: seconds);
}

/// 把官方搜索结果转换为领域 [Track]。
Track trackFromOfficialResult(OfficialSearchResult result) {
  final duration = parseClockDuration(result.duration);
  return Track(
    id: 'netease-web-${result.id}',
    title: result.title,
    artist: result.artist,
    album: '',
    duration: duration,
    sources: [
      TrackSource(
        service: MusicService.netease,
        providerTrackId: result.id,
        playable: true,
        officialHandoffUri:
            Uri.tryParse('https://music.163.com/song?id=${result.id}'),
      ),
    ],
  );
}

class WebPlaybackEngine extends ChangeNotifier {
  WebPlaybackEngine({
    required this.bridge,
    this.pollInterval = const Duration(milliseconds: 700),
    this.service = MusicService.netease,
  });

  final WebPlayerBridge bridge;
  final Duration pollInterval;
  final MusicService service;

  WebPlayerState _state = const WebPlayerState.empty();
  Timer? _timer;
  String? _lastError;

  bool get isBusy => _busy;

  bool _busy = false;

  WebPlayerState get state => _state;

  String? get lastError => _lastError;

  bool get isAttached => bridge.isAttached;

  WebPlayerTarget get target => webTargetFor(service) ?? neteaseWebTarget;

  void start() {
    _timer ??= Timer.periodic(pollInterval, (_) => unawaited(_poll()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _poll() async {
    if (!bridge.isAttached) return;
    try {
      final next = await bridge.readState();
      if (_sameState(next, _state)) return;
      _state = next;
      notifyListeners();
    } catch (_) {
      // 轮询失败不打断播放，下个周期再试。
    }
  }

  static bool _sameState(WebPlayerState a, WebPlayerState b) {
    if (a.hasMedia != b.hasMedia || a.paused != b.paused) return false;
    if (a.nowPlaying != b.nowPlaying) return false;
    return (a.position.inMilliseconds - b.position.inMilliseconds).abs() < 400;
  }

  Future<List<Track>> searchNetease(String query) async {
    if (query.trim().isEmpty) return const [];
    final results = await bridge.searchNetease(query);
    return results.map(trackFromOfficialResult).toList();
  }

  /// 打开曲目页并点击官方播放按钮，返回是否成功起播。
  Future<bool> playTrack(Track track) async {
    final source = track.sourceFor(service);
    if (source == null) return false;
    _busy = true;
    _lastError = null;
    notifyListeners();
    try {
      await bridge.openTrack(target, source.providerTrackId);
      await Future<void>.delayed(const Duration(milliseconds: 2600));
      final clicked = await bridge.clickOfficialPlay();
      if (clicked.startsWith('no-play-button') || clicked.startsWith('click-error')) {
        _lastError = '官方页面未找到播放按钮';
        return false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      await _poll();
      return _state.hasMedia;
    } catch (error) {
      _lastError = '$error';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> toggle() async {
    await bridge.toggle();
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await _poll();
  }

  Future<void> pausePlayback() async {
    await bridge.pause();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await _poll();
  }

  Future<void> resumePlayback() async {
    await bridge.play();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await _poll();
  }

  Future<void> seek(Duration position) async {
    final clamped = position < Duration.zero ? Duration.zero : position;
    await bridge.seek(clamped);
    _state = WebPlayerState(
      hasMedia: _state.hasMedia,
      paused: _state.paused,
      ended: _state.ended,
      position: clamped,
      duration: _state.duration,
      volume: _state.volume,
      pageTitle: _state.pageTitle,
      nowPlaying: _state.nowPlaying,
      source: _state.source,
    );
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await _poll();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
