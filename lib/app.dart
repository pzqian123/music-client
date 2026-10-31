import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'application/music_controller.dart';
import 'presentation/app_shell.dart';
import 'providers/music_provider.dart';
import 'providers/fake_netease_provider.dart';
import 'providers/fake_spotify_provider.dart';

/// 演示默认 Provider 集合。
List<MusicProvider> buildDemoProviders() => [
      FakeSpotifyProvider(),
      FakeNeteaseProvider(),
    ];

class MusicApp extends StatelessWidget {
  const MusicApp({super.key, this.controller});

  /// 测试时可注入已构造的控制器。
  final MusicController? controller;

  @override
  Widget build(BuildContext context) {
    final injected = controller;
    final shell = MaterialApp(
      title: '音乐聚合',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const AppShell(),
    );
    if (injected != null) {
      return ChangeNotifierProvider<MusicController>.value(
        value: injected,
        child: shell,
      );
    }
    return ChangeNotifierProvider<MusicController>(
      create: (_) => MusicController(providers: buildDemoProviders()),
      child: shell,
    );
  }
}

ThemeData buildTheme() {
  const background = Color(0xFF0B0B0F);
  const surface = Color(0xFF15151B);
  const outline = Color(0xFF2A2A33);

  final scheme = ColorScheme.fromSeed(
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
