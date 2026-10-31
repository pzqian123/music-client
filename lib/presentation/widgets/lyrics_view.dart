import 'package:flutter/material.dart';

import '../../domain/lyrics.dart';

/// 同步歌词视图：逐字优先，逐行兜底，静态/无歌词都有明确状态。
class LyricsView extends StatefulWidget {
  const LyricsView({
    super.key,
    required this.timeline,
    required this.position,
    this.immersive = false,
  });

  final LyricTimeline? timeline;
  final Duration position;
  final bool immersive;

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  final ScrollController _scrollController = ScrollController();
  int _lastActiveIndex = -1;
  double _lineHeight = 56;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleScroll(int activeIndex) {
    if (activeIndex == _lastActiveIndex) return;
    _lastActiveIndex = activeIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final target = activeIndex * _lineHeight;
      final max = _scrollController.position.maxScrollExtent;
      final clamped = target.clamp(0.0, max <= 0 ? 0.0 : max);
      _scrollController.animateTo(
        clamped,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final timeline = widget.timeline;

    if (timeline == null || timeline.isEmpty) {
      return _Placeholder(
        key: const Key('lyrics-unavailable'),
        icon: Icons.lyrics_outlined,
        text: '暂无歌词',
      );
    }

    final mode = timeline.mode;
    if (mode == LyricSyncMode.static) {
      return _StaticLyrics(timeline: timeline, immersive: widget.immersive);
    }

    final activeIndex = timeline.activeLineAt(widget.position);
    _scheduleScroll(activeIndex);
    _lineHeight = widget.immersive ? 64 : 56;

    return LayoutBuilder(
      builder: (context, constraints) {
        final verticalPadding =
            ((constraints.maxHeight - _lineHeight) / 2).clamp(0.0, 4000.0);
        return ListView.builder(
          key: const Key('lyrics-list'),
          controller: _scrollController,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(vertical: verticalPadding),
          itemExtent: _lineHeight,
          itemCount: timeline.length,
          itemBuilder: (context, index) {
            final line = timeline.lines[index];
            final isActive = index == activeIndex;
            return AnimatedOpacity(
              key: Key('lyric-line-$index'),
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              opacity: isActive ? 1.0 : 0.45,
              child: Transform.scale(
                scale: isActive ? 1.0 : 0.94,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _LineText(
                      line: line,
                      active: isActive,
                      immersive: widget.immersive,
                      progresses: isActive && mode == LyricSyncMode.word
                          ? timeline.wordProgressesAt(index, widget.position)
                          : const [],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _LineText extends StatelessWidget {
  const _LineText({
    required this.line,
    required this.active,
    required this.immersive,
    required this.progresses,
  });

  final LyricLine line;
  final bool active;
  final bool immersive;
  final List<double> progresses;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeColor = theme.colorScheme.onSurface;
    final idleColor = theme.colorScheme.onSurfaceVariant;
    final fontSize = active ? (immersive ? 30.0 : 24.0) : (immersive ? 22.0 : 18.0);
    final baseStyle = TextStyle(
      fontSize: fontSize,
      height: 1.3,
      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
      color: active ? activeColor : idleColor,
    );

    if (active && progresses.isNotEmpty) {
      return Text.rich(
        TextSpan(
          children: [
            for (var i = 0; i < line.words.length; i++)
              TextSpan(
                text: line.words[i].text,
                style: baseStyle.copyWith(
                  color: Color.lerp(
                        idleColor,
                        activeColor,
                        i < progresses.length ? progresses[i] : 0,
                      ) ??
                      idleColor,
                ),
              ),
          ],
        ),
        textAlign: TextAlign.center,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      );
    }

    return Text(
      line.text,
      textAlign: TextAlign.center,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: baseStyle,
    );
  }
}

class _StaticLyrics extends StatelessWidget {
  const _StaticLyrics({required this.timeline, required this.immersive});

  final LyricTimeline timeline;
  final bool immersive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const Key('lyrics-static'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text('暂无时间戳歌词', style: theme.textTheme.labelMedium),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final line in timeline.lines)
                  Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: immersive ? 10 : 6,
                      horizontal: 16,
                    ),
                    child: Text(
                      line.text,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 10),
          Text(text, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
