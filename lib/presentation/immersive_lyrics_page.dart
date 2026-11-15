import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../application/music_controller.dart';
import 'widgets/focus_lyrics_viewport.dart';
import 'widgets/immersive_ambient_backdrop.dart';
import 'widgets/immersive_controls.dart';
import 'widgets/track_result_tile.dart';

/// 全屏歌词：同一播放状态的另一种视图，不重置队列与进度。
class ImmersiveLyricsPage extends StatefulWidget {
  const ImmersiveLyricsPage({super.key});

  @override
  State<ImmersiveLyricsPage> createState() => _ImmersiveLyricsPageState();
}

class _ImmersiveLyricsPageState extends State<ImmersiveLyricsPage> {
  Timer? _hideChromeTimer;
  bool _chromeVisible = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleChromeHide();
  }

  void _showChrome() {
    if (!_chromeVisible) {
      setState(() => _chromeVisible = true);
    }
    _scheduleChromeHide();
  }

  void _scheduleChromeHide() {
    _hideChromeTimer?.cancel();
    final music = context.read<MusicController>();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion || !music.playback.isPlaying) {
      if (!_chromeVisible && mounted) {
        setState(() => _chromeVisible = true);
      }
      return;
    }
    _hideChromeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _chromeVisible = false);
    });
  }

  @override
  void dispose() {
    _hideChromeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final music = context.watch<MusicController>();
    final playback = music.playback;
    final track = playback.current;
    if (track == null) {
      return const Scaffold(body: SizedBox.shrink());
    }
    final theme = Theme.of(context);
    final coverBytes = music.coverBytesFor(track);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): music.toggleImmersive,
        const SingleActivator(LogicalKeyboardKey.space): () {
          _showChrome();
          unawaited(music.togglePlayPause());
        },
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
          _showChrome();
          unawaited(
            music.seekTo(playback.position - const Duration(seconds: 5)),
          );
        },
        const SingleActivator(LogicalKeyboardKey.arrowRight): () {
          _showChrome();
          unawaited(
            music.seekTo(playback.position + const Duration(seconds: 5)),
          );
        },
      },
      child: Focus(
        autofocus: true,
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) music.toggleImmersive();
          },
          child: Scaffold(
            key: const Key('immersive-lyrics'),
            backgroundColor: Colors.black,
            body: MouseRegion(
              onHover: (_) => _showChrome(),
              onEnter: (_) => _showChrome(),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _showChrome,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ImmersiveAmbientBackdrop(
                      accentColor: track.accentColor,
                      artworkBytes: coverBytes,
                      trackKey: track.id,
                    ),
                    SafeArea(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Column(
                            children: [
                              AnimatedOpacity(
                                duration: const Duration(milliseconds: 320),
                                opacity: _chromeVisible ? 1 : 0.2,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    8,
                                    16,
                                    0,
                                  ),
                                  child: Row(
                                    children: [
                                      IconButton(
                                        key: const Key('exit-immersive'),
                                        tooltip: '返回分栏视图',
                                        onPressed: music.toggleImmersive,
                                        icon: const Icon(
                                          Icons.keyboard_arrow_down,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              track.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.titleMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                    letterSpacing: -0.2,
                                                  ),
                                            ),
                                            Text(
                                              track.artist,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    color: Colors.white60,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${formatDuration(playback.position)} / '
                                        '${formatDuration(track.duration)}',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color: Colors.white60,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    0,
                                    12,
                                    104,
                                  ),
                                  child: FocusLyricsViewport(
                                    key: const Key('focus-lyrics-viewport'),
                                    timeline: music.lyrics,
                                    position: playback.position,
                                    onSeek: music.seekTo,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: ImmersiveControls(
                              music: music,
                              chromeVisible: _chromeVisible,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
