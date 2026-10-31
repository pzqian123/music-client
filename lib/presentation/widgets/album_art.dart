import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// 封面：无图时用主色 + 首字兜底，避免空白方块。
class AlbumArt extends StatelessWidget {
  const AlbumArt({
    super.key,
    required this.title,
    required this.accentColor,
    this.artworkUrl,
    this.imageBytes,
    this.size = 56,
    this.radius = 12,
  });

  final String title;
  final int? accentColor;
  final String? artworkUrl;

  /// 由官方页面抓到的图片字节（优先级高于网络地址）。
  final Uint8List? imageBytes;
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

    final bytes = imageBytes;
    if (bytes != null && bytes.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
          // 同一个字节实例复用缓存；切换曲目时保留上一帧，避免闪烁。
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => fallback,
        ),
      );
    }

    final url = artworkUrl;
    if (url == null || url.isEmpty) return fallback;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // 网易云图床会按 UA 拦截（Dart/Flutter 默认 UA 返回 403），必须伪装成浏览器。
        headers: _imageHeaders,
        // 加载中显示占位，失败时在角上给出明确标记，便于排查。
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
        errorBuilder: (_, error, _) {
          _logImageError(url, error);
          return Stack(
            children: [
              fallback,
              Positioned(
                right: 2,
                bottom: 2,
                child: Icon(
                  Icons.broken_image,
                  size: size * 0.28,
                  color: Colors.redAccent,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

const Map<String, String> _imageHeaders = {
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/156.0.0.0 Safari/537.36',
  'Referer': 'https://music.163.com/',
};

/// 把图片加载错误写到临时文件，便于在无控制台的桌面进程里排查。
void _logImageError(String url, Object error) {
  try {
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}musicmerge_image_error.txt',
    );
    file.writeAsStringSync('$url\n$error\n', mode: FileMode.append);
  } catch (_) {
    // 记录失败不影响界面。
  }
}
