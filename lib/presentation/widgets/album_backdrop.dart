import 'package:flutter/material.dart';

/// 沉浸模式背景：由专辑主色推导的深色渐变。
class AlbumBackdrop extends StatelessWidget {
  const AlbumBackdrop({super.key, this.accentColor});

  final int? accentColor;

  @override
  Widget build(BuildContext context) {
    final base = Color(accentColor ?? 0xFF2A2A33);
    final top = Color.lerp(const Color(0xFF0B0B0F), base, 0.35) ?? base;
    final middle = Color.lerp(const Color(0xFF0B0B0F), base, 0.18) ?? base;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [top, middle, const Color(0xFF08080B)],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
      child: const SizedBox.expand(),
    );
  }
}
