// 自动切歌探针：播放《K歌之王》并跳到结尾，记录官方网页切到下一首时的真实状态。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:music_client/application/music_controller.dart';
import 'package:music_client/application/playback_clock.dart';
import 'package:music_client/domain/models.dart';
import 'package:music_client/platform/official_handoff.dart';
import 'package:music_client/platform/secure_credentials.dart';
import 'package:music_client/platform/web_playback_engine.dart';
import 'package:music_client/platform/web_player_engine.dart';
import 'package:music_client/presentation/widgets/hidden_web_player.dart';

void main() => runApp(const _App());

class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: const _ProbePage(),
  );
}

class _ProbePage extends StatefulWidget {
  const _ProbePage();

  @override
  State<_ProbePage> createState() => _ProbePageState();
}

class _ProbePageState extends State<_ProbePage> {
  final WebPlayerHandle _handle = WebPlayerHandle();
  late final WebPlaybackEngine _engine =
      WebPlaybackEngine(bridge: HandleWebPlayerBridge(_handle));
  late final MusicController _controller = MusicController(
    providers: const [],
    clock: ManualClock(),
    credentials: InMemoryCredentials(),
    handoff: FakeHandoff(),
    webEngine: _engine,
  );
  bool _started = false;
  String _status = '等待官方页面…';

  static const _domDiagnostics = r"""
  (function () {
    function text(node) {
      if (!node) { return ''; }
      return ((node.getAttribute && node.getAttribute('title')) ||
        node.textContent || '').trim().slice(0, 100);
    }
    var links = Array.from(document.querySelectorAll(
      '.m-playbar a[href*="song?id="], #g_player a[href*="song?id="]'
    )).slice(0, 8).map(function (node) {
      return { text: text(node), href: node.getAttribute('href') || '' };
    });
    var meta = navigator.mediaSession && navigator.mediaSession.metadata;
    var media = window.__dshPickMedia ? window.__dshPickMedia() : null;
    return JSON.stringify({
      pageTitle: document.title,
      location: location.href,
      links: links,
      playbar: text(document.querySelector('.m-playbar')),
      mediaSession: meta ? {
        title: meta.title || '',
        artist: meta.artist || '',
        album: meta.album || ''
      } : null,
      currentSrc: media ? (media.currentSrc || media.src || '') : '',
      readyState: media ? media.readyState : -1
    });
  })();
  """;

  static const _openQueue = r"""
  (function () {
    var nodes = Array.from(document.querySelectorAll('a,button,div,span'));
    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i];
      var label = [
        node.getAttribute('title') || '',
        node.getAttribute('aria-label') || '',
        node.textContent || ''
      ].join(' ');
      if (/播放列表|播放队列/.test(label)) {
        node.click();
        return JSON.stringify({
          clicked: true,
          tag: node.tagName,
          className: String(node.className || ''),
          label: label.trim().slice(0, 80)
        });
      }
    }
    return JSON.stringify({ clicked: false });
  })();
  """;

  static const _queueDom = r"""
  (function () {
    function compact(value) {
      return String(value || '').replace(/\s+/g, ' ').trim();
    }
    function info(node) {
      if (!node) { return null; }
      return {
        tag: node.tagName,
        id: node.id || '',
        className: compact(node.className).slice(0, 160),
        childCount: node.children.length,
        text: compact(node.textContent).slice(0, 200)
      };
    }
    var all = Array.from(document.querySelectorAll('*'));
    var header = all.find(function (node) {
      return /^播放列表\(\d+\)$/.test(compact(node.textContent));
    });
    var levels = [];
    var container = header;
    while (container) {
      levels.push({
        info: info(container),
        anchors: container.querySelectorAll('a').length,
        songAnchors: container.querySelectorAll('a[href*="song?id="]').length
      });
      container = container.parentElement;
    }
    container = header;
    while (container &&
      container.querySelectorAll('a[href*="song?id="]').length < 3) {
      container = container.parentElement;
    }
    var rows = container ? Array.from(
      container.querySelectorAll('a[href*="song?id="]')
    ).map(function (node) {
      var row = node.closest('li,div,tr');
      var match = /song\?id=(\d+)/.exec(node.getAttribute('href') || '');
      return {
        id: match ? match[1] : '',
        title: compact(node.getAttribute('title') || node.textContent),
        rowClass: row ? compact(row.className) : '',
        rowText: row ? compact(row.textContent).slice(0, 160) : ''
      };
    }) : [];
    return JSON.stringify({
      header: info(header),
      container: info(container),
      containerParent: info(container && container.parentElement),
      levels: levels,
      rowsByText: all.filter(function (node) {
        var value = compact(node.textContent);
        return value === '少女的祈祷' || value === '晴天(深情版)';
      }).slice(0, 20).map(info),
      rows: rows.slice(0, 30),
      playlistHtml: (
        document.querySelector('#g_playlist') || {innerHTML: ''}
      ).innerHTML.slice(0, 12000)
    });
  })();
  """;

