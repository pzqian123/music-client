import 'package:window_manager/legacy.dart';

/// UI 与 Windows 窗口管理器之间的最小契约。
abstract interface class DesktopWindowService {
  Future<void> minimize();
  Future<void> toggleMaximize();
  Future<void> close();
  Future<void> startDragging();
  Future<bool> isMaximized();
}

class WindowManagerService implements DesktopWindowService {
  const WindowManagerService();

  @override
  Future<void> minimize() => windowManager.minimize();

  @override
  Future<void> toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Future<void> close() => windowManager.close();

  @override
  Future<void> startDragging() => windowManager.startDragging();

  @override
  Future<bool> isMaximized() => windowManager.isMaximized();
}

class FakeDesktopWindowService implements DesktopWindowService {
  FakeDesktopWindowService({this.maximized = false});

  bool maximized;
  final List<String> calls = [];

  @override
  Future<void> minimize() async => calls.add('minimize');

  @override
  Future<void> toggleMaximize() async {
    calls.add('toggleMaximize');
    maximized = !maximized;
  }

  @override
  Future<void> close() async => calls.add('close');

  @override
  Future<void> startDragging() async => calls.add('startDragging');

  @override
  Future<bool> isMaximized() async => maximized;
}
