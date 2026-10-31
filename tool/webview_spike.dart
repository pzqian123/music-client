// WebView 能力探针（仅用于技术验证，不进入产品入口）。
// 目的：确认 WebView2 是否支持 Widevine/PlayReady（决定 Spotify 网页版能否内嵌播放），
// 以及官方网页播放器能否正常加载。
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

const _probeScript = r"""
(function () {
  window.__probe = { status: 'running' };
  const configs = [{
    initDataTypes: ['cenc'],
    audioCapabilities: [
      { contentType: 'audio/mp4; codecs="mp4a.40.2"', robustness: 'SW_SECURE_CRYPTO' }
    ],
    videoCapabilities: [
      { contentType: 'video/mp4; codecs="avc1.42E01E"', robustness: 'SW_SECURE_CRYPTO' }
    ],
    distinctiveIdentifier: 'optional',
    persistentState: 'optional',
    sessionTypes: ['temporary']
  }];
  const names = ['com.widevine.alpha', 'com.microsoft.playready', 'org.w3.clearkey'];
  (async function () {
    const out = { userAgent: navigator.userAgent };
    for (const name of names) {
      try {
        const access = await navigator.requestMediaKeySystemAccess(name, configs);
        out[name] = 'OK:' + access.keySystem;
      } catch (e) {
        out[name] = 'FAIL:' + (e && e.name ? e.name : String(e));
      }
    }
    out.sep = '---';
    window.__probe = out;
  })();
})();
""";

const _mediaProbeScript = r"""
(function () {
  const els = Array.from(document.querySelectorAll('audio, video'));
  window.__media = {
    count: els.length,
    items: els.map(function (el) {
      return {
        tag: el.tagName,
        paused: el.paused,
        ready: el.readyState,
        duration: isFinite(el.duration) ? Math.round(el.duration) : null,
        currentTime: Math.round(el.currentTime || 0),
        src: el.currentSrc ? el.currentSrc.slice(0, 60) : ''
      };
    })
  };
})();
""";

void main() {
  runApp(const _SpikeApp());
}

class _SpikeApp extends StatelessWidget {
  const _SpikeApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const SpikePage(),
    );
  }
}

class SpikePage extends StatefulWidget {
  const SpikePage({super.key});

  @override
  State<SpikePage> createState() => _SpikePageState();
}

class _SpikePageState extends State<SpikePage> {
  InAppWebViewController? _controller;
  String _probe = '等待页面加载…';
  String _media = '（未探测）';
  String _currentUrl = '';
  final TextEditingController _urlController =
      TextEditingController(text: 'https://open.spotify.com');

  Future<void> _runProbe() async {
    final controller = _controller;
    if (controller == null) return;
    await controller.evaluateJavascript(source: _probeScript);
    await Future<void>.delayed(const Duration(seconds: 3));
    final result = await controller.evaluateJavascript(
      source: 'JSON.stringify(window.__probe || {status: "timeout"})',
    );
    if (!mounted) return;
    setState(() => _probe = '$result');
  }

  Future<void> _runMediaProbe() async {
    final controller = _controller;
    if (controller == null) return;
    await controller.evaluateJavascript(source: _mediaProbeScript);
    final result = await controller.evaluateJavascript(
      source: 'JSON.stringify(window.__media || {status: "none"})',
    );
    if (!mounted) return;
    setState(() => _media = '$result');
  }

  Future<void> _navigate(String url) async {
    _currentUrl = url;
    await _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WebView DRM 探针'),
        actions: [
          IconButton(
            tooltip: '重新探测 EME',
            onPressed: _runProbe,
            icon: const Icon(Icons.play_arrow),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: const Color(0xFF15151B),
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              '当前地址：$_currentUrl\n\nEME 探测结果：\n$_probe\n\n媒体元素探测：\n$_media',
              style: const TextStyle(fontSize: 12, height: 1.5),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      labelText: '加载地址',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => _navigate(_urlController.text),
                  child: const Text('打开'),
                ),
              ],
            ),
          ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest:
                  URLRequest(url: WebUri('https://music.163.com')),
              onWebViewCreated: (controller) => _controller = controller,
              onLoadStop: (controller, url) async {
                if (!mounted) return;
                setState(() => _currentUrl = url?.toString() ?? '');
                // EME 仅在安全上下文（https）可用，因此任何 https 页面都可以探测。
                if ((url?.toString() ?? '').startsWith('https:')) {
                  await _runProbe();
                  await Future<void>.delayed(const Duration(seconds: 2));
                  await _runMediaProbe();
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
