// 隐藏式网页播放器 Demo：验证「官方页面登录 → 隐藏 → 我们的 UI 控制」。
// 用法：flutter run -d windows -t tool/web_player_demo.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:music_client/domain/models.dart';
import 'package:music_client/platform/web_player_engine.dart';
import 'package:music_client/presentation/widgets/hidden_web_player.dart';

void main() => runApp(const _DemoApp());

class _DemoApp extends StatelessWidget {
  const _DemoApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        home: const DemoPage(),
      );
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  final WebPlayerHandle _handle = WebPlayerHandle();
  WebPlayerTarget _target = neteaseWebTarget;
  bool _visible = true;
  WebPlayerState _state = const WebPlayerState.empty();
  Timer? _poll;
  final TextEditingController _idController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(
      const Duration(milliseconds: 700),
      (_) => _refresh(),
    );
  }

  Future<void> _refresh() async {
    if (!_handle.isAttached) return;
    final state = await _handle.readState();
    if (!mounted) return;
    setState(() => _state = state);
  }

  @override
  void dispose() {
    _poll?.cancel();
    _idController.dispose();
    super.dispose();
  }

  Future<void> _openTrack() async {
    final id = _idController.text.trim();
    if (id.isEmpty) return;
    await _handle.openTrack(_target, id);
  }

  String _fmt(Duration d) =>
      '${d.inMinutes}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  String get _timeText => '${_fmt(_state.position)} / ${_fmt(_state.duration)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('隐藏播放器 Demo'),
        actions: [
          TextButton.icon(
            onPressed: () => setState(() => _visible = !_visible),
            icon: Icon(_visible ? Icons.visibility_off : Icons.visibility),
            label: Text(_visible ? '隐藏播放器' : '显示播放器'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                DropdownButton<MusicService>(
                  value: _target.service,
                  items: const [
                    DropdownMenuItem(
                      value: MusicService.netease,
                      child: Text('网易云网页版'),
                    ),
                    DropdownMenuItem(
                      value: MusicService.spotify,
                      child: Text('Spotify 网页版'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    final target = webTargetFor(value);
                    if (target == null) return;
                    setState(() => _target = target);
                    _handle.openHome(target);
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _idController,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: _target.service == MusicService.netease
                          ? '网易云歌曲 ID（如 347230）'
                          : 'Spotify Track ID',
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _openTrack(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _openTrack, child: const Text('打开曲目')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _target.loginHint,
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Stack(
              children: [
                if (!_visible)
                  const Center(
                    child: Text(
                      '播放器已隐藏——用下方控件控制官方页面播放',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                // 唯一的 WebView 实例：只改变位置与尺寸，不重建。
                Positioned(
                  left: 0,
                  top: 0,
                  right: _visible ? 0 : null,
                  bottom: _visible ? 0 : null,
                  width: _visible ? null : 2,
                  height: _visible ? null : 2,
                  child: HiddenWebPlayer(
                    target: _target,
                    handle: _handle,
                    visible: _visible,
                    onState: (state) => setState(() => _state = state),
                  ),
                ),
              ],
            ),
          ),
          if (!_visible) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => _handle.toggle(),
                        icon: Icon(
                          _state.isPlaying ? Icons.pause : Icons.play_arrow,
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          value: _state.progress,
                          onChanged: _state.hasMedia
                              ? (value) => _handle.seek(
                                    Duration(
                                      milliseconds:
                                          (value *
                                                  _state.duration
                                                      .inMilliseconds)
                                              .round(),
                                    ),
                                  )
                              : null,
                        ),
                      ),
                      Text(_timeText),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _state.hasMedia
                          ? (_state.isPlaying ? '官方页面：正在播放' : '官方页面：已暂停')
                          : '官方页面：未检测到媒体元素（需先登录并播放一首歌）',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
