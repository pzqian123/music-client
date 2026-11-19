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
import 'spotify_web_scripts.dart';
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
  Future<String> clickSongPagePlay();
  Future<String> pageTitle();
  Future<void> openHomeFor(WebPlayerTarget target);
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
  Future<String> clickSongPagePlay() => handle.clickSongPagePlay();

  @override
  Future<String> pageTitle() => handle.pageTitle();

  @override
  Future<void> openHomeFor(WebPlayerTarget target) => handle.openHome(target);

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

class OfficialQueueItem {
  final String id;
  final String title;
  final String artist;
  final String duration;
  final bool selected;

  const OfficialQueueItem({
    required this.id,
    required this.title,
    required this.artist,
    required this.duration,
    this.selected = false,
  });
}

List<OfficialQueueItem> parseOfficialQueue(String raw) {
  final trimmed = raw.trim();
  if (!trimmed.startsWith('{')) return const [];
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map<String, dynamic>) return const [];
    final items = decoded['items'];
    if (items is! List) return const [];
    return [
      for (final item in items)
        if (item is Map<String, dynamic> &&
            item['id'] is String &&
            (item['id'] as String).isNotEmpty &&
            item['title'] is String &&
            (item['title'] as String).isNotEmpty)
          OfficialQueueItem(
            id: item['id'] as String,
            title: item['title'] as String,
            artist: (item['artist'] as String?) ?? '',
            duration: (item['duration'] as String?) ?? '',
            selected: item['selected'] == true,
          ),
    ];
  } catch (_) {
    return const [];
  }
}

Track trackFromOfficialQueueItem(OfficialQueueItem item) {
  return Track(
    id: 'netease-web-${item.id}',
    title: item.title,
    artist: item.artist,
    album: '',
    duration: parseClockDuration(item.duration),
    sources: [
      TrackSource(
        service: MusicService.netease,
        providerTrackId: item.id,
        playable: true,
        officialHandoffUri: Uri.tryParse(
          'https://music.163.com/song?id=${item.id}',
        ),
      ),
    ],
  );
}

/// Spotify 官方网页搜索结果条目。
class SpotifySearchResult {
  final String id;
  final String title;
  final String artist;
  final String duration;
  final String cover;

  const SpotifySearchResult({
    required this.id,
    required this.title,
    required this.artist,
    this.duration = '',
    this.cover = '',
  });
}

/// 解析 `spotifyParseSearchScript` 返回的 JSON。
List<SpotifySearchResult> parseSpotifySearch(String raw) {
  final trimmed = raw.trim();
  if (!trimmed.startsWith('{')) return const [];
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map<String, dynamic>) return const [];
    final items = decoded['items'];
    if (items is! List) return const [];
    final results = <SpotifySearchResult>[];
    for (final item in items) {
      if (item is! Map<String, dynamic>) continue;
      final id = item['id'];
      final title = item['title'];
      if (id is! String || id.isEmpty || title is! String || title.isEmpty) {
        continue;
      }
      results.add(
        SpotifySearchResult(
          id: id,
          title: title,
          artist: (item['artist'] as String?) ?? '',
          duration: (item['duration'] as String?) ?? '',
          cover: (item['cover'] as String?) ?? '',
        ),
      );
    }
    return results;
  } catch (_) {
    return const [];
  }
}

/// 把 Spotify 网页搜索结果转成领域 [Track]。
Track trackFromSpotifyResult(SpotifySearchResult result) {
  final cover = upgradeSpotifyCover(result.cover);
  return Track(
    id: 'spotify-web-${result.id}',
    title: result.title,
    artist: result.artist,
    album: '',
    duration: parseClockDuration(result.duration),
    artworkUrl: cover.isEmpty ? null : cover,
    sources: [
      TrackSource(
        service: MusicService.spotify,
        providerTrackId: result.id,
        playable: true,
        officialHandoffUri: Uri.tryParse(
          'https://open.spotify.com/track/${result.id}',
        ),
      ),
    ],
  );
}

class WebPlaybackEngine extends ChangeNotifier {
  WebPlaybackEngine({
    required this.bridge,
    this.pollInterval = const Duration(milliseconds: 700),
    MusicService initialService = MusicService.netease,
  }) : _service = initialService;

  final WebPlayerBridge bridge;
  final Duration pollInterval;

  MusicService _service;

  /// 当前隐藏页面承载的服务：决定搜索结果页、曲目深链接和解析脚本。
  MusicService get service => _service;

  WebPlayerState _state = const WebPlayerState.empty();
  Timer? _timer;
  String? _lastError;
  bool _switching = false;

  bool get isSwitchingService => _switching;

  bool get isBusy => _busy;

  bool _busy = false;

  WebPlayerState get state => _state;

  String? get lastError => _lastError;

  bool get isAttached => bridge.isAttached;

  WebPlayerTarget get target => webTargetFor(_service) ?? neteaseWebTarget;

