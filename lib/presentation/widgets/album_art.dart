import 'package:flutter/material.dart';

/// 封面：无图时用主色 + 首字兜底，避免空白方块。
class AlbumArt extends StatelessWidget {
  const AlbumArt({
    super.key,
    required this.title,
    required this.accentColor,
    this.artworkUrl,
    this.size = 56,
    this.radius = 12,
  });

  final String title;
  final int? accentColor;
  final String? artworkUrl;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final color = Color(accentColor ?? 0xFF2A2A33);
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(color, Colors.white, 0.16) ?? color,
            color,
          ],
        ),
      ),
      child: Text(
        title.isEmpty ? '♪' : String.fromCharCode(title.runes.first),
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.9),
          fontSize: size * 0.34,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    final url = artworkUrl;
    if (url == null || url.isEmpty) return fallback;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}
