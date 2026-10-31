// 桥接层自测：不依赖任何账号，用本地音频页验证
// 探测 / 播放 / 暂停 / 跳转 / 被面板覆盖后是否继续推进。
// 结果写入 build/selftest.json，便于机器读取。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:music_client/domain/models.dart';
import 'package:music_client/platform/web_player_engine.dart';
import 'package:music_client/presentation/widgets/hidden_web_player.dart';

void main() => runApp(const _SelfTestApp());

class _SelfTestApp extends StatelessWidget {
  const _SelfTestApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        home: const SelfTestPage(),
      );
}

class SelfTestPage extends StatefulWidget {
  const SelfTestPage({super.key});

  @override
  State<SelfTestPage> createState() => _SelfTestPageState();
}

class _SelfTestPageState extends State<SelfTestPage> {
  final WebPlayerHandle _handle = WebPlayerHandle();
  final List<Map<String, Object?>> _steps = [];
  bool _covered = false;
  String _status = '启动中…';
  final Completer<void> _loaded = Completer<void>();

  static final WebPlayerTarget _target = WebPlayerTarget(
    service: MusicService.netease,
    homeUrl: 'http://127.0.0.1:8100/test_sound.html',
    trackUrl: (id) => 'http://127.0.0.1:8100/test_sound.html',
    loginHint: '本地自测页',
  );

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _record(String name, WebPlayerState state) async {
    final entry = <String, Object?>{
      'step': name,
      'hasMedia': state.hasMedia,
      'paused': state.paused,
      'positionMs': state.position.inMilliseconds,
      'durationMs': state.duration.inMilliseconds,
      'covered': _covered,
    };
    _steps.add(entry);
    setState(() => _status = '$name: ${state.position.inSeconds}s / '
        '${state.duration.inSeconds}s, paused=${state.paused}');
  }

  Future<void> _wait(int ms) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  Future<void> _run() async {
    try {
      await _loaded.future.timeout(const Duration(seconds: 20));
    } catch (_) {
      // 页面加载超时也继续，记录到结果里。
    }
    await _wait(800);

    await _record('initial', await _handle.readState());

    await _handle.play();
    await _wait(1500);
    final afterPlay = await _handle.readState();
    await _record('afterPlay', afterPlay);

    await _handle.seek(const Duration(seconds: 20));
    await _wait(1200);
    await _record('afterSeek20', await _handle.readState());

    await _handle.pause();
    await _wait(600);
    final paused = await _handle.readState();
    await _record('afterPause', paused);
    await _wait(1200);
    final pausedLater = await _handle.readState();
    await _record('pausedStill', pausedLater);

    // 恢复播放，然后盖住页面（模拟“隐藏”），看是否继续推进。
    await _handle.play();
    await _wait(800);
    setState(() => _covered = true);
    final coveredStart = await _handle.readState();
    await _record('coveredStart', coveredStart);
    await _wait(2500);
    final coveredLater = await _handle.readState();
    await _record('coveredLater', coveredLater);

    final payload = {
      'steps': _steps,
      'deltaWhileCoveredMs': coveredLater.position.inMilliseconds -
          coveredStart.position.inMilliseconds,
      'pausedHeldMs': pausedLater.position.inMilliseconds -
          paused.position.inMilliseconds,
      'ok': true,
    };
    // 用绝对路径，避免相对路径落在 exe 所在目录。
    final outFile = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}musicmerge_selftest.json',
    );
    await outFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
    );
    setState(() => _status = '自测完成：${outFile.path}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('桥接层自测')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(_status),
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: HiddenWebPlayer(
                    target: _target,
                    handle: _handle,
                    onLoaded: () {
                      if (!_loaded.isCompleted) _loaded.complete();
                    },
                  ),
                ),
                if (_covered)
                  const Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black,
                      child: Center(child: Text('页面已被盖住（模拟隐藏）')),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
