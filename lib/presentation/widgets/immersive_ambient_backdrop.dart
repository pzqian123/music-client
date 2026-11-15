import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 沉浸模式背景：模糊专辑封面 + 缓慢流动的主色氛围。
class ImmersiveAmbientBackdrop extends StatefulWidget {
  const ImmersiveAmbientBackdrop({
    super.key,
    this.accentColor,
    this.artworkBytes,
    required this.trackKey,
    this.animate = true,
  });

  final int? accentColor;
  final Uint8List? artworkBytes;
  final String trackKey;
  final bool animate;

  @override
  State<ImmersiveAmbientBackdrop> createState() =>
      _ImmersiveAmbientBackdropState();
}

class _ImmersiveAmbientBackdropState extends State<ImmersiveAmbientBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _drift = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 28),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!_reduceMotion && widget.animate) {
      if (!_drift.isAnimating) _drift.repeat(reverse: true);
    } else {
      _drift.stop();
      _drift.value = 0.25;
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Color(widget.accentColor ?? 0xFF2A2A33);
    final warm = Color.lerp(accent, const Color(0xFF9B7AFF), 0.35) ?? accent;
    final cool = Color.lerp(accent, const Color(0xFF38C6B5), 0.28) ?? accent;

    return RepaintBoundary(
      key: const Key('immersive-ambient-backdrop'),
      child: ColoredBox(
        color: const Color(0xFF060609),
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 700),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: widget.artworkBytes == null
                  ? const SizedBox.shrink()
                  : ClipRect(
                      key: ValueKey(widget.trackKey),
                      child: ImageFiltered(
                        imageFilter: ui.ImageFilter.blur(
                          sigmaX: 44,
                          sigmaY: 44,
                        ),
                        child: Transform.scale(
                          scale: 1.22,
                          child: Image.memory(
                            widget.artworkBytes!,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          ),
                        ),
                      ),
                    ),
            ),
            ColoredBox(color: Colors.black.withValues(alpha: 0.56)),
            AnimatedBuilder(
              animation: _drift,
              builder: (context, _) {
                final phase = _drift.value * math.pi * 2;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment(
                            -0.65 + math.sin(phase) * 0.18,
                            -0.55 + math.cos(phase * 0.7) * 0.12,
                          ),
                          radius: 1.05,
                          colors: [
                            warm.withValues(alpha: 0.5),
                            warm.withValues(alpha: 0.08),
                            Colors.transparent,
                          ],
                          stops: const [0, 0.42, 1],
                        ),
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment(
                            0.75 - math.cos(phase * 0.8) * 0.14,
                            0.65 + math.sin(phase * 0.6) * 0.2,
                          ),
                          radius: 0.9,
                          colors: [
                            cool.withValues(alpha: 0.34),
                            cool.withValues(alpha: 0.05),
                            Colors.transparent,
                          ],
                          stops: const [0, 0.5, 1],
                        ),
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.08),
                            Colors.black.withValues(alpha: 0.18),
                            Colors.black.withValues(alpha: 0.62),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
