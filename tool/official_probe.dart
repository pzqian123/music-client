// 官方页面能力自测：搜索解析 + 播放/暂停/拖动是否真的生效。
// 结果写入临时目录的 musicmerge_probe.json，便于机器读取。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:music_client/platform/web_player_engine.dart';
import 'package:music_client/platform/web_player_scripts.dart';
import 'package:music_client/presentation/widgets/hidden_web_player.dart';

void main() => runApp(const _ProbeApp());

class _ProbeApp extends StatelessWidget {
  const _ProbeApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        home: const ProbePage(),
      );
}

class ProbePage extends StatefulWidget {
  const ProbePage({super.key});

  @override
  State<ProbePage> createState() => _ProbePageState();
}

class _ProbePageState extends State<ProbePage> {
  final WebPlayerHandle _handle = WebPlayerHandle();
  final List<String> _log = [];
  bool _loaded = false;
  String _status = '加载中…';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('官方页面探针')),
      body: Stack(
        children: [
          Positioned.fill(
            child: HiddenWebPlayer(
              target: neteaseWebTarget,
              handle: _handle,
              onLoaded: () {
                if (!_loaded) {
                  _loaded = true;
                  _run();
                }
              },
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: Colors.black.withValues(alpha: 0.85),
              padding: const EdgeInsets.all(12),
              child: Text(
                _status,
                style: const TextStyle(fontSize: 12, height: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

  Future<void> _run() async {
    final out = <String, Object?>{};
    try {
      await _wait(1500);
      out['initial'] = await _handle.probeJson(mediaStateScript);

      // 1) 搜索解析
      await _handle.runScript(neteaseSearchScript('晴天'));
      await _wait(7000);
      out['searchDebug'] = await _handle.probeJson(neteaseSearchDebugScript);
      out['search'] = await _handle.probeJson(neteaseParseSearchScript);
      setState(() => _status = '搜索完成，结果已记录');

      // 搜索页上直接取封面（验证与播放无关的路径）
      const probeIds = ['2652820720', '2668397359', '3439604863'];
      await _handle.runScript(neteaseCoverFetchScript(probeIds));
      await _wait(1800);
      final coverRaw = await _handle.probeJson(neteaseCoverReadScript);
      out['coverRaw'] =
          coverRaw.length > 500 ? '${coverRaw.substring(0, 500)}…' : coverRaw;

      // 2) 播放控制：取第一条结果的 id，打开并播放
      final searchRaw = out['search'] as String? ?? '{}';
      final decoded = jsonDecode(searchRaw);
      String trackId = '';
      if (decoded is Map<String, dynamic>) {
        final items = decoded['items'];
        if (items is List && items.isNotEmpty) {
          final first = items.first;
          if (first is Map<String, dynamic>) {
            trackId = (first['id'] as String?) ?? '';
          }
        }
      }
      out['pickedId'] = trackId;
      if (trackId.isNotEmpty) {
        await _handle.openTrack(neteaseWebTarget, trackId);
        await _wait(5000);
        out['afterOpen'] = await _handle.probeJson(mediaStateScript);
        out['songPageButtons'] =
            await _handle.probeJson(neteaseSongPageButtonsScript);

        // 点官方播放按钮真正起播
        out['clickPlay'] = await _handle.runScript(neteaseClickPlayScript);
        await _wait(4000);
        out['afterClick'] = await _handle.probeJson(mediaStateScript);

        // 3) 暂停
        await _handle.pause();
        await _wait(1200);
        out['afterPause'] = await _handle.probeJson(mediaStateScript);

        // 4) 恢复 + 跳转 10 秒
        await _handle.play();
        await _wait(800);
        await _handle.seek(const Duration(seconds: 10));
        await _wait(1200);
        out['afterSeek10'] = await _handle.probeJson(mediaStateScript);

        // 5) 歌词
        await _handle.runScript(neteaseLyricFetchScript(trackId));
        await _wait(1500);
        final lyricRaw = await _handle.probeJson(neteaseLyricReadScript);
        out['lyricStatus'] = lyricRaw.length > 400
            ? '${lyricRaw.substring(0, 400)}…'
            : lyricRaw;

        // 6) 封面
        await _handle.runScript(neteaseCoverFetchScript([trackId]));
        await _wait(1500);
        final coverRaw = await _handle.probeJson(neteaseCoverReadScript);
        out['coverRaw'] = coverRaw.length > 500
            ? '${coverRaw.substring(0, 500)}…'
            : coverRaw;
      }
    } catch (error) {
      out['error'] = '$error';
    }

    out['log'] = _log;
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}musicmerge_probe.json',
    );
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(out));
    setState(() => _status = '完成：${file.path}');
  }
}
