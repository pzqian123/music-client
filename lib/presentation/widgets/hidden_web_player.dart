import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../platform/web_player_engine.dart';
import '../../platform/web_player_scripts.dart';

/// 控制隐藏播放器的句柄：由页面创建，交给 [HiddenWebPlayer] 绑定。
class WebPlayerHandle {
  InAppWebViewController? _controller;

  /// 最近一次原始 JS 返回，便于诊断。
  String lastRaw = '';

  /// 最近一次探测到的媒体元素数量。
  int lastMediaCount = -1;

  bool get isAttached => _controller != null;

  void attach(InAppWebViewController controller) => _controller = controller;

  Future<String?> _js(String source) async {
    final controller = _controller;
    if (controller == null) return null;
    final result = await controller.evaluateJavascript(source: source);
    return result?.toString();
  }

  /// 执行任意脚本并返回结果（诊断用）。
  Future<String> runScript(String source) async =>
      await _js(source) ?? '';

  /// 执行返回 JSON 的脚本。
  Future<String> probeJson(String source) async => await _js(source) ?? '{}';

  Future<void> openHome(WebPlayerTarget target) async {
    await _controller?.loadUrl(
      urlRequest: URLRequest(url: WebUri(target.homeUrl)),
    );
  }

  Future<void> openTrack(WebPlayerTarget target, String providerTrackId) async {
    await _controller?.loadUrl(
      urlRequest: URLRequest(url: WebUri(target.trackUrl(providerTrackId))),
    );
  }

  Future<void> loadUrl(String url) async {
    await _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  Future<String> currentUrl() async {
    final url = await _controller?.getUrl();
    return url?.toString() ?? '';
  }

  Future<WebPlayerState> readState() async {
    final raw = await _js(mediaStateScript);
    lastRaw = raw ?? '';
    lastMediaCount = _countFromRaw(lastRaw);
    return decodeState(raw);
  }

  static int _countFromRaw(String raw) {
    final match = RegExp(r'"mediaCount"\s*:\s*(\d+)').firstMatch(raw);
    if (match != null) return int.tryParse(match.group(1)!) ?? -1;
    return raw.contains('"hasMedia":false') ? 0 : -1;
  }

  Future<void> toggle() async {
    await _js(mediaToggleScript);
  }

  Future<void> play() async {
    await _js(mediaPlayScript);
  }

  Future<void> pause() async {
    await _js(mediaPauseScript);
  }

  Future<void> seek(Duration position) async {
    await _js(mediaSeekScript(position.inMilliseconds / 1000));
  }

  /// 点击官方页面上的播放按钮（新打开的曲目页需要它才起播）。
  Future<String> clickOfficialPlay() async =>
      await runScript(neteaseClickPlayScript);

  /// 只点歌曲页自己的播放按钮（不会误触播放栏的"继续上一首"）。
  Future<String> clickSongPagePlay() async =>
      await runScript(neteaseSongPagePlayScript);

  /// 当前页面标题，用于判断是否已切到目标曲目。
  Future<String> pageTitle() async => await runScript(pageTitleScript);

  /// 在官方页面上搜索，并返回解析后的结果（网易云）。
  Future<List<OfficialSearchResult>> searchNetease(
    String query, {
    Duration wait = const Duration(milliseconds: 2600),
  }) async {
    await runScript(neteaseSearchScript(query));
    await Future<void>.delayed(wait);
    final raw = await probeJson(neteaseParseSearchScript);
    return parseOfficialSearch(raw);
  }

  Future<void> setVolume(double volume) async {
    await _js(mediaVolumeScript(volume));
  }
}

/// 官方搜索结果条目。
class OfficialSearchResult {
  final String id;
  final String title;
  final String artist;
  final String duration;

