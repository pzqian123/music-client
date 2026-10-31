/// 应用唯一状态源：搜索、队列、播放、歌词、视图模式都从这里读。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/dedupe.dart';
import '../domain/lyrics.dart';
import '../domain/models.dart';
import '../domain/playback.dart';
import '../platform/official_handoff.dart';
import '../platform/secure_credentials.dart';
import '../platform/web_playback_engine.dart';
import '../providers/music_provider.dart';
import 'playback_clock.dart';

enum ViewMode { split, immersive }

class ProviderError {
  final MusicService service;
  final String message;
  final bool retryable;

  const ProviderError({
    required this.service,
    required this.message,
    this.retryable = true,
  });
}

class SearchState {
  final String query;
  final bool loading;
  final List<Track> results;
  final Map<MusicService, ProviderError> errors;
  final Duration? elapsed;

  const SearchState({
    this.query = '',
    this.loading = false,
    this.results = const [],
    this.errors = const {},
    this.elapsed,
  });

  bool get isEmptyResult => !loading && results.isEmpty;

  SearchState copyWith({
    String? query,
    bool? loading,
    List<Track>? results,
    Map<MusicService, ProviderError>? errors,
    Duration? elapsed,
  }) {
    return SearchState(
      query: query ?? this.query,
      loading: loading ?? this.loading,
      results: results ?? this.results,
      errors: errors ?? this.errors,
      elapsed: elapsed ?? this.elapsed,
    );
  }
}

class MusicController extends ChangeNotifier {
  MusicController({
    required List<MusicProvider> providers,
    PlaybackClock? clock,
    SecureCredentials? credentials,
    OfficialHandoff? handoff,
    this.webEngine,
  })  : providers = List.unmodifiable(providers),
        _clock = clock ?? TimerClock(),
        _credentials = credentials ?? InMemoryCredentials(),
        _handoff = handoff ?? const UrlLauncherHandoff() {
    _providerStates = {
      for (final provider in this.providers) provider.service: provider.snapshot,
    };
    _clockSubscription = _clock.positions.listen(_onClockTick);
    webEngine?.addListener(_onWebEngineChanged);
  }

  final List<MusicProvider> providers;
  final PlaybackClock _clock;
  final SecureCredentials _credentials;
  final OfficialHandoff _handoff;

  /// 网页播放引擎；为空或未就绪时退回演示播放。
  final WebPlaybackEngine? webEngine;

  final PlaybackMachine _machine = const PlaybackMachine();

  /// 官方页面抓到的封面字节（按 providerTrackId 索引）。
  /// 注意：这里缓存的是 `Uint8List` 实例本身——每次重建都新建实例会让
  /// MemoryImage 判定为新图、反复解码，封面就会闪烁。
  final Map<String, Uint8List> _coverBytes = {};

  Uint8List? coverBytesFor(Track track) {
    final source = track.sourceFor(MusicService.netease);
    if (source == null) return null;
    return _coverBytes[source.providerTrackId];
  }

  /// 当前播放是否由隐藏的官方网页驱动。
  bool _webMode = false;

  bool get usesWebPlayer => _webMode && (webEngine?.isAttached ?? false);

  StreamSubscription<Duration>? _clockSubscription;

  SearchState _search = const SearchState();
  PlaybackState _playback = const PlaybackState.idle();
  LyricTimeline? _lyrics;
  ViewMode _viewMode = ViewMode.split;
  Map<MusicService, ProviderSnapshot> _providerStates = const {};
  int _searchSeq = 0;

  SearchState get search => _search;

  PlaybackState get playback => _playback;

  LyricTimeline? get lyrics => _lyrics;

  ViewMode get viewMode => _viewMode;

  Map<MusicService, ProviderSnapshot> get providerStates => _providerStates;

  bool get isDemo => providers.isNotEmpty && providers.first.isDemo;

  /// 最近一次搜索是否来自官方页面（真实数据）。
  bool get usedOfficialSearch => _usedOfficialSearch;

  bool _usedOfficialSearch = false;

  ProviderSnapshot? snapshotOf(MusicService service) => _providerStates[service];

  MusicProvider? _providerFor(MusicService? service) {
    if (service == null) return null;
    for (final provider in providers) {
      if (provider.service == service) return provider;
    }
    return null;
  }

  void _refreshProviderStates() {
    _providerStates = {
      for (final provider in providers) provider.service: provider.snapshot,
    };
  }

