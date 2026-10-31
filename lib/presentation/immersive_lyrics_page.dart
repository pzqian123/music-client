import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../application/music_controller.dart';
import 'widgets/album_backdrop.dart';
import 'widgets/lyrics_view.dart';
import 'widgets/track_result_tile.dart';
import 'widgets/transport_controls.dart';

/// 全屏歌词：同一播放状态的另一种视图，不重置队列与进度。
class ImmersiveLyricsPage extends StatelessWidget {
  const ImmersiveLyricsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final music = context.watch<MusicController>();
    final playback = music.playback;
    final track = playback.current;

    if (track == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    final theme = Theme.of(context);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): music.toggleImmersive,
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
            body: Stack(
              children: [
                Positioned.fill(
                  child: AlbumBackdrop(accentColor: track.accentColor),
                ),
                SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 16, 0),
                        child: Row(
                          children: [
                            IconButton(
                              key: const Key('exit-immersive'),
                              tooltip: '返回分栏视图',
                              onPressed: music.toggleImmersive,
                              icon: const Icon(Icons.keyboard_arrow_down),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    track.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  Text(
                                    track.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${formatDuration(playback.position)} / '
                              '${formatDuration(track.duration)}',
                              style: theme.textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: LyricsView(
                          timeline: music.lyrics,
                          position: playback.position,
                          immersive: true,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                        child: Column(
                          children: [
                            LinearProgressIndicator(
                              value: track.duration.inMilliseconds == 0
                                  ? 0
                                  : (playback.position.inMilliseconds /
                                          track.duration.inMilliseconds)
                                      .clamp(0.0, 1.0),
                              minHeight: 2,
                            ),
                            const SizedBox(height: 6),
                            TransportControls(
                              playing: playback.isPlaying,
                              onPlayPause: music.togglePlayPause,
                              onPrevious: music.previous,
                              onNext: music.next,
                              hasPrevious: playback.queueIndex > 0,
                              hasNext: playback.hasNext,
                              compact: true,
                            ),
                          ],
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
    );
  }
}
