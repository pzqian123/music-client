import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'application/music_controller.dart';
import 'platform/desktop_window_service.dart';
import 'platform/io_http_fetcher.dart';
import 'platform/secure_credentials.dart';
import 'platform/spotify_auth.dart';
import 'platform/web_playback_engine.dart';
import 'presentation/app_shell.dart';
import 'presentation/app_window_chrome.dart';
import 'presentation/web_player_ui.dart';
import 'presentation/widgets/hidden_web_player.dart';
import 'providers/music_provider.dart';
import 'providers/fake_netease_provider.dart';
import 'providers/fake_spotify_provider.dart';
import 'providers/spotify_provider.dart';

/// 演示默认 Provider 集合。
List<MusicProvider> buildDemoProviders() => [
  FakeSpotifyProvider(),
  FakeNeteaseProvider(),
];

/// 调试开关：启动即显示官方页面（仅用于自动化验证）。
const bool _autoOpenOfficial = bool.fromEnvironment('DSH_AUTO_OPEN_OFFICIAL');

/// Spotify 客户端 ID 是公开标识，通过构建参数注入；client secret 不进入客户端。
const String _spotifyClientId = String.fromEnvironment('SPOTIFY_CLIENT_ID');

/// 测试环境（flutter test）不挂 WebView，避免缺少平台通道。
bool get webPlayerSupported {
  if (kIsWeb) return false;
  if (!Platform.isWindows && !Platform.isAndroid) return false;
  return Platform.environment['FLUTTER_TEST'] != 'true';
}

class MusicApp extends StatefulWidget {
  const MusicApp({
    super.key,
    this.controller,
    this.windowService = const WindowManagerService(),
    this.showWindowControls = false,
  });

  /// 测试时可注入已构造的控制器；注入时不会创建 WebView。
  final MusicController? controller;
  final DesktopWindowService windowService;
  final bool showWindowControls;

  @override
  State<MusicApp> createState() => _MusicAppState();
}

class _MusicAppState extends State<MusicApp> {
  late final WebPlayerHandle? _handle;
  late final WebPlaybackEngine? _engine;
  late final WebPlayerUi _ui;
  MusicController? _ownedController;
  SpotifyProvider? _spotifyProvider;

  MusicController get _controller => widget.controller ?? _ownedController!;

  @override
  void initState() {
    super.initState();
    _ui = WebPlayerUi();
    if (widget.controller != null) {
      // 注入控制器时（测试）不创建网页播放引擎。
      _handle = null;
      _engine = null;
      _ownedController = widget.controller;
      return;
    }
    if (!webPlayerSupported) {
      // 不支持的平台：仍然创建引擎对象，只是不挂 WebView（状态显示"未挂载"）。
      _handle = WebPlayerHandle();
      _engine = WebPlaybackEngine(bridge: HandleWebPlayerBridge(_handle!));
      _ownedController = MusicController(
        providers: _buildProviders(webAttached: false),
        webEngine: _engine,
      );
      _engine?.start();
      return;
    }
    _handle = WebPlayerHandle();
    _engine = WebPlaybackEngine(bridge: HandleWebPlayerBridge(_handle!));
    _ownedController = MusicController(
      providers: _buildProviders(webAttached: true),
      webEngine: _engine,
    );
    _engine!.start();
    unawaited(_restoreSpotifySession());
    if (_autoOpenOfficial) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ui.open();
      });
    }
  }

  List<MusicProvider> _buildProviders({required bool webAttached}) {
    if (!webAttached) return buildDemoProviders();

    if (_spotifyClientId.isEmpty) {
      return [FakeSpotifyProvider()];
    }

    final credentials = FlutterSecureStorageCredentials();
    final auth = SpotifyAuth(
      clientId: _spotifyClientId,
      credentials: credentials,
      httpFetcher: fetchWithIo,
      browserLauncher: _launchExternalBrowser,
    );
    final provider = SpotifyProvider(
      clientId: _spotifyClientId,
      credentials: credentials,
      fetcher: fetchWithIo,
      auth: auth,
    );
    _spotifyProvider = provider;
    return [provider];
  }

  Future<void> _restoreSpotifySession() async {
    final provider = _spotifyProvider;
    if (provider == null) return;
    await provider.restoreSession();
    if (!mounted) return;
    _ownedController?.refreshProviders();
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _ownedController?.dispose();
      _engine?.dispose();
    }
    _ui.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shell = MaterialApp(
      title: '音乐聚合',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: Builder(
        builder: (context) {
          final immersive = context.select<MusicController, bool>(
            (controller) =>
                controller.viewMode == ViewMode.immersive &&
                controller.playback.current != null,
          );
          return AppWindowChrome(
            windowService: widget.windowService,
            showWindowControls: widget.showWindowControls,
            immersive: immersive,
            child: const AppShell(),
          );
        },
      ),
    );

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<MusicController>.value(value: _controller),
        ChangeNotifierProvider<WebPlayerUi>.value(value: _ui),
        if (_engine != null)
          ChangeNotifierProvider<WebPlaybackEngine>.value(value: _engine),
        if (_handle != null) Provider<WebPlayerHandle>.value(value: _handle),
      ],
      child: shell,
    );
  }
}

Future<bool> _launchExternalBrowser(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

ThemeData buildTheme() {
  const background = Color(0xFF0B0B0F);
  const surface = Color(0xFF15151B);
  const outline = Color(0xFF2A2A33);

  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF1DB954),
        brightness: Brightness.dark,
      ).copyWith(
        surface: background,
        surfaceContainerHighest: surface,
        outline: outline,
      );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    dividerColor: outline,
    cardTheme: const CardThemeData(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
        side: BorderSide(color: outline),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: outline),
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: Color(0xFF1F3A2A),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: surface,
      indicatorColor: Color(0xFF1F3A2A),
    ),
  );
}
