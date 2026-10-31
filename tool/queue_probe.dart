// 队列切歌探针：播放第一首 → 入队第二首 → next() → 校验实际曲目。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:music_client/application/music_controller.dart';
import 'package:music_client/application/playback_clock.dart';
import 'package:music_client/platform/official_handoff.dart';
import 'package:music_client/platform/secure_credentials.dart';
import 'package:music_client/platform/web_playback_engine.dart';
import 'package:music_client/platform/web_player_engine.dart';
import 'package:music_client/presentation/widgets/hidden_web_player.dart';
import 'package:music_client/providers/fake_netease_provider.dart';
import 'package:music_client/providers/fake_spotify_provider.dart';

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
  late final MusicController _controller = MusicController(
    providers: [FakeSpotifyProvider(), FakeNeteaseProvider()],
    clock: ManualClock(),
    credentials: InMemoryCredentials(),
    handoff: FakeHandoff(),
    webEngine: _engine,
  );
  bool _started = false;
  String _status = '加载中…';

  @override
  void dispose() {
    _controller.dispose();
    _engine.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final out = <String, Object?>{};
    _engine.start();
    try {
      await Future<void>.delayed(const Duration(seconds: 2));
      await _controller.searchFor('晴天');
      final results = _controller.search.results;
      out['count'] = results.length;
      if (results.length >= 2) {
        await _controller.selectTrack(results[0]);
        await Future<void>.delayed(const Duration(seconds: 5));
        out['firstTrack'] = results[0].title;
        out['firstNowPlaying'] = _engine.state.nowPlaying;
        out['firstPositionMs'] = _engine.state.position.inMilliseconds;

        // 入队第二首并通过 next() 切歌（走队列路径）
        _controller.enqueue(results[1]);
        await _controller.next();
        await Future<void>.delayed(const Duration(seconds: 5));
        out['secondTrack'] = results[1].title;
        out['secondNowPlaying'] = _engine.state.nowPlaying;
        out['secondQueueIndex'] = _controller.playback.queueIndex;
        out['secondPositionMs'] = _engine.state.position.inMilliseconds;
        await Future<void>.delayed(const Duration(seconds: 3));
        out['secondPositionLaterMs'] = _engine.state.position.inMilliseconds;
      }
    } catch (error) {
      out['error'] = '$error';
    }

    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}musicmerge_queue.json',
    );
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(out));
    setState(() => _status = '完成：${file.path}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('队列切歌探针')),
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
