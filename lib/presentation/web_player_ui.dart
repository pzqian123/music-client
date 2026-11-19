import 'package:flutter/foundation.dart';

import '../domain/models.dart';

/// 控制「把哪一家的官方页面显示出来」的 UI 状态。
///
/// 两家官方页面（网易云 / Spotify）都常驻在应用界面之下，所以搜索和歌词
/// 任何时刻都能同时用到；这里只决定"翻上来的是哪一家"，用于登录或手动切歌。
class WebPlayerUi extends ChangeNotifier {
  MusicService _service = MusicService.netease;
  bool _showing = false;

  /// 当前要显示的官方页面属于哪一家。
  MusicService get service => _service;

  /// 两家网页播放器都常驻挂载，这里恒为 true（保留旧接口语义）。
  bool get isMounted => true;

  /// 是否正在显示某一家官方页面。
  bool get isShowing => _showing;

  /// 显示指定服务的官方页面（首次就是登录页）。
  void open([MusicService? service]) {
    if (service != null) _service = service;
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
