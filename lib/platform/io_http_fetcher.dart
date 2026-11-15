/// 桌面端与 Android 共用的真实 HTTP 实现。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../providers/http_client_port.dart';

const Duration _requestTimeout = Duration(seconds: 20);

/// 使用 `dart:io` 的轻量 fetcher：不引入额外依赖，也不会记录请求头或令牌。
Future<HttpResponse> fetchWithIo(
  Uri uri, {
  Map<String, String>? headers,
  String? body,
  String? contentType,
}) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..idleTimeout = const Duration(seconds: 5);
  try {
    final request = await client
        .openUrl(body == null ? 'GET' : 'POST', uri)
        .timeout(_requestTimeout);
    headers?.forEach(request.headers.set);
    request.followRedirects = true;
    request.maxRedirects = 5;
    if (contentType != null) {
      request.headers.set(HttpHeaders.contentTypeHeader, contentType);
    }
    if (body != null) {
      request.write(body);
    }

    final response = await request.close().timeout(_requestTimeout);
    final responseBody = await utf8.decoder
        .bind(response)
        .join()
        .timeout(_requestTimeout);
    return HttpResponse(response.statusCode, responseBody);
  } finally {
    client.close(force: true);
  }
}
