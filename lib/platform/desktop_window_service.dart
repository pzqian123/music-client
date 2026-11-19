import 'package:window_manager/window_manager.dart';

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

  Window? get _window => WindowManager.instance.getCurrent();

  @override
  Future<void> minimize() async => _window?.minimize();

  @override
  Future<void> toggleMaximize() async {
    final window = _window;
    if (window == null) return;
    if (window.isMaximized) {
      window.unmaximize();
    } else {
      window.maximize();
    }
  }

  @override
  Future<void> close() async => _window?.close();

  @override
  Future<void> startDragging() async => _window?.startDragging();

  @override
  Future<bool> isMaximized() async => _window?.isMaximized ?? false;
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
