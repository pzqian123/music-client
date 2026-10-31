/// 本地回环 OAuth 回调：桌面端官方推荐方式（http://127.0.0.1:PORT/callback）。
///
/// 不接收账号密码；只接收服务商重定向回来的授权码。
library;

import 'dart:async';
import 'dart:io';

class OAuthCallbackResult {
  final String? code;
  final String? state;
  final String? error;
  final String? errorDescription;

  const OAuthCallbackResult({
    this.code,
    this.state,
    this.error,
    this.errorDescription,
  });

  bool get isSuccess => code != null && error == null;
}

class OAuthException implements Exception {
  final String message;
  const OAuthException(this.message);
  @override
  String toString() => 'OAuthException($message)';
}

/// 打开授权页面的能力抽象（便于测试注入）。
typedef BrowserLauncher = Future<bool> Function(Uri authorizationUrl);

/// 在 [LocalOAuthServer.start] 之前告诉调用方回调地址。
class LocalOAuthServer {
  LocalOAuthServer._(this._server);

  final HttpServer _server;

  int get port => _server.port;

  Uri get redirectUri =>
      Uri.parse('http://127.0.0.1:${_server.port}/callback');

  static Future<LocalOAuthServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return LocalOAuthServer._(server);
  }

  /// 关闭监听端口（幂等）。
  Future<void> close() async {
    try {
      await _server.close(force: true);
    } catch (_) {
      // 已关闭则忽略。
    }
  }

  /// 等待一次回调；超时抛 [OAuthException]。
  Future<OAuthCallbackResult> waitForCallback({
    required String expectedState,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final completer = Completer<OAuthCallbackResult>();

    final subscription = _server.listen((request) async {
      final uri = request.uri;
      if (uri.path != '/callback') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      final params = uri.queryParameters;
      final result = OAuthCallbackResult(
        code: params['code'],
        state: params['state'],
        error: params['error'],
        errorDescription: params['error_description'],
      );

      request.response.headers.contentType = ContentType.html;
      request.response.write(
        result.isSuccess
            ? '<html><body style="font-family:sans-serif;background:#0b0b0f;color:#f5f5f7">'
                '<h2>授权成功</h2><p>可以关闭此标签页，回到音乐聚合。</p></body></html>'
            : '<html><body style="font-family:sans-serif;background:#0b0b0f;color:#f5f5f7">'
                '<h2>授权未完成</h2><p>${result.error ?? '未知错误'}</p></body></html>',
      );
      await request.response.close();

      if (!completer.isCompleted) {
        if (result.state != expectedState) {
          completer.complete(
            const OAuthCallbackResult(error: 'state_mismatch'),
          );
        } else {
          completer.complete(result);
        }
      }
    });

    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      throw const OAuthException('等待授权回调超时，请重试');
    } finally {
      await subscription.cancel();
      await _server.close(force: true);
    }
  }
}

/// 执行一次完整的「打开浏览器 → 等待回环回调」。
Future<OAuthCallbackResult> runLoopbackOAuth({
  required Uri authorizationUrl,
  required String expectedState,
  required BrowserLauncher launcher,
  Duration timeout = const Duration(minutes: 5),
}) async {
  final server = await LocalOAuthServer.start();
  try {
    final replaced = authorizationUrl.replace(
      queryParameters: {
        ...authorizationUrl.queryParameters,
        'redirect_uri': server.redirectUri.toString(),
      },
    );
    final opened = await launcher(replaced);
    if (!opened) {
      throw const OAuthException('无法打开系统浏览器，请检查默认浏览器设置');
    }
    return await server.waitForCallback(
      expectedState: expectedState,
      timeout: timeout,
    );
  } finally {
    // waitForCallback 内部已关闭；这里兜底防止异常路径泄漏端口。
    try {
      await server._server.close(force: true);
    } catch (_) {
      // 已关闭则忽略。
    }
  }
}
