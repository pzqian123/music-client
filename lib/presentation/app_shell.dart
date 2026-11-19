import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../application/music_controller.dart';
import '../domain/models.dart';
import '../platform/web_player_engine.dart';
import 'connections_page.dart';
import 'immersive_lyrics_page.dart';
import 'player_page.dart';
import 'search_page.dart';
import 'web_player_ui.dart';
import 'widgets/hidden_web_player.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = const int.fromEnvironment('DSH_INITIAL_TAB', defaultValue: 0);

  /// 调试开关：启动后自动搜索，用于无人值守验证真实搜索结果。
  static const String _autoSearch =
      String.fromEnvironment('DSH_AUTO_SEARCH');

  /// 调试开关：搜索完成后自动播放第一条结果（验证歌词与播放控制）。
  static const bool _autoPlayFirst =
      bool.fromEnvironment('DSH_AUTO_PLAY_FIRST');

  /// 调试开关：播放完成后再切到第二条结果，验证切歌。
  static const bool _autoPlaySecond =
      bool.fromEnvironment('DSH_AUTO_PLAY_SECOND');

  /// 调试开关：播放后自动进入沉浸模式，验证不会中断播放。
  static const bool _autoImmersive =
      bool.fromEnvironment('DSH_AUTO_IMMERSIVE');

  @override
  void initState() {
    super.initState();
    if (_autoSearch.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        // 等官方页面就绪后再搜索。
        await Future<void>.delayed(const Duration(seconds: 6));
        if (!mounted) return;
        final controller = context.read<MusicController>();
        await controller.searchFor(_autoSearch);
        if (!mounted) return;
        // 验证模式下自动收起官方页面，确认结果渲染在我们自己的界面里。
        context.read<WebPlayerUi>().close();
        if (!_autoPlayFirst || controller.search.results.isEmpty) return;

        await controller.selectTrack(controller.search.results.first);
        if (!mounted) return;

        if (_autoImmersive) {
          controller.toggleImmersive();
        }

        if (_autoPlaySecond && controller.search.results.length > 1) {
          await Future<void>.delayed(const Duration(seconds: 12));
          if (!mounted) return;
          await controller.selectTrack(controller.search.results[1]);
        }
      });
    }
  }

  static const _destinations = [
    NavigationRailDestination(
      icon: Icon(Icons.search),
      label: Text('搜索'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.play_circle_outline),
      label: Text('播放'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.settings_outlined),
      label: Text('连接'),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final viewMode = context.select<MusicController, ViewMode>(
      (controller) => controller.viewMode,
    );
    final hasTrack = context.select<MusicController, bool>(
      (controller) => controller.playback.current != null,
    );

    final immersive = viewMode == ViewMode.immersive && hasTrack;

    final ui = context.watch<WebPlayerUi>();
    final handles = context.read<Map<MusicService, WebPlayerHandle>?>();
    final engines = context.watch<MusicController>().webEngines;

    final wide = MediaQuery.sizeOf(context).width >= 900;
    final pages = const <Widget>[
      SearchPage(),
      PlayerPage(),
      ConnectionsPage(),
    ];

    final body = IndexedStack(index: _index, children: pages);

    final app = wide
        ? Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: (value) =>
                      setState(() => _index = value),
                  labelType: NavigationRailLabelType.all,
                  destinations: _destinations,
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            ),
          )
        : Scaffold(
            body: body,
            bottomNavigationBar: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (value) => setState(() => _index = value),
              destinations: const [
                NavigationDestination(icon: Icon(Icons.search), label: '搜索'),
                NavigationDestination(
                  icon: Icon(Icons.play_circle_outline),
                  label: '播放',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  label: '连接',
                ),
              ],
            ),
          );

    if (handles == null || handles.isEmpty) {
      return immersive ? const ImmersiveLyricsPage() : app;
    }

    // 两家官方页面都常驻在最底层（平时被应用界面盖住），顺序决定谁在最上面。
    // 要显示某一家时把那一家的 Stack 位置放到最后；注意不能卸载 WebView，
    // 否则音频会立刻停止。
    final order = ui.isShowing && ui.service == MusicService.spotify
        ? const [MusicService.netease, MusicService.spotify]
        : const [MusicService.spotify, MusicService.netease];

    final players = <Widget>[
      for (final service in order)
        if (handles[service] != null && engines[service] != null)
          Positioned.fill(
            child: HiddenWebPlayer(
              key: ValueKey('official-web-${service.name}'),
              target: webTargetFor(service) ?? neteaseWebTarget,
              handle: handles[service]!,
              onLoaded: () {},
            ),
          ),
    ];

    return Stack(
      children: [
        ...players,
        if (!ui.isShowing)
          Positioned.fill(
            child: immersive ? const ImmersiveLyricsPage() : app,
          ),
        if (ui.isShowing)
          _OfficialPageBar(service: ui.service, onClose: ui.close),
      ],
    );
  }
}

/// 官方页面顶部的一条轻量工具条（其余区域让给官方页面）。
class _OfficialPageBar extends StatelessWidget {
  const _OfficialPageBar({required this.service, required this.onClose});

  final MusicService service;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: Material(
        color: const Color(0xFF15151B),
        elevation: 4,
        child: SafeArea(
          bottom: false,
          child: Row(
            children: [
              const SizedBox(width: 12),
              const Icon(Icons.public, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${service.displayName} 官方页面：在这里登录/切歌，完成后点右侧按钮回到应用',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              TextButton(
                key: const Key('close-official-page'),
                onPressed: onClose,
                child: const Text('回到应用'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
