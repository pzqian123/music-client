/// 网页播放引擎：把「隐藏的官方页面」封装成一个可测试的播放后端。
///
/// 与 UI 无关，通过 [WebPlayerBridge] 与真实 WebView 通信，测试可注入假实现。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../domain/lyrics.dart';
import '../domain/models.dart';
import '../presentation/widgets/hidden_web_player.dart';
import 'web_player_engine.dart';
import 'web_player_scripts.dart';

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
      await Future<void>.delayed(const Duration(milliseconds: 3200));

      for (var attempt = 0; attempt < 3; attempt++) {
        final clicked = await bridge.clickOfficialPlay();
        if (clicked.startsWith('click-error')) {
          _lastError = '官方页面点击播放失败';
          return false;
        }
        // 等真实元素就绪：拿到的必须是带时长的媒体元素。
        for (var i = 0; i < 6; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          await _poll();
          if (_state.hasMedia &&
              _state.duration.inMilliseconds > 0 &&
              !_state.paused) {
            return true;
          }
        }
      }
      _lastError = _state.hasMedia
          ? '官方页面未开始播放（可能是 VIP 或版权限制）'
          : '官方页面未找到播放器元素';
      return false;
    } catch (error) {
      _lastError = '$error';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 通过官方页面抓取封面字节（绕过图床的 UA 拦截）。
  Future<Map<String, List<int>>> fetchCoverBytes(
    List<Map<String, String>> items,
  ) async {
    if (items.isEmpty) return const {};
    try {
      await bridge.runScript(neteaseCoverBytesScript(items));
      for (var attempt = 0; attempt < 24; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        final raw = await bridge.runScript(neteaseCoverBytesReadScript);
        final decoded = _decode(raw);
        if (decoded == null) continue;
        final status = decoded['status'];
        if (status == 'pending') continue;
        if (status != 'ok') return const {};
        final list = decoded['items'];
        if (list is! List) return const {};
        final result = <String, List<int>>{};
        for (final item in list) {
          if (item is! Map<String, dynamic>) continue;
          final id = item['id'];
          final data = item['data'];
          if (id is! String || data is! String) continue;
          final comma = data.indexOf(',');
          if (comma <= 0) continue;
          try {
            result[id] = base64Decode(data.substring(comma + 1));
          } catch (_) {
            // 单张失败不影响其余封面。
          }
        }
        return result;
      }
      return const {};
    } catch (_) {
      return const {};
    }
  }

  /// 取单曲封面（官方详情接口对批量 ids 支持不稳定，改为逐曲查询）。
  Future<String?> fetchCover(String songId) async {
    final covers = await _fetchCoversOnce([songId]);
    return covers[songId];
  }

  /// 批量取封面地址（官方详情接口），返回 providerTrackId → 图片地址。
  Future<Map<String, String>> fetchCovers(List<String> songIds) async {
    if (songIds.isEmpty) return const {};
    // 批量接口在部分情况下只返回一条，按每批 1 个查询保证准确性。
    final result = <String, String>{};
    for (final id in songIds.take(12)) {
      final one = await _fetchCoversOnce([id]);
      result.addAll(one);
    }
    return result;
  }

  Future<Map<String, String>> _fetchCoversOnce(List<String> songIds) async {
    if (songIds.isEmpty) return const {};
    try {
      await bridge.runScript(neteaseCoverFetchScript(songIds));
      for (var attempt = 0; attempt < 10; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 220));
        final raw = await bridge.runScript(neteaseCoverReadScript);
        final decoded = _decode(raw);
        if (decoded == null) continue;
        final status = decoded['status'];
        if (status == 'pending') continue;
        if (status != 'ok') return const {};
        final items = decoded['items'];
        if (items is! List) return const {};
        final covers = <String, String>{};
        for (final item in items) {
          if (item is! Map<String, dynamic>) continue;
          final id = item['id'];
          final pic = item['pic'];
          if (id is String && pic is String && pic.isNotEmpty) {
            // 不要加 ?param= 后缀：本机网络下带参数的请求会失败。
            covers[id] = pic;
          }
        }
        return covers;
      }
      return const {};
    } catch (_) {
      return const {};
    }
  }

  /// 取歌词：在官方页面上下文里请求其自身的歌词接口，得到带时间戳的 LRC。
  Future<LyricTimeline?> fetchLyrics(String songId) async {
    if (songId.isEmpty) return null;
    try {
      await bridge.runScript(neteaseLyricFetchScript(songId));
      for (var attempt = 0; attempt < 12; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        final raw = await bridge.runScript(neteaseLyricReadScript);
        final decoded = _decode(raw);
        if (decoded == null) continue;
        final status = decoded['status'];
        if (status == 'pending' || status == null) continue;
        if (status != 'ok') return null;
        final lrc = (decoded['lrc'] as String?) ?? '';
        if (lrc.trim().isEmpty) return null;
        final timeline = LyricTimeline.parseLrc(lrc);
        return timeline.isEmpty ? null : timeline;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _decode(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // 忽略不完整 JSON，继续轮询。
    }
    return null;
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
