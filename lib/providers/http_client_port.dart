/// 真实服务接入所需的 HTTP 抽象：测试注入假实现，生产注入真实实现。
library;

class HttpResponse {
  final int statusCode;
  final String body;

  const HttpResponse(this.statusCode, this.body);
}

typedef HttpFetcher = Future<HttpResponse> Function(
  Uri uri, {
  Map<String, String>? headers,
});

/// 默认拒绝访问网络：在未显式注入 fetcher 前，真实 Provider 不会悄悄联网。
Future<HttpResponse> disabledFetcher(
  Uri uri, {
  Map<String, String>? headers,
}) async {
  throw StateError('未配置 HTTP 客户端：真实服务接入需要在初始化时注入 fetcher');
}
