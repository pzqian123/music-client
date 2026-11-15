import 'dart:ui';

import 'package:flutter/material.dart';

import '../../application/music_controller.dart';
import 'track_result_tile.dart';
import 'transport_controls.dart';

/// 沉浸模式底部玻璃控制条。
class ImmersiveControls extends StatelessWidget {
  const ImmersiveControls({
    super.key,
    required this.music,
    required this.chromeVisible,
  });

  final MusicController music;
  final bool chromeVisible;

  @override
  Widget build(BuildContext context) {
    final playback = music.playback;
    final track = playback.current;
    if (track == null) return const SizedBox.shrink();
    final progress = track.duration.inMilliseconds <= 0
        ? 0.0
        : (playback.position.inMilliseconds / track.duration.inMilliseconds)
              .clamp(0.0, 1.0);

    return AnimatedOpacity(
      key: const Key('immersive-controls'),
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      opacity: chromeVisible ? 1 : 0.2,
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 14),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.065),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.11),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 3,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.12,
                              ),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white.withValues(alpha: 0.9),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Text(
                                formatDuration(playback.position),
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                              const Spacer(),
                              TransportControls(
                                playing: playback.isPlaying,
                                onPlayPause: music.togglePlayPause,
                                onPrevious: music.previous,
                                onNext: music.next,
                                hasPrevious:
                                    playback.hasPrevious ||
                                    playback.position > Duration.zero,
                                hasNext: playback.hasNext,
                                compact: true,
                              ),
                              const Spacer(),
                              Text(
                                formatDuration(track.duration),
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
