// 恢复性探针：先尝试受限曲目（应失败），再播放正常曲目（应成功）。
// 结果写入临时目录的 musicmerge_recovery.json。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:music_client/domain/models.dart';
import 'package:music_client/platform/web_playback_engine.dart';
import 'package:music_client/platform/web_player_engine.dart';
import 'package:music_client/presentation/widgets/hidden_web_player.dart';

void main() => runApp(const _App());

class _App extends StatelessWidget {
  const _App();

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
  late final WebPlaybackEngine _engine =
      WebPlaybackEngine(bridge: HandleWebPlayerBridge(_handle));
  bool _started = false;
  String _status = '加载中…';

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final out = <String, Object?>{};
    _engine.start();
    try {
      await Future<void>.delayed(const Duration(seconds: 2));

      // 0) 强制失败分支：不存在的曲目 id（官方页面会显示错误页，没有播放按钮）
      final bogus = Track(
        id: 'bogus',
        title: '不存在的曲目',
        artist: '',
        album: '',
        duration: Duration.zero,
        sources: const [
          TrackSource(
            service: MusicService.netease,
            providerTrackId: '999999999',
            playable: true,
          ),
        ],
      );
      out['bogusPlayed'] = await _engine.playTrack(bogus);
      out['bogusError'] = _engine.lastError;

      // 1) 受限曲目
      final restricted = await _engine.searchNetease('Blank Space');
      out['restrictedCount'] = restricted.length;
      if (restricted.isNotEmpty) {
        final ok = await _engine.playTrack(restricted.first);
        out['restrictedPlayed'] = ok;
        out['restrictedError'] = _engine.lastError;
      }

      // 2) 正常曲目（关键：失败后是否还能恢复）
      final normal = await _engine.searchNetease('晴天');
      out['normalCount'] = normal.length;
      if (normal.isNotEmpty) {
        final ok = await _engine.playTrack(normal.first);
        out['normalPlayed'] = ok;
        out['normalError'] = _engine.lastError;
        out['normalNowPlaying'] = _engine.state.nowPlaying;
        out['normalPositionMs'] = _engine.state.position.inMilliseconds;
        await Future<void>.delayed(const Duration(seconds: 3));
        out['normalPositionLaterMs'] = _engine.state.position.inMilliseconds;
      }
    } catch (error) {
      out['error'] = '$error';
    }

    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}musicmerge_recovery.json',
    );
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(out));
    setState(() => _status = '完成：${file.path}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('恢复性探针')),
      body: Stack(
        children: [
          Positioned.fill(
            child: HiddenWebPlayer(
              target: neteaseWebTarget,
              handle: _handle,
              onLoaded: () {
                if (_started) return;
                _started = true;
                _run();
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
              child: Text(_status, style: const TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }
}
