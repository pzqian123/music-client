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
    WebPlaybackEngine? webEngine,
    Map<MusicService, WebPlaybackEngine>? webEngines,
  }) : providers = List.unmodifiable(providers),
       _clock = clock ?? TimerClock(),
       _credentials = credentials ?? InMemoryCredentials(),
       _handoff = handoff ?? const UrlLauncherHandoff(),
       webEngines = Map.unmodifiable(
         webEngines ??
             (webEngine == null
                 ? const <MusicService, WebPlaybackEngine>{}
                 : <MusicService, WebPlaybackEngine>{webEngine.service: webEngine}),
       ) {
    _providerStates = const {};
    _refreshProviderStates();
    _clockSubscription = _clock.positions.listen(_onClockTick);
    for (final engine in this.webEngines.values) {
      engine.addListener(() => _onWebEngineChanged(engine));
    }
  }

  final List<MusicProvider> providers;
  final PlaybackClock _clock;
  final SecureCredentials _credentials;
  final OfficialHandoff _handoff;

  /// 每个服务一个官方网页播放器（网易云 / Spotify 各一个，常驻）。
  ///
  /// 两头都在同一个 WebView2 profile 里，登录态各自独立；同一时刻只有一家在出声。
  final Map<MusicService, WebPlaybackEngine> webEngines;

  /// 当前真正在出声的那一家。
  WebPlaybackEngine? _activeWebEngine;

  /// 兼容旧调用：没有活跃引擎时回落到网易云（其次任意一个已挂载的）。
  WebPlaybackEngine? get webEngine {
    final active = _activeWebEngine;
    if (active != null) return active;
    if (webEngines.isEmpty) return null;
    return webEngines[MusicService.netease] ?? webEngines.values.first;
  }

  WebPlaybackEngine? engineFor(MusicService service) => webEngines[service];

  Iterable<WebPlaybackEngine> get _attachedEngines =>
      webEngines.values.where((engine) => engine.isAttached);

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
    // 每挂载一家官方网页播放器，就把该服务标成"由官方页面提供"。
    for (final engine in _attachedEngines) {
      states[engine.service] = ProviderSnapshot(
        service: engine.service,
        state: ProviderState.connected,
        capabilities: ProviderCapabilities(
          search: true,
          metadata: true,
          // Spotify 的歌词由网易云页面按同曲匹配后提供，所以也算有歌词。
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

    final engines = _attachedEngines.toList();
    final officialEnabled = engines.isNotEmpty;
    final futures = <Future<_ProviderSearchBatch>>[];

    // 两家官方页面常驻，所以一次搜索能同时拿到两个平台的真实结果。
    for (final engine in engines) {
      futures.add(_searchOfficialWeb(engine, trimmed));
    }

    // 官方网页模式只合并真实 Provider，避免演示目录混入线上搜索结果；
    // 已经在官方页面里搜过的服务不再重复请求。
    final activeProviders = officialEnabled
        ? providers.where(
            (provider) =>
                !provider.isDemo &&
                !engines.any((engine) => engine.service == provider.service),
          )
        : providers;
    for (final provider in activeProviders) {
      futures.add(_searchProvider(provider, trimmed));
    }

    final responses = await Future.wait(futures);
    if (seq != _searchSeq) return; // 竞态保护：丢弃过期结果

    final collected = <ProviderTrack>[];
    final errors = <MusicService, ProviderError>{};
    final officialServices = engines.map((engine) => engine.service).toSet();
    for (final response in responses) {
      if (response.error == null) {
        collected.addAll(response.tracks);
        if (officialServices.contains(response.service)) {
          _usedOfficialSearch = true;
        }
      } else {
        final error = response.error!;
        errors[response.service] = ProviderError(
          service: response.service,
          message: error is ProviderException
              ? error.message
              : officialServices.contains(response.service)
              ? '官方页面搜索失败：$error'
              : '加载失败，请重试',
        );
      }
    }

    final merged = mergeProviderTracks(collected);
    var tracks = merged.tracks;

    // 合并后再补网易云封面，保证 Spotify + 网易云同曲不会因先取封面而错过合并。
    final neteaseEngine = webEngines[MusicService.netease];
    if (neteaseEngine != null && neteaseEngine.isAttached) {
      final engine = neteaseEngine;
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

  Future<_ProviderSearchBatch> _searchOfficialWeb(
    WebPlaybackEngine engine,
    String query,
  ) async {
    final service = engine.service;
    try {
      final tracks = await engine.searchWeb(query);
      return _ProviderSearchBatch(
        service: service,
        tracks: [
          for (final track in tracks)
            if (track.sourceFor(service) case final source?)
              ProviderTrack(
                service: service,
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
      return _ProviderSearchBatch(service: service, error: error);
    }
  }

  /// 选播放引擎：显式来源 > 当前在播的那家 > 轨道的首选来源。
  ///
  /// 两家官方页面常驻，所以只要对应服务挂载了就一定能内播。
  WebPlaybackEngine? _engineForPlayback(Track track, MusicService? service) {
    final explicit = service ?? track.preferredSource?.service;
    if (explicit != null && track.sourceFor(explicit) != null) {
      final engine = webEngines[explicit];
      if (engine != null && engine.isAttached) return engine;
    }
    final active = _activeWebEngine;
    if (active != null && active.isAttached && track.sourceFor(active.service) != null) {
      return active;
    }
    for (final engine in _attachedEngines) {
      if (track.sourceFor(engine.service) != null) return engine;
    }
    return null;
  }

  static bool _isWebHosted(MusicService service) =>
      service == MusicService.netease || service == MusicService.spotify;

  /// 播放入口：统一决定走隐藏的官方页面还是演示播放。
  Future<void> _playTrack(Track track, {MusicService? service}) async {
    final engine = _engineForPlayback(track, service);
    if (engine != null) {
      await _playViaWeb(track, engine);
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

  Future<void> _playViaWeb(Track track, WebPlaybackEngine engine) async {
    final service = engine.service;
    // 另一家还在响就先停掉，保证同一时刻只有一家在出声。
    final previous = _activeWebEngine;
    if (previous != null && previous != engine) {
      try {
        await previous.pausePlayback();
      } catch (_) {}
    }
    _activeWebEngine = engine;
    _webMode = true;
    // 切歌先清空上一条的进度与状态，避免失败后残留旧曲目的时间和歌词。
    _lyrics = null;
    _playback = PlaybackState(
      queue: _playback.queue,
      queueIndex: _playback.queueIndex,
      position: Duration.zero,
      status: PlaybackStatus.loading,
      activeService: service,
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
      activeService: service,
    );
    notifyListeners();

    await _loadWebTrackAssets(track, engine);
  }

  /// 加载当前网页曲目的歌词与封面；切歌期间丢弃已经过期的异步结果。
  ///
  /// - 网易云：歌词与封面都走自己的官方页面。
  /// - Spotify：封面直接用它自己的 CDN；歌词去网易云按「同名同艺人」匹配，
  ///   取到 LRC 后喂给同一套歌词引擎（见 [_fetchNeteaseLyricsFor]）。
  Future<void> _loadWebTrackAssets(Track track, WebPlaybackEngine engine) async {
    final source = track.sourceFor(engine.service);
    if (source == null) {
      _lyrics = null;
      return;
    }
    final seq = ++_webAssetSeq;

    if (engine.service != MusicService.netease) {
      final lyrics = await _fetchNeteaseLyricsFor(track);
      if (_disposed ||
          seq != _webAssetSeq ||
          _playback.current?.id != track.id) {
        return;
      }
      _lyrics = lyrics;
      notifyListeners();
      return;
    }

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

  /// Spotify 曲目 → 网易云同曲歌词。
  ///
  /// 做法：在网易云页面里按「标题 + 艺人」搜索，挑标题一致/时长最接近的一条，
  /// 再调网易云自己的歌词接口拿带时间戳的 LRC。匹配不到就返回 null（界面显示暂无歌词）。
  Future<LyricTimeline?> _fetchNeteaseLyricsFor(Track track) async {
    final netease = webEngines[MusicService.netease];
    if (netease == null || !netease.isAttached) return null;
    final title = track.title.trim();
    if (title.isEmpty) return null;
    final artist = track.artist.trim();
    final query = artist.isEmpty ? title : '$title $artist';

    final candidates = await netease.searchWeb(query);
    if (candidates.isEmpty) return null;

    Track? best;
    var bestScore = 0;
    for (final candidate in candidates.take(12)) {
      if (candidate.sourceFor(MusicService.netease) == null) continue;
      final score = _lyricMatchScore(track, candidate);
      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }
    // 分数太低说明只是同名不同曲，宁可不显示歌词也不要张冠李戴。
    if (best == null || bestScore < 2) return null;
    final id = best.sourceFor(MusicService.netease)?.providerTrackId;
    if (id == null || id.isEmpty) return null;
    return netease.fetchLyrics(id);
  }

  static int _lyricMatchScore(Track target, Track candidate) {
    final expected = normalizeTitle(target.title);
    final actual = normalizeTitle(candidate.title);
    var score = 0;
    if (expected.isNotEmpty && actual.isNotEmpty) {
      if (expected == actual) {
        score += 3;
      } else if (actual.contains(expected) || expected.contains(actual)) {
        score += 2;
      }
    }
    final targetArtist = _normalizeLoose(target.artist);
    final actualArtist = _normalizeLoose(candidate.artist);
    if (targetArtist.isNotEmpty &&
        actualArtist.isNotEmpty &&
        (actualArtist.contains(targetArtist) ||
            targetArtist.contains(actualArtist))) {
      score += 1;
    }
    if (target.duration > Duration.zero && candidate.duration > Duration.zero) {
      final diff = (target.duration - candidate.duration).inSeconds.abs();
      if (diff <= 3) {
        score += 2;
      } else if (diff <= 10) {
        score += 1;
      }
    }
    return score;
  }

  static String _normalizeLoose(String value) =>
      value.replaceAll(RegExp(r'\s+'), '').toLowerCase();

  /// 读取并接管网易云官方播放列表；只在网易云网页播放模式下生效。
  Future<void> refreshQueue() async {
    final engine = webEngines[MusicService.netease];
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

  void _onWebEngineChanged(WebPlaybackEngine engine) {
    if (_disposed) return;
    _refreshProviderStates();
    // 只有正在出声的那一家才驱动播放状态；另一家的轮询只管刷新能力快照。
    if (!_webMode || engine != _activeWebEngine) {
      notifyListeners();
      return;
    }
    final state = engine.state;
    if (!state.hasMedia) return;
    // 正在打开新曲目时，网页可能还会短暂上报上一首状态，不能据此回滚界面。
    if (_playback.status == PlaybackStatus.loading) return;
    if (state.ended) {
      _handleTrackCompleted(position: state.duration);
      return;
    }

    final service = engine.service;
    final actualIndex = _queueIndexForWebState(state, service);
    if (actualIndex != null && actualIndex != _playback.queueIndex) {
      final track = _playback.queue[actualIndex];
      _playback = PlaybackState(
        queue: _playback.queue,
        queueIndex: actualIndex,
        position: state.position,
        status:
            state.paused ? PlaybackStatus.paused : PlaybackStatus.playing,
        activeService: service,
      );
      _lyrics = null;
      notifyListeners();
      unawaited(_loadWebTrackAssets(track, engine));
      return;
    }
    if (actualIndex == null) {
      final external = _externalWebTrack(state, service);
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
          activeService: service,
        );
        _lyrics = null;
        notifyListeners();
        unawaited(_loadWebTrackAssets(external, engine));
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
  int? _queueIndexForWebState(WebPlayerState state, MusicService service) {
    final actualId = state.nowPlayingId.trim();
    if (actualId.isNotEmpty) {
      for (var i = 0; i < _playback.queue.length; i++) {
        final source = _playback.queue[i].sourceFor(service);
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
  Track? _externalWebTrack(WebPlayerState state, MusicService service) {
    final title = _webStateTitle(state);
    final id = state.nowPlayingId.trim();
    if (title.isEmpty && id.isEmpty) return null;
    final artist = state.mediaSessionArtist.trim();
    final album = state.mediaSessionAlbum.trim();
    final isSpotify = service == MusicService.spotify;
    final prefix = isSpotify ? 'spotify-web' : 'netease-web';
    final source = TrackSource(
      service: service,
      providerTrackId: id,
      playable: id.isNotEmpty,
      officialHandoffUri: id.isEmpty
          ? null
          : Uri.tryParse(
              isSpotify
                  ? 'https://open.spotify.com/track/$id'
                  : 'https://music.163.com/song?id=$id',
            ),
    );
    return Track(
      id: id.isNotEmpty
          ? '$prefix-$id'
          : '$prefix-${title.hashCode}-${artist.hashCode}',
      title: title.isEmpty
          ? (isSpotify ? 'Spotify 当前曲目' : '网易云音乐当前曲目')
          : title,
      artist: artist.isEmpty
          ? (isSpotify ? 'Spotify' : '网易云音乐')
          : artist,
      album: album,
      duration: state.duration,
      sources: [source],
    );
  }

  /// 拖动进度（网页播放模式下真实生效）。
  Future<void> seekTo(Duration position) async {
    final engine = _activeWebEngine ?? webEngine;
    if (_webMode && engine != null && engine.isAttached) {
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

    final netease = webEngines[MusicService.netease];
    if (_officialQueueMode && (netease?.isAttached ?? false)) {
      final source = track.sourceFor(MusicService.netease);
      final ok = source == null
          ? false
          : await netease!.playNeteaseQueueItem(
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
      _activeWebEngine = netease;
      final state = netease.state;
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
      await _loadWebTrackAssets(track, netease);
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

    final engine = webEngines[service];
    if (engine != null && engine.isAttached && _isWebHosted(service)) {
      await _playViaWeb(track, engine);
      if (position > Duration.zero &&
          _playback.status == PlaybackStatus.playing) {
        await seekTo(position);
      }
      return;
    }

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

    // 网页播放模式：直接操作当前出声的那家官方页面。
    final active = _activeWebEngine;
    if (_webMode && (active?.isAttached ?? false)) {
      await active!.toggle();
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
      final active = _activeWebEngine;
      if (_webMode && (active?.isAttached ?? false)) {
        await active!.seek(Duration.zero);
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

  /// 当前出声的官方页面属于哪一家（未挂载时为 null）。
  MusicService? get webService {
    final active = _activeWebEngine;
    if (active != null && active.isAttached) return active.service;
    final attached = _attachedEngines;
    return attached.isEmpty ? null : attached.first.service;
  }

  /// 指定服务的官方页面是否已挂载（两家常驻，用来越权/能力判断）。
  bool isWebEngineAttached(MusicService service) =>
      webEngines[service]?.isAttached ?? false;

  /// 那一家官方页面当前是否已登录；null 表示无法判断。
  Future<bool?> checkWebLogin(MusicService service) async =>
      webEngines[service]?.detectLogin();

  /// 两家都已登录时返回 true（用于连接页的总览提示）。
  Future<bool> checkAllLoggedIn() async {
    var any = false;
    for (final engine in _attachedEngines) {
      final result = await engine.detectLogin();
      if (result == true) {
        any = true;
      } else if (result == false) {
        return false;
      }
    }
    return any;
  }

  /// 探测当前出声那家是否已登录。
  Future<bool?> checkActiveWebLogin() async {
    final active = _activeWebEngine ?? webEngine;
    if (active == null || !active.isAttached) return null;
    return active.detectLogin();
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
    // 监听器是按引擎创建的闭包，无法单独移除，这里直接清空引用即可；
    // 控制器销毁后引擎回调里的 notifyListeners 会被 _disposed 挡住。
    _clockSubscription?.cancel();
    unawaited(_clock.dispose());
    super.dispose();
  }
}
