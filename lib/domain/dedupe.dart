/// 保守的曲目标准化与重复合并。
///
/// 规则来自设计文档：只有「标准化标题相同 + 主艺人相同 + 版本标记完全一致
/// + 时长差 ≤ 8s」才合并；置信度 ≥ 0.8 才合并，否则保留为两条。
library;

import 'models.dart';

/// 版本标记词表（小写）。命中后既作为版本标记，也从标题中移除。
const Set<String> versionTokens = {
  'live',
  'remix',
  'remaster',
  'remastered',
  'acoustic',
  'instrumental',
  'cover',
  'karaoke',
  'demo',
  'edit',
  'extended',
  'sped up',
  'slowed',
  '现场',
  '翻唱',
  '伴奏',
  '混音',
  '重制',
  '版',
};

/// 合并后的结果。
class DedupeResult {
  final List<Track> tracks;

  /// Track.id -> 该曲目的合并置信度（0..1）。
  final Map<String, double> confidence;

  const DedupeResult({required this.tracks, required this.confidence});
}

/// 标准化后的标题拆解。
class TitleParts {
  final String base;
  final Set<String> markers;

  const TitleParts(this.base, this.markers);
}

/// 需要从标题/艺人中剔除的标点（含中英文引号与破折号）。
final RegExp _punctuation = RegExp(r'''[,\.\!\?\-\u2014/&'"“”‘’]''');

