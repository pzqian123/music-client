import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/music_controller.dart';
import '../../domain/models.dart';
import 'album_art.dart';
import 'track_result_tile.dart';

/// 队列面板：宽屏用对话框，窄屏用底部弹窗。
Future<void> showQueueSheet(BuildContext context) {
  final wide = MediaQuery.sizeOf(context).width >= 900;
  if (wide) {
    return showDialog<void>(
      context: context,
      builder: (_) => const Dialog(
        child: SizedBox(width: 440, height: 520, child: QueuePanel()),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const SizedBox(height: 520, child: QueuePanel()),
  );
}

class QueuePanel extends StatelessWidget {
  const QueuePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final music = context.watch<MusicController>();
    final queue = music.playback.queue;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Text('播放队列', style: theme.textTheme.titleMedium),
              const Spacer(),
              Text('${queue.length} 首', style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: queue.isEmpty
              ? const Center(child: Text('队列是空的'))
              : ListView.builder(
                  itemCount: queue.length,
                  itemBuilder: (context, index) {
                    final track = queue[index];
                    final active = index == music.playback.queueIndex;
                    return ListTile(
                      key: Key('queue-item-$index'),
                      selected: active,
                      leading: AlbumArt(
                        title: track.title,
                        accentColor: track.accentColor,
                        artworkUrl: track.artworkUrl,
                        size: 40,
                        radius: 8,
                      ),
                      title: Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${track.artist} · ${formatDuration(track.duration)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: active
                          ? Icon(
                              Icons.volume_up,
                              color: theme.colorScheme.primary,
                              size: 18,
                            )
                          : null,
                      onTap: () => music.playAt(index),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// 队列里展示的服务来源标签（供播放页复用）。
String sourceSummary(Track track) {
  if (track.sources.isEmpty) return '无来源';
  return track.sources.map((s) => s.service.displayName).join(' / ');
}
