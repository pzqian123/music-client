/// 官方 App / 官方网页跳转抽象。
library;

import 'package:url_launcher/url_launcher.dart';

abstract interface class OfficialHandoff {
  /// 返回是否成功发起跳转；失败时界面给出可理解提示。
  Future<bool> open(Uri uri);
}

class UrlLauncherHandoff implements OfficialHandoff {
  const UrlLauncherHandoff();

  @override
  Future<bool> open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}

/// 测试用实现：记录最后一次跳转地址。
class FakeHandoff implements OfficialHandoff {
  FakeHandoff({this.result = true});

  Uri? last;
  bool result;

  @override
  Future<bool> open(Uri uri) async {
    last = uri;
    return result;
  }
}