  Future<void> searchFor(String query) async {
    final trimmed = query.trim();
    final seq = ++_searchSeq;
    if (trimmed.isEmpty) {
      _search = const SearchState();
      notifyListeners();
      return;
    }

    _search = _search.copyWith(query: trimmed, loading: true, errors: const {});
    notifyListeners();

    final stopwatch = Stopwatch()..start();

    // 网页播放引擎可用时，搜索直接解析官方结果（真实数据）。
    final engine = webEngine;
    if (engine != null && engine.isAttached) {
      try {
        final tracks = await engine.searchNetease(trimmed);
        if (seq != _searchSeq) return;
        stopwatch.stop();
        _usedOfficialSearch = true;

        // 批量补封面（一次请求覆盖列表）。
        final ids = tracks
            .map((track) => track.sourceFor(MusicService.netease)?.providerTrackId)
            .whereType<String>()
            .toList();
        final covers = await engine.fetchCovers(ids);
        if (seq != _searchSeq) return;
        final withCovers = [
          for (final track in tracks)
            covers[track.sourceFor(MusicService.netease)?.providerTrackId] == null
                ? track
                : track.copyWith(
                    artworkUrl:
                        covers[track.sourceFor(MusicService.netease)!.providerTrackId],
                  ),
        ];

        // 由官方页面抓取前若干首的封面字节，规避图床的 UA 拦截。
        final byteRequests = <Map<String, String>>[
          for (final track in withCovers.take(10))
            if (track.artworkUrl != null)
              {
                'id': track.sourceFor(MusicService.netease)?.providerTrackId ?? '',
                'url': track.artworkUrl ?? '',
              },
        ]..removeWhere((item) => item['id']!.isEmpty);
        if (byteRequests.isNotEmpty) {
          final bytes = await engine.fetchCoverBytes(byteRequests);
          if (seq != _searchSeq) return;
          for (final entry in bytes.entries) {
            _coverBytes[entry.key] = Uint8List.fromList(entry.value);
          }
        }

        _search = SearchState(
          query: trimmed,
          loading: false,
          results: withCovers,
          errors: const {},
          elapsed: stopwatch.elapsed,
        );
        notifyListeners();
        return;
      } catch (error) {
        if (seq != _searchSeq) return;
        _search = SearchState(
          query: trimmed,
          loading: false,
          results: const [],
          errors: {
            MusicService.netease: ProviderError(
              service: MusicService.netease,
              message: '官方页面搜索失败：$error',
            ),
          },
          elapsed: stopwatch.elapsed,
        );
        notifyListeners();
        return;
      }
    }

    final futures = providers.map((provider) async {
      try {
        final tracks = await provider.search(trimmed);
        return MapEntry<MusicService, Object>(provider.service, tracks);
      } catch (error) {
        return MapEntry<MusicService, Object>(provider.service, error);
      }
    }).toList();

    final responses = await Future.wait(futures);
    if (seq != _searchSeq) return; // 竞态保护：丢弃过期结果

    final collected = <ProviderTrack>[];
    final errors = <MusicService, ProviderError>{};
    for (final response in responses) {
      final value = response.value;
      if (value is List<ProviderTrack>) {
        collected.addAll(value);
      } else if (value is ProviderException) {
        errors[response.key] = ProviderError(
          service: response.key,
          message: value.message,
        );
      } else {
        errors[response.key] = ProviderError(
          service: response.key,
          message: '加载失败，请重试',
        );
      }
    }
    stopwatch.stop();

    final merged = mergeProviderTracks(collected);
    _search = SearchState(
      query: trimmed,
      loading: false,
      results: merged.tracks,
      errors: errors,
      elapsed: stopwatch.elapsed,
    );
    _refreshProviderStates();
    notifyListeners();
  }

  /// 曲目是否有可用的网易云来源且隐藏播放器就绪。
  bool _canPlayThroughWeb(Track track, MusicService? service) {
    if (!(webEngine?.isAttached ?? false)) return false;
    if (track.sourceFor(MusicService.netease) == null) return false;
    return service == null || service == MusicService.netease;
  }

  /// 播放入口：统一决定走隐藏的官方页面还是演示播放。
  Future<void> _playTrack(Track track, {MusicService? service}) async {
    if (_canPlayThroughWeb(track, service)) {
      await _playViaWeb(track);
      return;
    }
    await _startPlayback(
      track,
      service ?? track.preferredSource?.service,
      resetPosition: true,
    );
  }

  Future<void> selectTrack(Track track, {MusicService? service}) async {
    // 队列去重：同一首已在队列里就跳过去，不再追加一条。
    final existing =
        _playback.queue.indexWhere((item) => item.id == track.id);
    if (existing >= 0) {
      _playback = _machine.playAt(_playback, existing);
      notifyListeners();
      await _playTrack(_playback.current ?? track, service: service);
      return;
    }

    _playback = _machine.enqueue(_playback, track);
    final index = _playback.queue.length - 1;
    _playback = _machine.playAt(_playback, index);
    notifyListeners();
    await _playTrack(track, service: service);
  }

