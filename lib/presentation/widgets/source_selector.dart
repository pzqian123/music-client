import 'package:flutter/material.dart';

import '../../domain/models.dart';

/// 一条结果的来源选择器：实心 = 可内播，描边 = 仅跳转官方 App。
class SourceSelector extends StatelessWidget {
  const SourceSelector({
    super.key,
    required this.track,
    required this.onSelect,
  });

  final Track track;
  final ValueChanged<MusicService> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final source in track.sources)
          ActionChip(
            key: Key('source-${track.id}-${source.service.name}'),
            avatar: Icon(
              source.playable ? Icons.play_arrow : Icons.open_in_new,
              size: 14,
            ),
            label: Text(
              source.service.displayName,
              style: theme.textTheme.labelSmall,
            ),
            backgroundColor: source.playable
                ? theme.colorScheme.primary.withValues(alpha: 0.18)
                : Colors.transparent,
            side: BorderSide(
              color: source.playable
                  ? theme.colorScheme.primary
                  : theme.dividerColor,
            ),
            visualDensity: VisualDensity.compact,
            onPressed: () => onSelect(source.service),
          ),
      ],
    );
  }
}
