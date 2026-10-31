import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../application/music_controller.dart';
import '../domain/playback.dart';
import 'widgets/album_art.dart';
import 'widgets/lyrics_view.dart';
import 'widgets/queue_sheet.dart';
import 'widgets/track_result_tile.dart';
import 'widgets/transport_controls.dart';

class PlayerPage extends StatelessWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final music = context.watch<MusicController>();
    final playback = music.playback;
    final track = playback.current;

    if (track == null) {
      return const _EmptyPlayer();
    }

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final left = _LeftPanel(music: music, compact: !wide);
          final right = _LyricsPanel(music: music);

          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 38, child: left),
                const VerticalDivider(width: 1),
                Expanded(flex: 62, child: right),
              ],
            );
          }

          return Column(
            children: [
              left,
              const Divider(height: 1),
              Expanded(child: right),
            ],
          );
        },
      ),
    );
  }
}

class _EmptyPlayer extends StatelessWidget {
  const _EmptyPlayer();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      key: const Key('player-empty'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.album_outlined,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text('还没有播放任何歌曲', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text('去搜索页找一首歌开始吧', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _LeftPanel extends StatelessWidget {
  const _LeftPanel({required this.music, required this.compact});

  final MusicController music;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final playback = music.playback;
    final track = playback.current!;
    final blocked = playback.status == PlaybackStatus.blocked ||
        playback.status == PlaybackStatus.error;
    final handoff = music.officialHandoffOfCurrent();

    final cover = AlbumArt(
      title: track.title,
      accentColor: track.accentColor,
      artworkUrl: track.artworkUrl,
      imageBytes: music.coverBytesFor(track),
      size: compact ? 96 : 240,
      radius: compact ? 12 : 20,
    );

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          track.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: compact ? theme.textTheme.titleLarge : theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 4),
        Text(
          '${track.artist} · ${track.album}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 6),
        Text(
          sourceSummary(track),
          style: theme.textTheme.bodySmall,
        ),
      ],
    );

    final content = <Widget>[
      if (compact)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            cover,
            const SizedBox(width: 14),
            Expanded(child: titleBlock),
          ],
        )
      else ...[
        Center(child: cover),
        const SizedBox(height: 20),
        titleBlock,
      ],
      const SizedBox(height: 14),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final source in track.sources)
            ChoiceChip(
              key: Key('player-source-${source.service.name}'),
              label: Text(source.service.displayName),
              selected: playback.activeService == source.service,
              onSelected: (_) => music.switchSource(source.service),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
      if (blocked) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                playback.message ?? '暂时无法播放',
                key: const Key('playback-blocked-message'),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  if (handoff != null)
                    FilledButton.tonal(
                      key: const Key('open-official-app'),
                      onPressed: () => music.openOfficialApp(handoff),
                      child: const Text('打开官方 App'),
                    ),
                  OutlinedButton(
                    key: const Key('retry-playback'),
                    onPressed: music.togglePlayPause,
                    child: const Text('重试'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 16),
      _Progress(music: music),
      const SizedBox(height: 8),
      Center(
        child: TransportControls(
          playing: playback.isPlaying,
          onPlayPause: music.togglePlayPause,
          onPrevious: music.previous,
          onNext: music.next,
          hasPrevious: playback.queueIndex > 0 || playback.position > Duration.zero,
          hasNext: playback.hasNext,
          compact: compact,
        ),
      ),
      const SizedBox(height: 8),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton.icon(
            key: const Key('open-queue'),
            onPressed: () => showQueueSheet(context),
            icon: const Icon(Icons.queue_music, size: 18),
            label: const Text('队列'),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            key: const Key('enter-immersive'),
            onPressed: music.toggleImmersive,
            icon: const Icon(Icons.fullscreen, size: 18),
            label: const Text('沉浸模式'),
          ),
        ],
      ),
    ];

    return SingleChildScrollView(
      padding: EdgeInsets.all(compact ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: content,
      ),
    );
  }
}

class _Progress extends StatefulWidget {
  const _Progress({required this.music});

  final MusicController music;

  @override
  State<_Progress> createState() => _ProgressState();
}

class _ProgressState extends State<_Progress> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final playback = widget.music.playback;
    final duration = playback.current?.duration ?? Duration.zero;
    final live = duration.inMilliseconds <= 0
        ? 0.0
        : (playback.position.inMilliseconds / duration.inMilliseconds)
            .clamp(0.0, 1.0);
    final value = _dragValue ?? live;

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
          ),
          child: Slider(
            key: const Key('playback-progress'),
            value: value,
            onChanged: duration.inMilliseconds <= 0
                ? null
                : (next) => setState(() => _dragValue = next),
            onChangeEnd: duration.inMilliseconds <= 0
                ? null
                : (next) {
                    final target = Duration(
                      milliseconds:
                          (next * duration.inMilliseconds).round(),
                    );
                    setState(() => _dragValue = null);
                    widget.music.seekTo(target);
                  },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Text(
                formatDuration(_dragValue == null
                    ? playback.position
                    : Duration(
                        milliseconds:
                            (_dragValue! * duration.inMilliseconds).round(),
                      )),
                style: theme.textTheme.labelSmall,
              ),
              const Spacer(),
              Text(formatDuration(duration), style: theme.textTheme.labelSmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _LyricsPanel extends StatelessWidget {
  const _LyricsPanel({required this.music});

  final MusicController music;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: music.toggleImmersive,
      child: LyricsView(
        timeline: music.lyrics,
        position: music.playback.position,
      ),
    );
  }
}