  Future<void> _playViaWeb(Track track) async {
    final engine = webEngine;
    if (engine == null) return;
    _webMode = true;
    // 切歌先清空上一条的进度与状态，避免失败后残留旧曲目的时间和歌词。
    _lyrics = null;
    _playback = PlaybackState(
      queue: _playback.queue,
      queueIndex: _playback.queueIndex,
      position: Duration.zero,
      status: PlaybackStatus.loading,
      activeService: MusicService.netease,
    );
    notifyListeners();

    final ok = await engine.playTrack(track);
    if (!ok) {
      _webMode = false;
      _playback = _machine.block(
        _playback,
        BlockReason.notSupported,
        engine.lastError ?? '官方页面未能开始播放，请先在「连接」页登录',
      );
      notifyListeners();
      return;
    }
    _playback = PlaybackState(
      queue: _playback.queue,
      queueIndex: _playback.queueIndex,
      position: engine.state.position,
      status: engine.state.paused
          ? PlaybackStatus.paused
          : PlaybackStatus.playing,
      activeService: MusicService.netease,
    );
    notifyListeners();

    // 真实曲目歌词：从官方页面取 LRC（带时间戳），驱动逐行同步。
    final source = track.sourceFor(MusicService.netease);
    if (source != null) {
      _lyrics = await engine.fetchLyrics(source.providerTrackId);
      notifyListeners();

      // 队列里的封面：播放到哪首就补哪首的字节（搜索结果只预抓了前 10 条）。
      if (!_coverBytes.containsKey(source.providerTrackId) &&
          (track.artworkUrl ?? '').isNotEmpty) {
        final bytes = await engine.fetchCoverBytes([
          {'id': source.providerTrackId, 'url': track.artworkUrl!},
        ]);
        final data = bytes[source.providerTrackId];
        if (data != null && data.isNotEmpty) {
          _coverBytes[source.providerTrackId] = Uint8List.fromList(data);
          notifyListeners();
        }
      }
    }
  }

  void _onWebEngineChanged() {
    if (!_webMode) return;
    final state = webEngine?.state;
    if (state == null || !state.hasMedia) return;
    final nextStatus = _playback.status == PlaybackStatus.loading
        ? (state.paused ? PlaybackStatus.paused : PlaybackStatus.playing)
        : (state.paused ? PlaybackStatus.paused : PlaybackStatus.playing);
    _playback = _playback.copyWith(
      position: state.position,
      status: nextStatus,
    );
    notifyListeners();
  }

  /// 拖动进度（网页播放模式下真实生效）。
  Future<void> seekTo(Duration position) async {
    final engine = webEngine;
    if (_webMode && engine != null) {
      _playback = _playback.copyWith(position: position);
      notifyListeners();
      await engine.seek(position);
      return;
    }
    _clock.seek(position);
    _playback = _playback.copyWith(position: position);
    notifyListeners();
  }

  /// 仅加入队列，不改变当前播放；已在队列中则忽略。
  void enqueue(Track track) {
    if (_playback.queue.any((item) => item.id == track.id)) {
      notifyListeners();
      return;
    }
    _playback = _machine.enqueue(_playback, track);
    notifyListeners();
  }

  /// 播放队列中指定位置（队列面板使用）。
  Future<void> playAt(int index) async {
    if (index < 0 || index >= _playback.queue.length) return;
    final track = _playback.queue[index];
    _playback = _machine.playAt(_playback, index);
    notifyListeners();
    await _playTrack(track);
  }

  Future<void> switchSource(MusicService service) async {
    final track = _playback.current;
    if (track == null) return;
    if (track.sourceFor(service) == null) return;
    final position = _playback.position;
    _playback = _machine.switchSource(_playback, service);
    notifyListeners();
    await _startPlayback(track, service, resetPosition: false, keepPosition: position);
  }

  Future<void> _startPlayback(
    Track track,
    MusicService? service, {
    required bool resetPosition,
    Duration? keepPosition,
  }) async {
    final provider = _providerFor(service);
    final source = service == null ? null : track.sourceFor(service);
    if (provider == null || source == null) {
      _playback = _machine.block(
        _playback,
        BlockReason.notSupported,
        '没有可用的播放来源',
      );
      _lyrics = null;
      notifyListeners();
      return;
    }

    // 用户显式选择的来源即使不可播放，也应成为当前活动来源，
    // 这样错误提示与「打开官方 App」才会指向正确的服务。
    _playback = _playback.copyWith(activeService: service);

    try {
      final result = await provider.startPlayback(source.providerTrackId);
      if (!result.isStarted) {
        _playback = _machine.block(
          _playback,
          _reasonFor(result.outcome),
          result.message ?? '无法在客户端内播放',
        );
        await _loadLyrics(track, service);
        notifyListeners();
        return;
      }

      final start = resetPosition ? Duration.zero : (keepPosition ?? Duration.zero);
      _playback = PlaybackState(
        queue: _playback.queue,
        queueIndex: _playback.queueIndex,
        position: start,
        status: PlaybackStatus.playing,
        activeService: service,
      );
      _clock.seek(start);
      _clock.start();
      await _loadLyrics(track, service);
      notifyListeners();
    } on ProviderException catch (error) {
      _playback = _machine.fail(_playback, error.message);
      notifyListeners();
    }
  }

