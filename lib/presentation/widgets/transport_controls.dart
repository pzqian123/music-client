import 'package:flutter/material.dart';

/// 播放控制条：上一首 / 播放暂停 / 下一首。
class TransportControls extends StatelessWidget {
  const TransportControls({
    super.key,
    required this.playing,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
    required this.hasPrevious,
    required this.hasNext,
    this.compact = false,
  });

  final bool playing;
  final VoidCallback onPlayPause;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final bool hasPrevious;
  final bool hasNext;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconSize = compact ? 28.0 : 32.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: const Key('transport-previous'),
          tooltip: '上一首',
          onPressed: hasPrevious ? onPrevious : null,
          iconSize: iconSize,
          icon: const Icon(Icons.skip_previous),
        ),
        const SizedBox(width: 4),
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            shape: BoxShape.circle,
          ),
          child: IconButton(
            key: const Key('transport-play-pause'),
            tooltip: playing ? '暂停' : '播放',
            onPressed: onPlayPause,
            iconSize: compact ? 30 : 34,
            color: theme.colorScheme.onPrimary,
            icon: Icon(playing ? Icons.pause : Icons.play_arrow),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          key: const Key('transport-next'),
          tooltip: '下一首',
          onPressed: hasNext ? onNext : null,
          iconSize: iconSize,
          icon: const Icon(Icons.skip_next),
        ),
      ],
    );
  }
}