/// 全角 ASCII（U+FF01–FF5E）转半角。
String _toHalfWidth(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    if (rune >= 0xFF01 && rune <= 0xFF5E) {
      buffer.writeCharCode(rune - 0xFEE0);
    } else if (rune == 0x3000) {
      buffer.write(' ');
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

const List<String> _bracketPairs = ['()', '[]', '【】'];

/// 提取括号内的版本标记，返回清洗后的主体与标记集合。
TitleParts parseTitle(String raw) {
  var working = _toHalfWidth(raw).toLowerCase();
  final markers = <String>{};

  for (final pair in _bracketPairs) {
    final open = pair[0];
    final close = pair[1];
    var start = working.indexOf(open);
    while (start != -1) {
      final end = working.indexOf(close, start + 1);
      if (end == -1) break;
      final inner = working.substring(start + 1, end).trim();
      final marker = _markerOf(inner);
      if (marker != null) markers.add(marker);
      working = '${working.substring(0, start)} ${working.substring(end + 1)}';
      start = working.indexOf(open);
    }
  }

  working = working.replaceAll(_punctuation, ' ');
  final base = working.replaceAll(RegExp(r'\s+'), ' ').trim();

  // 标题尾部裸写的版本词，如「晴天 live」。
  for (final token in versionTokens) {
    if (_endsWithToken(base, token)) {
      markers.add(token);
      break;
    }
  }

  return TitleParts(base, markers);
}

bool _endsWithToken(String value, String token) {
  if (!value.endsWith(token)) return false;
  if (value.length == token.length) return true;
  final before = value[value.length - token.length - 1];
  return before == ' ' || before == '-' || before == '_';
}

String? _markerOf(String inner) {
  final normalized = inner.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) return null;
  if (versionTokens.contains(normalized)) return normalized;
  for (final token in versionTokens) {
    if (normalized.contains(token)) return token;
  }
  return null;
}

/// 标准化标题主体（不含版本标记）。
String normalizeTitle(String raw) => parseTitle(raw).base;

/// 标准化艺人：小写、去标点、压缩空格。
String normalizeArtist(String raw) {
  var working = _toHalfWidth(raw).toLowerCase();
  working = working.replaceAll(_punctuation, ' ');
  return working.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// 版本标记兼容判定：集合必须完全相等。
bool _markersCompatible(Set<String> a, Set<String> b) {
  if (a.length != b.length) return false;
  return a.containsAll(b);
}

double _confidenceFor(Duration a, Duration b) {
  final diff = (a - b).inMilliseconds.abs();
  if (diff <= 3000) return 0.95;
  if (diff <= 8000) return 0.85;
  return 0;
}

/// 合并两个服务的曲目列表。
DedupeResult mergeProviderTracks(List<ProviderTrack> tracks) {
  final groups = <String, List<ProviderTrack>>{};
  final keys = <ProviderTrack, String>{};
  final partsByTrack = <ProviderTrack, TitleParts>{};

  for (final track in tracks) {
    final parts = parseTitle(track.title);
    partsByTrack[track] = parts;
    final key = '${parts.base}|${normalizeArtist(track.artist)}';
    keys[track] = key;
    groups.putIfAbsent(key, () => []).add(track);
  }

  final result = <Track>[];
  final confidence = <String, double>{};
  final usedIds = <String>{};

  for (final entry in groups.entries) {
    final baseKey = entry.key;
    final group = entry.value;

    // 在组内按时长 + 版本标记聚类。
    final clusters = <List<ProviderTrack>>[];
    for (final track in group) {
      final markers = <String>{
        ...(partsByTrack[track]?.markers ?? const <String>{}),
        ...track.versionMarkers.map((e) => e.toLowerCase()),
      };
      var placed = false;
      for (final cluster in clusters) {
        final head = cluster.first;
        final headMarkers = <String>{
          ...(partsByTrack[head]?.markers ?? const <String>{}),
          ...head.versionMarkers.map((e) => e.toLowerCase()),
        };
        if (_markersCompatible(markers, headMarkers) &&
            _confidenceFor(track.duration, head.duration) >= 0.8) {
          cluster.add(track);
          placed = true;
          break;
        }
      }
      if (!placed) clusters.add(<ProviderTrack>[track]);
    }

    for (final cluster in clusters) {
      final head = cluster.first;
      final markers = <String>{
        ...(partsByTrack[head]?.markers ?? const <String>{}),
        ...head.versionMarkers.map((e) => e.toLowerCase()),
      };

      var minConfidence = 1.0;
      for (final other in cluster.skip(1)) {
        final score = _confidenceFor(head.duration, other.duration);
        if (score > 0 && score < minConfidence) minConfidence = score;
      }

      var longest = head.duration;
      String? artwork;
      int? accent;
      final sources = <TrackSource>[];
      for (final item in cluster) {
        if (item.duration > longest) longest = item.duration;
        artwork ??= item.artworkUrl;
        accent ??= item.accentColor;
        final source = TrackSource(
          service: item.service,
          providerTrackId: item.providerTrackId,
          playable: item.playable,
          officialHandoffUri: item.officialHandoffUri,
        );
        if (!sources.contains(source)) sources.add(source);
      }
      sources.sort((a, b) => a.service.index.compareTo(b.service.index));

      final markerSuffix =
          (markers.toList()..sort()).join('+');
      var id = markerSuffix.isEmpty ? baseKey : '$baseKey#$markerSuffix';
      var suffix = 1;
      while (usedIds.contains(id)) {
        id = '$baseKey#$markerSuffix~$suffix';
        suffix++;
      }
      usedIds.add(id);

      result.add(
        Track(
          id: id,
          title: cluster.length > 1 ? _displayTitle(cluster) : head.title,
          artist: head.artist,
          album: head.album,
          duration: longest,
          artworkUrl: artwork,
          accentColor: accent,
          versionMarkers: markers,
          sources: sources,
        ),
      );
      confidence[id] = minConfidence;
    }
  }

  result.sort((a, b) => a.title.compareTo(b.title));
  return DedupeResult(tracks: result, confidence: confidence);
}

/// 合并后展示用标题：优先取不带版本标记的最短标题。
String _displayTitle(List<ProviderTrack> cluster) {
  final sorted = List<ProviderTrack>.from(cluster)
    ..sort((a, b) => a.title.length.compareTo(b.title.length));
  return sorted.first.title;
}
