import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../domain/models.dart';
import 'album_art.dart';
import 'source_selector.dart';

String formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

class TrackResultTile extends StatelessWidget {
  const TrackResultTile({
    super.key,
    required this.track,
    required this.onTap,
    required this.onSelectSource,
    required this.onAddToQueue,
    this.imageBytes,
  });

  final Track track;
  final VoidCallback onTap;
  final ValueChanged<MusicService> onSelectSource;
  final VoidCallback onAddToQueue;
  final Uint8List? imageBytes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: Key('track-${track.id}'),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              AlbumArt(
                title: track.title,
                accentColor: track.accentColor,
                artworkUrl: track.artworkUrl,
                imageBytes: imageBytes,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${track.artist} · ${track.album} · ${formatDuration(track.duration)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    SourceSelector(track: track, onSelect: onSelectSource),
                  ],
                ),
              ),
              IconButton(
                tooltip: '加入队列',
                onPressed: onAddToQueue,
                icon: const Icon(Icons.playlist_add),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
