import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../platform/web_player_engine.dart';
import '../../platform/web_player_scripts.dart';

/// 控制隐藏播放器的句柄：由页面创建，交给 [HiddenWebPlayer] 绑定。
class WebPlayerHandle {
  InAppWebViewController? _controller;

  bool get isAttached => _controller != null;

  void attach(InAppWebViewController controller) => _controller = controller;

  Future<String?> _js(String source) async {
    final controller = _controller;
    if (controller == null) return null;
    final result = await controller.evaluateJavascript(source: source);
    return result?.toString();
  }

  Future<void> openHome(WebPlayerTarget target) async {
    await _controller?.loadUrl(
      urlRequest: URLRequest(url: WebUri(target.homeUrl)),
    );
  }

  Future<void> openTrack(WebPlayerTarget target, String providerTrackId) async {
    await _controller?.loadUrl(
      urlRequest: URLRequest(url: WebUri(target.trackUrl(providerTrackId))),
    );
  }

  Future<void> loadUrl(String url) async {
    await _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  Future<WebPlayerState> readState() async {
    final raw = await _js(mediaStateScript);
    return decodeState(raw);
  }

  Future<void> toggle() async {
    await _js(mediaToggleScript);
  }

  Future<void> play() async {
    await _js(mediaPlayScript);
  }

  Future<void> pause() async {
    await _js(mediaPauseScript);
  }

  Future<void> seek(Duration position) async {
    await _js(mediaSeekScript(position.inMilliseconds / 1000));
  }

  Future<void> setVolume(double volume) async {
    await _js(mediaVolumeScript(volume));
  }
}

/// 把 JS 返回的 JSON 字符串解析为状态；解析失败返回空状态。
WebPlayerState decodeState(String? raw) {
  if (raw == null || raw.isEmpty) return const WebPlayerState.empty();
  final trimmed = raw.trim();
  if (!trimmed.startsWith('{')) return const WebPlayerState.empty();
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map<String, dynamic>) return const WebPlayerState.empty();
    return WebPlayerState.fromJsonObject(decoded);
  } catch (_) {
    return const WebPlayerState.empty();
  }
}

class HiddenWebPlayer extends StatefulWidget {
  const HiddenWebPlayer({
    super.key,
    required this.target,
    required this.handle,
    required this.visible,
    this.onLoaded,
    this.onState,
  });

  final WebPlayerTarget target;
  final WebPlayerHandle handle;
  final bool visible;
  final VoidCallback? onLoaded;
  final ValueChanged<WebPlayerState>? onState;

  @override
  State<HiddenWebPlayer> createState() => _HiddenWebPlayerState();
}

class _HiddenWebPlayerState extends State<HiddenWebPlayer> {
  @override
  Widget build(BuildContext context) {
    final webview = InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(widget.target.homeUrl)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        transparentBackground: true,
        allowFileAccess: false,
        useShouldOverrideUrlLoading: false,
        isInspectable: false,
      ),
      onWebViewCreated: (controller) {
        widget.handle.attach(controller);
      },
      onLoadStop: (controller, url) {
        widget.onLoaded?.call();
      },
    );

    // 关键：无论显示还是隐藏都保持同一棵组件树，只改变不透明度，
    // 否则 InAppWebView 会被销毁——登录态和正在播放的音频都会丢。
    return Opacity(
      opacity: widget.visible ? 1 : 0,
      child: IgnorePointer(ignoring: !widget.visible, child: webview),
    );
  }
}