  /// 切换隐藏页面承载的服务（会导航到该服务的首页，登录态各自独立保存）。
  Future<void> useService(MusicService next) async {
    if (_service == next) return;
    _service = next;
    _state = const WebPlayerState.empty();
    _lastError = null;
    _switching = true;
    notifyListeners();
    try {
      await bridge.openHomeFor(target);
    } catch (_) {
      // 导航失败不阻塞后续操作，用户仍可手动打开官方页面。
    } finally {
      _switching = false;
      notifyListeners();
    }
  }

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
    if (a.nowPlayingId != b.nowPlayingId) return false;
    if (a.mediaSessionTitle != b.mediaSessionTitle) return false;
    if (a.mediaSessionArtist != b.mediaSessionArtist) return false;
    if (a.mediaSessionAlbum != b.mediaSessionAlbum) return false;
    return (a.position.inMilliseconds - b.position.inMilliseconds).abs() < 400;
  }

  Future<List<Track>> searchNetease(String query) async {
    if (query.trim().isEmpty) return const [];
    final results = await bridge.searchNetease(query);
    return results.map(trackFromOfficialResult).toList();
  }

  /// 在官方页面里搜索 Spotify（曲目页签），不依赖 Web API / Client ID。
  Future<List<Track>> searchSpotify(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty || !bridge.isAttached) return const [];
    try {
      await bridge.runScript(spotifySearchScript(trimmed));
      // 页面要重新渲染 + 拉接口，轮询到出现结果或超时。
      for (var attempt = 0; attempt < 26; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 420));
        final raw = await bridge.runScript(spotifyParseSearchScript);
        final results = parseSpotifySearch(raw);
        if (results.isNotEmpty) {
          return results.map(trackFromSpotifyResult).toList();
        }
      }
    } catch (_) {}
    return const [];
  }

  /// 按当前承载的服务发起官方页面搜索。
  Future<List<Track>> searchWeb(String query) {
    return _service == MusicService.spotify
        ? searchSpotify(query)
        : searchNetease(query);
  }

  /// 当前是否已登录（Spotify 用播放条上的用户菜单判断；网易云用本地歌曲入口判断）。
  Future<bool?> detectLogin() async {
    if (!bridge.isAttached) return null;
    try {
      if (_service == MusicService.spotify) {
        final raw = await bridge.runScript(spotifyLoginStateScript);
        final decoded = _decode(raw);
        if (decoded == null) return null;
        return decoded['loggedIn'] == true;
      }
      final raw = await bridge.runScript(mediaStateScript);
      final decoded = _decode(raw);
      if (decoded == null) return null;
      // 网易云：页面能读到播放栏/媒体元素即视为可用会话。
      return decoded['hasMedia'] == true ||
          ((decoded['pageTitle'] as String?) ?? '').contains('网易云');
    } catch (_) {
      return null;
    }
  }

  /// 读取网易云官方网页的真实播放队列。
  Future<List<Track>> fetchNeteaseQueue() async {
    if (_service != MusicService.netease) return const [];
    try {
      await bridge.runScript(neteaseQueueOpenScript);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final raw = await bridge.runScript(neteaseQueueReadScript);
      final items = parseOfficialQueue(raw);
      return items.map(trackFromOfficialQueueItem).toList();
    } catch (_) {
      return const [];
    }
  }

  /// 点击官方播放列表中的曲目，保留网页自己的队列顺序和权益判断。
  Future<bool> playNeteaseQueueItem(String songId) async {
    if (songId.isEmpty || _service != MusicService.netease) return false;
    try {
      await bridge.runScript(neteaseQueueOpenScript);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final clicked = await bridge.runScript(
        neteaseQueuePlayScript(songId),
      );
      if (!clicked.startsWith('clicked')) return false;
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await _poll();
        if (_state.hasMedia &&
            _state.nowPlayingId == songId &&
            !_state.paused) {
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// 打开曲目页并点击官方播放按钮，返回是否成功起播。
  ///
  /// 关键点：只点歌曲页自己的播放按钮；如果页面还没渲染出来就继续等，
  /// 绝不回退到播放栏的播放键（那会变成"继续上一首"）。
  Future<bool> playTrack(Track track) async {
    final source = track.sourceFor(service);
    if (source == null) return false;
    _busy = true;
    _lastError = null;
    notifyListeners();
    try {
      var clicked = await _openAndClick(source.providerTrackId, attempt: 0);

      // 页面没渲染出播放按钮（常见于 VIP/无版权曲目或页面卡住）：
      // 回首页再打开一次，避免把 WebView 留在坏状态——否则后续点歌都会失败。
      if (!clicked) {
        await bridge.openHomeFor(target);
        await Future<void>.delayed(const Duration(milliseconds: 2500));
        clicked = await _openAndClick(source.providerTrackId, attempt: 1);
      }

      if (!clicked) {
        _lastError = _service == MusicService.spotify
            ? '这首曲目在官方页面没有播放按钮（可能需要登录，或该地区不可用）'
            : '这首歌在官方页面无法播放（可能需要 VIP 或无版权）';
        return false;
      }

      // 等真实元素起播，并确认放的是目标曲目（标题匹配）而不是上一首。
      // 注意：只在"确实放错了歌"时才补点一次，避免重复点击把歌重头播。
      // Spotify 是整页重载 + DRM 起播，给的时间要明显更长。
      final expected = _normalize(track.title);
      final tries = _service == MusicService.spotify ? 34 : 8;
      for (var attempt = 0; attempt < 2; attempt++) {
        if (await _waitForPlayback(expected, tries: tries)) return true;
        if (attempt == 0) {
          if (_service == MusicService.spotify) {
            await bridge.runScript(spotifyTrackPlayScript);
          } else {
            await bridge.clickSongPagePlay();
          }
          await Future<void>.delayed(const Duration(milliseconds: 1500));
        }
      }

      _lastError = _state.hasMedia && _state.nowPlaying.isNotEmpty
          ? '官方页面没有切到目标曲目（当前显示「${_state.nowPlaying}」），请稍后重试'
          : _service == MusicService.spotify
          ? '官方页面未开始播放（请先在「连接」页登录 Spotify）'
          : '官方页面未开始播放（可能是 VIP 或版权限制）';
      return false;
    } catch (error) {
      _lastError = '$error';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 轮询等待"正在播放且曲目匹配"。
  ///
  /// 判定顺序：Media Session 元数据（最及时）→ 播放栏曲名 → 页面标题。
  /// 只要其一匹配就算成功，避免因为播放栏文字延迟而重复点击、把歌重头播。
  ///
  /// 若曲目已经切对但播放器停在暂停（Spotify 整页重载后偶发），补一次 play()。
  Future<bool> _waitForPlayback(String expected, {required int tries}) async {
    var pausedMatches = 0;
    for (var i = 0; i < tries; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await _poll();
      if (!_state.hasMedia || _state.duration.inMilliseconds == 0) continue;

      final titleMatched =
          _titleMatches(_state.mediaSessionTitle, expected) ||
          _titleMatches(_state.nowPlaying, expected);

      if (_state.paused) {
        if (titleMatched) {
          pausedMatches++;
          if (pausedMatches == 2) {
            await bridge.play();
            await Future<void>.delayed(const Duration(milliseconds: 700));
            await _poll();
            if (_state.hasMedia && !_state.paused) return true;
          }
        }
        continue;
      }
      if (titleMatched) return true;
      if (i % 2 == 1) {
        final title = await bridge.pageTitle();
        if (_titleMatches(title, expected)) return true;
      }
    }
    return false;
  }

  static String _normalize(String value) =>
      value.replaceAll(RegExp(r'\s+'), '').toLowerCase();

  /// 打开曲目页并尝试点中播放按钮，返回是否点到了（或本来就在播）。
  Future<bool> _openAndClick(String trackId, {required int attempt}) async {
    await bridge.openTrack(target, trackId);
    // Spotify 是整页重载，首屏比网易云的 hash 路由慢。
    final rounds = _service == MusicService.spotify ? 24 : 14;
    for (var i = 0; i < rounds; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final result = _service == MusicService.spotify
          ? await bridge.runScript(spotifyTrackPlayScript)
          : await bridge.clickSongPagePlay();
      if (result.startsWith('click-error')) return false;
      if (result.startsWith('clicked') ||
          result.startsWith('already-playing')) {
        return true;
      }
    }
    return false;
  }

  static bool _titleMatches(String nowPlaying, String expected) {
    if (nowPlaying.isEmpty) return false;
    final actual = _normalize(nowPlaying);
    if (actual.isEmpty) return false;
    if (actual.contains(expected) || expected.contains(actual)) return true;
    // 标题常带括号后缀（如「晴天(深情版)」），比较前缀即可。
    final short = expected.length >= 6 ? expected.substring(0, 6) : expected;
    return actual.contains(short);
  }

  /// 通过官方页面抓取封面字节（绕过图床的 UA 拦截）。
  ///
  /// 只有网易云图床需要这招；Spotify 的 i.scdn.co 允许直连，直接给 artworkUrl。
  Future<Map<String, List<int>>> fetchCoverBytes(
    List<Map<String, String>> items,
  ) async {
    if (items.isEmpty || _service != MusicService.netease) return const {};
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
    if (songIds.isEmpty || _service != MusicService.netease) return const {};
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
  ///
  /// Spotify 的歌词走私有接口（spclient + 令牌），网页版也没有 LRC 文本，
  /// 因此只对网易云生效，Spotify 返回 null 让界面走"无歌词"分支。
  Future<LyricTimeline?> fetchLyrics(String songId) async {
    if (songId.isEmpty || _service != MusicService.netease) return null;
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
      nowPlayingId: _state.nowPlayingId,
      mediaSessionTitle: _state.mediaSessionTitle,
      mediaSessionArtist: _state.mediaSessionArtist,
      mediaSessionAlbum: _state.mediaSessionAlbum,
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
