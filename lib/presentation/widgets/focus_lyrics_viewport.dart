import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../domain/lyrics.dart';

/// 居中的焦点歌词视口：当前行带动相邻行，使用弹簧收敛而不是列表跳滚动。
class FocusLyricsViewport extends StatefulWidget {
  const FocusLyricsViewport({
    super.key,
    required this.timeline,
    required this.position,
    required this.onSeek,
    this.animate = true,
  });

  final LyricTimeline? timeline;
  final Duration position;
  final ValueChanged<Duration> onSeek;
  final bool animate;

  @override
  State<FocusLyricsViewport> createState() => _FocusLyricsViewportState();
}

class _FocusLyricsViewportState extends State<FocusLyricsViewport>
    with SingleTickerProviderStateMixin {
  late final AnimationController _focusController;
  int _activeIndex = -1;
  double _focusPosition = 0;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _focusController = AnimationController.unbounded(vsync: this)
      ..addListener(() {
        if (!mounted) return;
        setState(() => _focusPosition = _focusController.value);
      });
    _syncActive(animate: false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduced != _reduceMotion) {
      _reduceMotion = reduced;
      _syncActive(animate: false);
    }
  }

  @override
  void didUpdateWidget(covariant FocusLyricsViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.timeline != widget.timeline) {
      _activeIndex = -1;
      _syncActive(animate: false);
      return;
    }
    _syncActive(animate: widget.animate);
  }

  void _syncActive({required bool animate}) {
    final timeline = widget.timeline;
    if (timeline == null || timeline.isEmpty) return;
    final next = timeline.activeLineAt(widget.position);
    if (next < 0) return;
    if (_activeIndex < 0) {
      _activeIndex = next;
      _focusPosition = next.toDouble();
      _focusController.value = _focusPosition;
      return;
    }
    if (next == _activeIndex) return;
    _activeIndex = next;
    if (!animate || _reduceMotion) {
      _focusController.stop();
      _focusPosition = next.toDouble();
      _focusController.value = _focusPosition;
      return;
    }
    _focusController.stop();
    _focusController.value = _focusPosition;
    _focusController.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 260, damping: 28),
        _focusPosition,
        next.toDouble(),
        0,
      ),
    );
  }

  @override
  void dispose() {
    _focusController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timeline = widget.timeline;
    if (timeline == null || timeline.isEmpty) {
      return const _LyricsPlaceholder(
        key: Key('lyrics-unavailable'),
        icon: Icons.lyrics_outlined,
        text: '暂无歌词',
      );
    }
    if (timeline.mode == LyricSyncMode.static) {
      return _StaticFocusLyrics(timeline: timeline);
    }

    _syncActive(animate: widget.animate);
    return LayoutBuilder(
      builder: (context, constraints) {
        final short = constraints.maxHeight < 560;
        final lineExtent = short ? 66.0 : 76.0;
        final span = short ? 2 : 4;
        final center = constraints.maxHeight * 0.47;
        final activeLine = timeline.lines[_activeIndex];
        final nextLine = _activeIndex + 1 < timeline.lines.length
            ? timeline.lines[_activeIndex + 1]
            : null;
        final breathing =
            nextLine != null &&
            widget.position >= activeLine.end &&
            nextLine.start - widget.position >= const Duration(seconds: 4);

        return RepaintBoundary(
          child: ClipRect(
            child: Stack(
              key: const Key('focused-lyric-transition'),
              clipBehavior: Clip.none,
              children: [
                for (
                  var index = math.max(0, _activeIndex - span);
                  index <=
                      math.min(timeline.lines.length - 1, _activeIndex + span);
                  index++
                )
                  _buildLine(
                    context,
                    timeline,
                    index,
                    center,
                    lineExtent,
                    span,
                  ),
                if (breathing)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: center + lineExtent * 0.58,
                    child: const _BreathingDots(key: Key('lyrics-breathing')),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLine(
    BuildContext context,
    LyricTimeline timeline,
    int index,
    double center,
    double lineExtent,
    int span,
  ) {
    final line = timeline.lines[index];
    final distance = index - _focusPosition;
    final normalized = (distance.abs() / (span + 0.5)).clamp(0.0, 1.0);
    final active = index == _activeIndex;
    final scale = 1.0 - normalized * 0.18;
    final opacity = active ? 1.0 : (1.0 - normalized * 0.72).clamp(0.22, 0.9);
    final horizontal = distance > 0 ? 18.0 * normalized : 10.0 * normalized;
    final top = center + distance * lineExtent - lineExtent / 2;

    return Positioned(
      left: 0,
      right: 0,
      top: top,
      child: IgnorePointer(
        ignoring: normalized > 0.92,
        child: Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(horizontal, 0),
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.center,
              child: GestureDetector(
                key: active
                    ? Key('focused-lyric-line-$index')
                    : Key('lyric-line-$index'),
                behavior: HitTestBehavior.opaque,
                onTap: () => widget.onSeek(line.start),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 4,
                  ),
                  child: _FocusLineText(
                    line: line,
                    active: active,
                    progresses: active && timeline.mode == LyricSyncMode.word
                        ? timeline.wordProgressesAt(index, widget.position)
                        : const [],
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

class _FocusLineText extends StatelessWidget {
  const _FocusLineText({
    required this.line,
    required this.active,
    required this.progresses,
  });

  final LyricLine line;
  final bool active;
  final List<double> progresses;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = TextStyle(
      fontSize: active ? 30 : 21,
      height: 1.22,
      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
      letterSpacing: active ? -0.4 : 0,
      color: active ? Colors.white : Colors.white.withValues(alpha: 0.58),
    );
    if (!active || progresses.isEmpty) {
      return Text(
        line.text,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: base,
      );
    }

    return Text.rich(
      TextSpan(
        children: [
          for (var i = 0; i < line.words.length; i++)
            TextSpan(
              text: line.words[i].text,
              style: base.copyWith(
                color: Color.lerp(
                  theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
                  Colors.white,
                  i < progresses.length ? progresses[i] : 0,
                ),
                shadows: i < progresses.length && progresses[i] > 0.12
                    ? [
                        Shadow(
                          color: Colors.white.withValues(
                            alpha: 0.26 * progresses[i],
                          ),
                          blurRadius: 14 * progresses[i],
                        ),
                      ]
                    : null,
              ),
            ),
        ],
      ),
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _BreathingDots extends StatefulWidget {
  const _BreathingDots({super.key});

  @override
  State<_BreathingDots> createState() => _BreathingDotsState();
}

class _BreathingDotsState extends State<_BreathingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduced) {
      _controller.stop();
      _controller.value = 0.35;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Opacity(
                opacity:
                    0.2 +
                    0.55 *
                        (0.5 +
                            0.5 *
                                math.sin(
                                  (_controller.value * math.pi * 2) - i * 0.9,
                                )),
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox(width: 5, height: 5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StaticFocusLyrics extends StatelessWidget {
  const _StaticFocusLyrics({required this.timeline});

  final LyricTimeline timeline;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const Key('lyrics-static'),
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
      child: Column(
        children: [
          for (final line in timeline.lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Text(
                line.text,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.7),
                  height: 1.3,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LyricsPlaceholder extends StatelessWidget {
  const _LyricsPlaceholder({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 38, color: Colors.white38),
          const SizedBox(height: 10),
          Text(text, style: const TextStyle(color: Colors.white54)),
        ],
      ),
    );
  }
}
