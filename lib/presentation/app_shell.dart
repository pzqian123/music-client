import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../application/music_controller.dart';
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

  @override
  void initState() {
    super.initState();
    if (_autoSearch.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        // 等官方页面就绪后再搜索。
        await Future<void>.delayed(const Duration(seconds: 6));
        if (!mounted) return;
        await context.read<MusicController>().searchFor(_autoSearch);
        if (!mounted) return;
        // 验证模式下自动收起官方页面，确认结果渲染在我们自己的界面里。
        context.read<WebPlayerUi>().close();
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

    if (viewMode == ViewMode.immersive && hasTrack) {
      return const ImmersiveLyricsPage();
    }

    final ui = context.watch<WebPlayerUi>();
    final handle = context.read<WebPlayerHandle?>();

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

    if (handle == null) return app;

    // 官方页面永远在最底层：平时被应用界面盖住，登录时才翻到最上面。
    return Stack(
      children: [
        if (ui.isMounted)
          Positioned.fill(
            child: HiddenWebPlayer(
              target: neteaseWebTarget,
              handle: handle,
              onLoaded: () {},
            ),
          ),
        if (!ui.isShowing) Positioned.fill(child: app),
        if (ui.isShowing) _OfficialPageBar(onClose: ui.close),
      ],
    );
  }
}

/// 官方页面顶部的一条轻量工具条（其余区域让给官方页面）。
class _OfficialPageBar extends StatelessWidget {
  const _OfficialPageBar({required this.onClose});

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
              const Expanded(
                child: Text(
                  '官方页面：在这里登录/切歌，完成后点右侧按钮回到应用',
                  style: TextStyle(fontSize: 12),
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