  const OfficialSearchResult({
    required this.id,
    required this.title,
    required this.artist,
    this.duration = '',
  });
}

/// 解析官方搜索脚本返回的 JSON。
List<OfficialSearchResult> parseOfficialSearch(String raw) {
  final trimmed = raw.trim();
  if (!trimmed.startsWith('{')) return const [];
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map<String, dynamic>) return const [];
    final items = decoded['items'];
    if (items is! List) return const [];
    final results = <OfficialSearchResult>[];
    for (final item in items) {
      if (item is! Map<String, dynamic>) continue;
      final id = item['id'];
      final title = item['title'];
      if (id is! String || id.isEmpty || title is! String || title.isEmpty) {
        continue;
      }
      results.add(
        OfficialSearchResult(
          id: id,
          title: title,
          artist: (item['artist'] as String?) ?? '',
          duration: (item['duration'] as String?) ?? '',
        ),
      );
    }
    return results;
  } catch (_) {
    return const [];
  }
}

/// 把 JS 返回的 JSON 字符串解析为状态；解析失败返回空状态。
WebPlayerState decodeState(String? raw) {
  if (raw == null || raw.isEmpty) return const WebPlayerState.empty();
  final trimmed = raw.trim();
  if (!trimmed.startsWith('{')) return const WebPlayerState.empty();
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map<String, dynamic>) return const WebPlayerState.empty();
    return WebPlayerState.fromJsonObject(decoded);
  } catch (_) {
    return const WebPlayerState.empty();
  }
}

/// 官方网页播放器宿主。
///
/// 重要：**绝不改变它的尺寸或把它移出屏幕**。WebView2 一旦被重新布局或判定不可见，
/// 页面可能重载、音频会被暂停。要"隐藏"时，请在本组件之上盖一层不透明面板。
class HiddenWebPlayer extends StatefulWidget {
  const HiddenWebPlayer({
    super.key,
    required this.target,
    required this.handle,
    this.onLoaded,
  });

  final WebPlayerTarget target;
  final WebPlayerHandle handle;
  final VoidCallback? onLoaded;

  @override
  State<HiddenWebPlayer> createState() => _HiddenWebPlayerState();
}

class _HiddenWebPlayerState extends State<HiddenWebPlayer> {
  WebViewEnvironment? _environment;
  bool _environmentFailed = false;

  @override
  void initState() {
    super.initState();
    _prepareEnvironment();
  }

  /// Windows 需要 WebView2 启动参数：
  /// - `--autoplay-policy=no-user-gesture-required`：允许 JS 直接 play()（否则官方页面必须手点）
  /// - `--disable-features=CalculateNativeWinOcclusion`：页面被盖住时不要判定为不可见而节流
  ///
  /// 同时指定持久化的 userDataFolder：否则每次启动都是新的浏览器会话，官方页面要重新登录。
  Future<void> _prepareEnvironment() async {
    if (!Platform.isWindows) return;
    try {
      final environment = await WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(
          userDataFolder: _userDataFolder(),
          additionalBrowserArguments:
              '--autoplay-policy=no-user-gesture-required '
              '--disable-features=CalculateNativeWinOcclusion',
        ),
      );
      if (!mounted) return;
      setState(() => _environment = environment);
    } catch (_) {
      if (!mounted) return;
      setState(() => _environmentFailed = true);
    }
  }

  String _userDataFolder() {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final base = (localAppData == null || localAppData.isEmpty)
        ? Directory.systemTemp.path
        : localAppData;
    final dir = Directory('$base${Platform.pathSeparator}MusicMerge'
        '${Platform.pathSeparator}webview2');
    if (!dir.existsSync()) {
      try {
        dir.createSync(recursive: true);
      } catch (_) {
        // 创建失败时交给 WebView2 用默认目录。
      }
    }
    return dir.path;
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isWindows && _environment == null && !_environmentFailed) {
      return const SizedBox.shrink();
    }

    return InAppWebView(
      key: const ValueKey('official-web-player'),
      webViewEnvironment: _environment,
      initialUrlRequest: URLRequest(url: WebUri(widget.target.homeUrl)),
      initialUserScripts: UnmodifiableListView<UserScript>([
        UserScript(
          source: mediaTapScript,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
      ]),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        transparentBackground: true,
        allowFileAccess: false,
        useShouldOverrideUrlLoading: false,
        isInspectable: false,
        disableContextMenu: true,
      ),
      onWebViewCreated: (controller) {
        widget.handle.attach(controller);
      },
      onLoadStop: (controller, url) {
        widget.onLoaded?.call();
      },
    );
  }
}