  Track? _pick(List<Track> tracks, String title, String artist) {
    for (final track in tracks) {
      if (track.title.contains(title) && track.artist.contains(artist)) {
        return track;
      }
    }
    for (final track in tracks) {
      if (track.title.contains(title)) return track;
    }
    return tracks.isEmpty ? null : tracks.first;
  }

  Future<void> _run() async {
    final out = <String, Object?>{};
    final samples = <Map<String, Object?>>[];
    _engine.start();
    try {
      await Future<void>.delayed(const Duration(seconds: 2));
      await _controller.searchFor('K歌之王 陈奕迅');
      final firstTracks = _controller.search.results;
      final first = _pick(firstTracks, 'K歌之王', '陈奕迅');
      if (first == null) throw StateError('没有找到 K歌之王');

      await _controller.selectTrack(first);
      await Future<void>.delayed(const Duration(seconds: 3));
      final initialId = _engine.state.nowPlayingId;
      final initialSession = _engine.state.mediaSessionTitle;

      await _controller.searchFor('少女的祈祷 杨千嬅');
      final second = _pick(_controller.search.results, '少女的祈祷', '杨千嬅');

      final duration = _engine.state.duration;
      if (duration > const Duration(seconds: 5)) {
        await _controller.seekTo(duration - const Duration(seconds: 2));
      }

      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        final state = _engine.state;
        samples.add({
          'second': i,
          'appTrack': _controller.playback.current?.title ?? '',
          'queueIndex': _controller.playback.queueIndex,
          'status': _controller.playback.status.name,
          'positionMs': state.position.inMilliseconds,
          'durationMs': state.duration.inMilliseconds,
          'ended': state.ended,
          'paused': state.paused,
          'nowPlaying': state.nowPlaying,
          'nowPlayingId': state.nowPlayingId,
          'sessionTitle': state.mediaSessionTitle,
          'sessionArtist': state.mediaSessionArtist,
        });
        final changed =
            (initialId.isNotEmpty &&
                state.nowPlayingId.isNotEmpty &&
                state.nowPlayingId != initialId) ||
            (initialSession.isNotEmpty &&
                state.mediaSessionTitle.isNotEmpty &&
                state.mediaSessionTitle != initialSession);
        if (changed) {
          out['changed'] = true;
          out['dom'] = await _handle.probeJson(_domDiagnostics);
          out['queueClick'] = await _handle.probeJson(_openQueue);
          await Future<void>.delayed(const Duration(seconds: 1));
          out['queueDom'] = await _handle.probeJson(_queueDom);
          await _controller.refreshQueue();
          out['officialQueue'] = [
            for (final track in _controller.playback.queue) track.title,
          ];
          final kIndex = _controller.playback.queue.indexWhere(
            (track) => track.title.contains('K歌之王'),
          );
          if (kIndex >= 0) {
            await _controller.playAt(kIndex);
            await Future<void>.delayed(const Duration(seconds: 2));
            out['directQueueSwitch'] = {
              'appTrack': _controller.playback.current?.title,
              'queueIndex': _controller.playback.queueIndex,
              'nowPlayingId': _engine.state.nowPlayingId,
            };
          }
          break;
        }
      }
      out['first'] = first.title;
      out['secondFoundButNotQueued'] = second?.title;
      out['initialId'] = initialId;
      out['initialSession'] = initialSession;
      out['samples'] = samples;
    } catch (error) {
      out['error'] = '$error';
    }

    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}musicmerge_autonext.json',
    );
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(out));
    if (mounted) setState(() => _status = '完成：${file.path}');
  }

  @override
  void dispose() {
    _controller.dispose();
    _engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('自动切歌探针')),
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
              color: Colors.black87,
              padding: const EdgeInsets.all(12),
              child: Text(_status),
            ),
          ),
        ],
      ),
    );
  }
}
