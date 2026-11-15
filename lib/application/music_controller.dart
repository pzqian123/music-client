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
import '../platform/web_player_engine.dart';
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

class _ProviderSearchBatch {
  const _ProviderSearchBatch({
    required this.service,
    this.tracks = const [],
    this.error,
  });

  final MusicService service;
  final List<ProviderTrack> tracks;
  final Object? error;
}

class MusicController extends ChangeNotifier {
  MusicController({
    required List<MusicProvider> providers,
    PlaybackClock? clock,
    SecureCredentials? credentials,
    OfficialHandoff? handoff,
    this.webEngine,
  }) : providers = List.unmodifiable(providers),
       _clock = clock ?? TimerClock(),
       _credentials = credentials ?? InMemoryCredentials(),
       _handoff = handoff ?? const UrlLauncherHandoff() {
    _providerStates = const {};
    _refreshProviderStates();
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
  bool _officialQueueMode = false;
  bool _queueLoading = false;
  int _queueSeq = 0;
  int _webAssetSeq = 0;
  bool _disposed = false;

  bool get usesWebPlayer => _webMode && (webEngine?.isAttached ?? false);
  bool get usesOfficialQueue => _officialQueueMode;
  bool get queueLoading => _queueLoading;

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

  ProviderSnapshot? snapshotOf(MusicService service) =>
      _providerStates[service];

  MusicProvider? _providerFor(MusicService? service) {
    if (service == null) return null;
    for (final provider in providers) {
      if (provider.service == service) return provider;
    }
    return null;
  }

  void _refreshProviderStates() {
    final states = <MusicService, ProviderSnapshot>{
      for (final provider in providers) provider.service: provider.snapshot,
    };
    if (webEngine?.isAttached ?? false) {
      states[MusicService.netease] = const ProviderSnapshot(
        service: MusicService.netease,
        state: ProviderState.connected,
        capabilities: ProviderCapabilities(
          search: true,
          metadata: true,
          lyrics: true,
          inAppPlayback: true,
          officialHandoff: true,
        ),
        message: '由官方网页播放器提供',
      );
    }
    _providerStates = states;
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

    final engine = webEngine;
    final officialEnabled = engine != null && engine.isAttached;
    final futures = <Future<_ProviderSearchBatch>>[];

    if (officialEnabled) {
      futures.add(_searchOfficialNetease(engine, trimmed));
    }

    // 官方网页模式只合并真实 Provider，避免演示目录混入线上搜索结果。
    final activeProviders = officialEnabled
        ? providers.where(
            (provider) =>
                !provider.isDemo && provider.service != MusicService.netease,
          )
        : providers;
    for (final provider in activeProviders) {
      futures.add(_searchProvider(provider, trimmed));
    }

    final responses = await Future.wait(futures);
    if (seq != _searchSeq) return; // 竞态保护：丢弃过期结果

    final collected = <ProviderTrack>[];
    final errors = <MusicService, ProviderError>{};
    for (final response in responses) {
      if (response.error == null) {
        collected.addAll(response.tracks);
        if (officialEnabled && response.service == MusicService.netease) {
          _usedOfficialSearch = true;
        }
      } else {
        final error = response.error!;
        errors[response.service] = ProviderError(
          service: response.service,
          message: error is ProviderException
              ? error.message
              : response.service == MusicService.netease
              ? '官方页面搜索失败：$error'
              : '加载失败，请重试',
        );
      }
    }

    final merged = mergeProviderTracks(collected);
    var tracks = merged.tracks;

    // 合并后再补网易云封面，保证 Spotify + 网易云同曲不会因先取封面而错过合并。
    if (officialEnabled) {
      final ids = [
        for (final track in tracks)
          track.sourceFor(MusicService.netease)?.providerTrackId,
      ].whereType<String>().take(12).toList();
      if (ids.isNotEmpty) {
        final covers = await engine.fetchCovers(ids);
        if (seq != _searchSeq) return;
        tracks = [
          for (final track in tracks)
            if (track.sourceFor(MusicService.netease)?.providerTrackId
                case final id? when covers[id] != null)
              track.copyWith(artworkUrl: covers[id])
            else
              track,
        ];

        final byteRequests = <Map<String, String>>[
          for (final track in tracks)
            if (track.sourceFor(MusicService.netease)?.providerTrackId
                case final id? when (track.artworkUrl ?? '').isNotEmpty)
              {'id': id, 'url': track.artworkUrl!},
        ].take(10).toList();
        if (byteRequests.isNotEmpty) {
          final bytes = await engine.fetchCoverBytes(byteRequests);
          if (seq != _searchSeq) return;
          for (final entry in bytes.entries) {
            _coverBytes[entry.key] = Uint8List.fromList(entry.value);
          }
        }
      }
    }

    stopwatch.stop();
    _search = SearchState(
      query: trimmed,
      loading: false,
      results: tracks,
      errors: errors,
      elapsed: stopwatch.elapsed,
    );
    _refreshProviderStates();
    notifyListeners();
  }

  Future<_ProviderSearchBatch> _searchProvider(
    MusicProvider provider,
    String query,
  ) async {
    try {
      return _ProviderSearchBatch(
        service: provider.service,
        tracks: await provider.search(query),
      );
    } catch (error) {
      return _ProviderSearchBatch(service: provider.service, error: error);
    }
  }

  Future<_ProviderSearchBatch> _searchOfficialNetease(
    WebPlaybackEngine engine,
    String query,
  ) async {
    try {
      final tracks = await engine.searchNetease(query);
      return _ProviderSearchBatch(
        service: MusicService.netease,
        tracks: [
          for (final track in tracks)
            if (track.sourceFor(MusicService.netease) case final source?)
              ProviderTrack(
                service: MusicService.netease,
                providerTrackId: source.providerTrackId,
                title: track.title,
                artist: track.artist,
                album: track.album,
                duration: track.duration,
                artworkUrl: track.artworkUrl,
                accentColor: track.accentColor,
                versionMarkers: track.versionMarkers,
                officialHandoffUri: source.officialHandoffUri,
                playable: source.playable,
              ),
        ],
      );
    } catch (error) {
      return _ProviderSearchBatch(service: MusicService.netease, error: error);
    }
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
    final existing = _playback.queue.indexWhere((item) => item.id == track.id);
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

    await _loadWebTrackAssets(track);
  }

  /// 加载当前网页曲目的歌词与封面；切歌期间丢弃已经过期的异步结果。
  Future<void> _loadWebTrackAssets(Track track) async {
    final engine = webEngine;
    final source = track.sourceFor(MusicService.netease);
    if (engine == null || source == null) {
      _lyrics = null;
      return;
    }
    final seq = ++_webAssetSeq;
    final lyrics = await engine.fetchLyrics(source.providerTrackId);
    if (_disposed ||
        seq != _webAssetSeq ||
        _playback.current?.id != track.id) {
      return;
    }
    _lyrics = lyrics;
    notifyListeners();

    // 队列里的封面：播放到哪首就补哪首的字节（搜索结果只预抓了前 10 条）。
    var coverUrl = track.artworkUrl ?? '';
    if (coverUrl.isEmpty && source.providerTrackId.isNotEmpty) {
      coverUrl = await engine.fetchCover(source.providerTrackId) ?? '';
      if (_disposed ||
          seq != _webAssetSeq ||
          _playback.current?.id != track.id) {
        return;
      }
    }
    if (!_coverBytes.containsKey(source.providerTrackId) &&
        coverUrl.isNotEmpty) {
      final bytes = await engine.fetchCoverBytes([
        {'id': source.providerTrackId, 'url': coverUrl},
      ]);
      if (_disposed ||
          seq != _webAssetSeq ||
          _playback.current?.id != track.id) {
        return;
      }
      final data = bytes[source.providerTrackId];
      if (data != null && data.isNotEmpty) {
        _coverBytes[source.providerTrackId] = Uint8List.fromList(data);
        notifyListeners();
      }
    }
  }

  /// 读取并接管网易云官方播放列表；只在网页播放模式下生效。
  Future<void> refreshQueue() async {
    final engine = webEngine;
    if (!_webMode || engine == null || !engine.isAttached) return;
    final seq = ++_queueSeq;
    _queueLoading = true;
    notifyListeners();
    final tracks = await engine.fetchNeteaseQueue();
    if (_disposed || seq != _queueSeq) return;
    _queueLoading = false;
    if (tracks.isEmpty) {
      notifyListeners();
      return;
    }

    final state = engine.state;
    var index = state.nowPlayingId.isEmpty
        ? -1
        : tracks.indexWhere(
            (track) =>
                track.sourceFor(MusicService.netease)?.providerTrackId ==
                state.nowPlayingId,
          );
    if (index < 0) {
      final label = _webStateTitle(state);
      if (label.isNotEmpty) {
        index = tracks.indexWhere((track) => track.title == label);
      }
    }
    _officialQueueMode = true;
    _playback = PlaybackState(
      queue: tracks,
      queueIndex: index,
      position: state.position,
      status: state.paused ? PlaybackStatus.paused : PlaybackStatus.playing,
      activeService: MusicService.netease,
    );
    notifyListeners();
  }

  void _onWebEngineChanged() {
    _refreshProviderStates();
    if (!_webMode) {
      notifyListeners();
      return;
    }
    final state = webEngine?.state;
    if (state == null || !state.hasMedia) return;
    // 正在打开新曲目时，网页可能还会短暂上报上一首状态，不能据此回滚界面。
    if (_playback.status == PlaybackStatus.loading) return;
    if (state.ended) {
      _handleTrackCompleted(position: state.duration);
      return;
    }

    final actualIndex = _queueIndexForWebState(state);
    if (actualIndex != null && actualIndex != _playback.queueIndex) {
      final track = _playback.queue[actualIndex];
      _playback = PlaybackState(
        queue: _playback.queue,
        queueIndex: actualIndex,
        position: state.position,
        status:
            state.paused ? PlaybackStatus.paused : PlaybackStatus.playing,
        activeService: MusicService.netease,
      );
      _lyrics = null;
      notifyListeners();
      unawaited(_loadWebTrackAssets(track));
      return;
    }
    if (actualIndex == null) {
      final external = _externalWebTrack(state);
      if (external != null) {
        final queue = List<Track>.from(_playback.queue);
        final insertAt = (_playback.queueIndex + 1).clamp(0, queue.length);
        queue.insert(insertAt, external);
        _playback = PlaybackState(
          queue: queue,
          queueIndex: insertAt,
          position: state.position,
          status:
              state.paused ? PlaybackStatus.paused : PlaybackStatus.playing,
          activeService: MusicService.netease,
        );
        _lyrics = null;
        notifyListeners();
        unawaited(_loadWebTrackAssets(external));
        return;
      }
    }

    _playback = _playback.copyWith(
      position: state.position,
      status: state.paused ? PlaybackStatus.paused : PlaybackStatus.playing,
      clearBlock: true,
      message: '',
    );
    notifyListeners();
  }

  /// 官方网页会自行播放下一首；优先用歌曲 ID，回退到 Media Session / DOM 标题。
  int? _queueIndexForWebState(WebPlayerState state) {
    final actualId = state.nowPlayingId.trim();
    if (actualId.isNotEmpty) {
      for (var i = 0; i < _playback.queue.length; i++) {
        final source = _playback.queue[i].sourceFor(MusicService.netease);
        if (source?.providerTrackId == actualId) return i;
      }
    }

    final label = _webStateTitle(state);
    final actual = label.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    if (actual.isEmpty) return null;

    bool fullMatch(Track track) {
      final expected =
          track.title.replaceAll(RegExp(r'\s+'), '').toLowerCase();
      return expected.isNotEmpty && actual.contains(expected);
    }

    bool durationMatches(Track track) {
      if (state.duration <= Duration.zero ||
          track.duration <= Duration.zero) {
        return true;
      }
      return (state.duration - track.duration).inSeconds.abs() <= 10;
    }

    for (var i = 0; i < _playback.queue.length; i++) {
      final track = _playback.queue[i];
      if (fullMatch(track) && durationMatches(track)) return i;
    }

    final actualBase = normalizeTitle(label).replaceAll(RegExp(r'\s+'), '');
    if (actualBase.isEmpty) return null;
    for (var i = 0; i < _playback.queue.length; i++) {
      final track = _playback.queue[i];
      final expectedBase = normalizeTitle(track.title);
      if (actualBase.contains(expectedBase) && durationMatches(track)) {
        return i;
      }
    }
    return null;
  }

  String _webStateTitle(WebPlayerState state) =>
      state.mediaSessionTitle.trim().isNotEmpty
      ? state.mediaSessionTitle.trim()
      : state.nowPlaying.trim();

  /// 网页自行播放推荐曲时可能不在应用队列中；把它作为新的真实来源接入队列。
  Track? _externalWebTrack(WebPlayerState state) {
    final title = _webStateTitle(state);
    final id = state.nowPlayingId.trim();
    if (title.isEmpty && id.isEmpty) return null;
    final artist = state.mediaSessionArtist.trim();
    final album = state.mediaSessionAlbum.trim();
    final source = TrackSource(
      service: MusicService.netease,
      providerTrackId: id,
      playable: id.isNotEmpty,
      officialHandoffUri: id.isEmpty
          ? null
          : Uri.tryParse('https://music.163.com/song?id=$id'),
    );
    return Track(
      id: id.isNotEmpty
          ? 'netease-web-$id'
          : 'netease-web-${title.hashCode}-${artist.hashCode}',
      title: title.isEmpty ? '网易云音乐当前曲目' : title,
      artist: artist.isEmpty ? '网易云音乐' : artist,
      album: album,
      duration: state.duration,
      sources: [source],
    );
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

    if (_officialQueueMode && (webEngine?.isAttached ?? false)) {
      final source = track.sourceFor(MusicService.netease);
      final ok = source == null
          ? false
          : await webEngine!.playNeteaseQueueItem(
              source.providerTrackId,
            );
      if (!ok) {
        _playback = _machine.block(
          _playback,
          BlockReason.notSupported,
          '官方播放列表无法切换到该曲目',
        );
        notifyListeners();
        return;
      }
      final state = webEngine!.state;
      _playback = _playback.copyWith(
        position: state.position,
        status: state.paused
            ? PlaybackStatus.paused
            : PlaybackStatus.playing,
        clearBlock: true,
        message: '',
      );
      _lyrics = null;
      notifyListeners();
      await _loadWebTrackAssets(track);
      return;
    }
    await _playTrack(track);
  }

  Future<void> switchSource(MusicService service) async {
    final track = _playback.current;
    if (track == null) return;
    if (track.sourceFor(service) == null) return;
    final position = _playback.position;
    _playback = _machine.switchSource(_playback, service);
    notifyListeners();
    await _startPlayback(
      track,
      service,
      resetPosition: false,
      keepPosition: position,
    );
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

      final start = resetPosition
          ? Duration.zero
          : (keepPosition ?? Duration.zero);
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
    if (_officialQueueMode) {
      await playAt(_playback.queueIndex + 1);
      return;
    }
    final target = _playback.queue[_playback.queueIndex + 1];
    _playback = _machine.next(_playback);
    notifyListeners();
    await _playTrack(target);
  }

  Future<void> previous() async {
    if (_playback.queue.isEmpty) return;
    if (_officialQueueMode) {
      if (_playback.position > const Duration(seconds: 3)) {
        await seekTo(Duration.zero);
      } else if (_playback.hasPrevious) {
        await playAt(_playback.queueIndex - 1);
      } else {
        await seekTo(Duration.zero);
      }
      return;
    }
    final wasPlaying = _playback.status == PlaybackStatus.playing;
    final beforeIndex = _playback.queueIndex;
    _playback = _machine.previous(_playback);
    final track = _playback.current;
    if (track == null) return;

    if (_playback.queueIndex == beforeIndex &&
        _playback.position == Duration.zero &&
        wasPlaying) {
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
    _viewMode = _viewMode == ViewMode.split
        ? ViewMode.immersive
        : ViewMode.split;
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
    if (track.duration > Duration.zero && clamped >= track.duration) {
      _handleTrackCompleted(position: track.duration);
      return;
    }
    _playback = _playback.copyWith(position: clamped);
    notifyListeners();
  }

  void _handleTrackCompleted({Duration? position}) {
    final track = _playback.current;
    if (track == null) return;
    if (_playback.hasNext) {
      _clock.pause();
      unawaited(next());
      return;
    }
    _clock.pause();
    _playback = _playback.copyWith(
      position: position ?? track.duration,
      status: PlaybackStatus.paused,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    webEngine?.removeListener(_onWebEngineChanged);
    _clockSubscription?.cancel();
    unawaited(_clock.dispose());
    super.dispose();
  }
}
