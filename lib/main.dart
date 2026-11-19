import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'platform/desktop_window_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  var showWindowControls = false;
  if (Platform.isWindows) {
    try {
      final window = WindowManager.instance.getCurrent();
      if (window == null) throw StateError('当前 Windows 窗口不可用');
      window
        ..title = '音乐聚合'
        ..minimumSize = const Size(820, 560).toNative()
        ..titleBarStyle = TitleBarStyle.hidden
        ..isWindowControlButtonsVisible = false
        ..setFrameless(true);
      window.setSize(const Size(1280, 720).toNative(), false);
      window.center();
      window.show();
      window.focus();
      showWindowControls = true;
    } catch (_) {
      // 初始化失败时保留系统原生标题栏，避免出现无法关闭的窗口。
      showWindowControls = false;
    }
  }

  runApp(
    MusicApp(
      windowService: const WindowManagerService(),
      showWindowControls: showWindowControls,
    ),
  );
}
