import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../application/music_controller.dart';
import 'connections_page.dart';
import 'immersive_lyrics_page.dart';
import 'player_page.dart';
import 'search_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

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

    final wide = MediaQuery.sizeOf(context).width >= 900;
    final pages = const <Widget>[
      SearchPage(),
      PlayerPage(),
      ConnectionsPage(),
    ];

    final body = IndexedStack(index: _index, children: pages);

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (value) => setState(() => _index = value),
              labelType: NavigationRailLabelType.all,
              destinations: _destinations,
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
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
  }
}