  BlockReason _reasonFor(PlaybackStartOutcome outcome) {
    switch (outcome) {
      case PlaybackStartOutcome.notAuthorized:
        return BlockReason.notAuthorized;
      case PlaybackStartOutcome.notSupported:
        return BlockReason.notSupported;
      case PlaybackStartOutcome.regionRestricted:
        return BlockReason.regionRestricted;
      case PlaybackStartOutcome.requiresSubscription:
        return BlockReason.requiresSubscription;
      case PlaybackStartOutcome.failed:
        return BlockReason.network;
      case PlaybackStartOutcome.started:
        return BlockReason.unknown;
    }
  }

  Future<void> _loadLyrics(Track track, MusicService? service) async {
    final provider = _providerFor(service);
    final source = service == null ? null : track.sourceFor(service);
    if (provider == null || source == null) {
      _lyrics = null;
      return;
    }
    try {
      _lyrics = await provider.lyricsFor(source.providerTrackId);
    } on ProviderException {
      _lyrics = null;
    }
  }

  Future<void> togglePlayPause() async {
    final current = _playback.current;
    if (current == null) return;

    // 网页播放模式：直接操作隐藏的官方页面。
    if (_webMode && (webEngine?.isAttached ?? false)) {
      await webEngine!.toggle();
      return;
    }

    switch (_playback.status) {
      case PlaybackStatus.playing:
        _playback = _machine.pause(_playback);
        _clock.pause();
        await _providerFor(_playback.activeService)?.pause();
        notifyListeners();
      case PlaybackStatus.paused:
        _playback = _machine.resume(_playback);
        _clock.start();
        await _providerFor(_playback.activeService)?.resume();
        notifyListeners();
      case PlaybackStatus.blocked:
      case PlaybackStatus.error:
        await _startPlayback(
          current,
          _playback.activeService ?? current.preferredSource?.service,
          resetPosition: false,
          keepPosition: _playback.position,
        );
      case PlaybackStatus.idle:
      case PlaybackStatus.loading:
        return;
    }
  }

  Future<void> next() async {
    if (_playback.queue.isEmpty) return;
    if (!_playback.hasNext) return;
    final target = _playback.queue[_playback.queueIndex + 1];
    _playback = _machine.next(_playback);
    notifyListeners();
    await _playTrack(target);
  }

  Future<void> previous() async {
    if (_playback.queue.isEmpty) return;
    final wasPlaying = _playback.status == PlaybackStatus.playing;
    final beforeIndex = _playback.queueIndex;
    _playback = _machine.previous(_playback);
    final track = _playback.current;
    if (track == null) return;

    if (_playback.queueIndex == beforeIndex && _playback.position == Duration.zero && wasPlaying) {
      // 只是回到本曲开头：网页播放模式下要真正 seek 回 0。
      if (_webMode && (webEngine?.isAttached ?? false)) {
        await webEngine!.seek(Duration.zero);
      } else {
        _clock.seek(Duration.zero);
      }
      notifyListeners();
      return;
    }
    notifyListeners();
    await _playTrack(track);
  }

  void toggleImmersive() {
    _viewMode =
        _viewMode == ViewMode.split ? ViewMode.immersive : ViewMode.split;
    notifyListeners();
  }

  /// 外部（如连接页）触发 Provider 动作后刷新快照。
  void refreshProviders() {
    _refreshProviderStates();
    notifyListeners();
  }

  Future<void> disconnect(MusicService service) async {
    await _providerFor(service)?.disconnect();
    await _credentials.delete(service.storageKey);
    _refreshProviderStates();
    notifyListeners();
  }

  Future<bool> openOfficialApp(Uri uri) => _handoff.open(uri);

  /// 当前曲目在指定来源（或当前来源）下的官方跳转地址。
  Uri? officialHandoffOfCurrent() {
    final track = _playback.current;
    if (track == null) return null;
    final source =
        track.sourceFor(_playback.activeService ?? MusicService.spotify) ??
            track.preferredSource;
    return source?.officialHandoffUri;
  }

  void _onClockTick(Duration position) {
    if (_playback.status != PlaybackStatus.playing) return;
    final track = _playback.current;
    if (track == null) return;
    final clamped = position > track.duration ? track.duration : position;
    _playback = _playback.copyWith(position: clamped);
    notifyListeners();
  }

  @override
  void dispose() {
    webEngine?.removeListener(_onWebEngineChanged);
    _clockSubscription?.cancel();
    unawaited(_clock.dispose());
    super.dispose();
  }
}
