import 'package:flutter/foundation.dart';

/// 控制「是否把官方页面显示出来」的 UI 状态。
///
/// 默认不显示：官方页面在应用界面之下持续存在，用户只在登录时才翻上来。
class WebPlayerUi extends ChangeNotifier {
  bool _mounted = false;
  bool _showing = false;

  /// 是否已经把 WebView 挂进组件树。挂上后不再销毁，否则登录态会丢。
  bool get isMounted => _mounted;

  /// 是否正在显示官方页面（登录/切换服务时）。
  bool get isShowing => _showing;

  /// 显示官方页面（首次调用会挂载 WebView）。
  void open() {
    _mounted = true;
    _showing = true;
    notifyListeners();
  }

  /// 收起官方页面，回到我们自己的界面。
  void close() {
    if (!_showing) return;
    _showing = false;
    notifyListeners();
  }

  void toggle() => _showing ? close() : open();
}
