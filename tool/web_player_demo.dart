// 隐藏式网页播放器 Demo：验证「官方页面登录 → 盖住页面 → 我们的 UI 控制」。
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
  bool _covered = false;
  WebPlayerState _state = const WebPlayerState.empty();
  String _url = '';

  String get _currentPath {
    if (_url.isEmpty) return '?';
    final parsed = Uri.tryParse(_url);
    return parsed?.path ?? _url;
  }
  Timer? _poll;
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  List<OfficialSearchResult> _results = const [];
  bool _searching = false;

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
    final url = await _handle.currentUrl();
    if (!mounted) return;
    setState(() {
      _state = state;
      _url = url;
    });
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty || _searching) return;
    setState(() => _searching = true);
    final results = await _handle.searchNetease(query);
    if (!mounted) return;
    setState(() {
      _results = results;
      _searching = false;
      _covered = false;
    });
  }

  Future<void> _playResult(OfficialSearchResult result) async {
    await _handle.openTrack(_target, result.id);
    await Future<void>.delayed(const Duration(milliseconds: 2600));
    await _handle.clickOfficialPlay();
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    await _refresh();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _idController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openTrack() async {
    final id = _idController.text.trim();
    if (id.isEmpty) return;
    await _handle.openTrack(_target, id);
  }

  String _fmt(Duration d) =>
      '${d.inMinutes}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('隐藏播放器 Demo'),
        actions: [
          TextButton.icon(
            onPressed: () => setState(() => _covered = !_covered),
            icon: Icon(_covered ? Icons.visibility : Icons.visibility_off),
            label: Text(_covered ? '显示官方页面' : '盖住官方页面'),
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
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: '在官方页面搜索（网易云）',
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _searching ? null : _search,
                  child: Text(_searching ? '搜索中…' : '官方搜索'),
                ),
              ],
            ),
          ),
          if (_results.isNotEmpty)
            SizedBox(
              height: 66,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: _results.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final result = _results[index];
                  return ActionChip(
                    label: Text(
                      '${result.title} · ${result.artist}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    onPressed: () => _playResult(result),
                  );
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _covered
                    ? '官方页面已被盖住——下面是我们自己的控件'
                    : _target.loginHint,
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Stack(
              children: [
                // 官方页面始终占满、尺寸不变；"隐藏"靠上面的不透明面板。
                Positioned.fill(
                  child: HiddenWebPlayer(
                    target: _target,
                    handle: _handle,
                    onLoaded: _refresh,
                  ),
                ),
                if (_covered)
                  Positioned.fill(
                    child: ColoredBox(
                      color: const Color(0xFF0B0B0F),
                      child: _OurPlayerPanel(
                        state: _state,
                        timeText:
                            '${_fmt(_state.position)} / ${_fmt(_state.duration)}',
                        onToggle: () => _handle.toggle(),
                        onSeek: (value) => _handle.seek(
                          Duration(
                            milliseconds:
                                (value * _state.duration.inMilliseconds).round(),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '诊断：媒体元素 ${_handle.lastMediaCount} 个 · '
                '${_state.hasMedia ? (_state.isPlaying ? "播放中" : "已暂停") : "未检测到播放"} · '
                '页面「${_state.pageTitle}」 · 路径 $_currentPath · '
                '页面播放栏：${_state.nowPlaying.isEmpty ? "空" : _state.nowPlaying}',
                style: const TextStyle(fontSize: 11, color: Colors.white38),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OurPlayerPanel extends StatelessWidget {
  const _OurPlayerPanel({
    required this.state,
    required this.timeText,
    required this.onToggle,
    required this.onSeek,
  });

  final WebPlayerState state;
  final String timeText;
  final VoidCallback onToggle;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.album, size: 96, color: Colors.white24),
        const SizedBox(height: 16),
        const Text('这是我们的播放界面', style: TextStyle(fontSize: 18)),
        const SizedBox(height: 8),
        Text(
          state.hasMedia ? '官方页面正在输出音频' : '官方页面尚无媒体元素',
          style: const TextStyle(fontSize: 12, color: Colors.white54),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: 420,
          child: Row(
            children: [
              IconButton(
                onPressed: onToggle,
                icon: Icon(state.isPlaying ? Icons.pause : Icons.play_arrow),
              ),
              Expanded(
                child: Slider(
                  value: state.progress,
                  onChanged: state.hasMedia ? onSeek : null,
                ),
              ),
              Text(timeText, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}
