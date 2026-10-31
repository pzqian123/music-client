/// 领域模型：只依赖 dart: 前缀，不 import Flutter。
library;

/// 音乐服务的标识。
enum MusicService {
  spotify('Spotify', 'spotify'),
  netease('网易云音乐', 'netease');

  const MusicService(this.displayName, this.storageKey);

  final String displayName;

  /// 用于凭证存储的稳定键，不要随 UI 文案变化。
  final String storageKey;
}

/// 服务连接的授权状态。
enum ProviderState {
  disconnected,
  connecting,
  connected,
  expired,
  error,
}

/// 服务能力：授权不等于拥有全部功能，必须逐项声明。
class ProviderCapabilities {
  final bool search;
  final bool metadata;
  final bool lyrics;
  final bool inAppPlayback;
  final bool officialHandoff;

  const ProviderCapabilities({
    required this.search,
    required this.metadata,
    required this.lyrics,
    required this.inAppPlayback,
    required this.officialHandoff,
  });

  static const none = ProviderCapabilities(
    search: false,
    metadata: false,
    lyrics: false,
    inAppPlayback: false,
    officialHandoff: false,
  );

  ProviderCapabilities copyWith({
    bool? search,
    bool? metadata,
    bool? lyrics,
    bool? inAppPlayback,
    bool? officialHandoff,
  }) {
    return ProviderCapabilities(
      search: search ?? this.search,
      metadata: metadata ?? this.metadata,
      lyrics: lyrics ?? this.lyrics,
      inAppPlayback: inAppPlayback ?? this.inAppPlayback,
      officialHandoff: officialHandoff ?? this.officialHandoff,
    );
  }

  @override
  String toString() =>
      'ProviderCapabilities(search: $search, metadata: $metadata, '
      'lyrics: $lyrics, inAppPlayback: $inAppPlayback, '
      'officialHandoff: $officialHandoff)';
}

/// 服务商返回的原始曲目，尚未合并、尚未标准化。
class ProviderTrack {
  final MusicService service;
  final String providerTrackId;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final String? artworkUrl;

  /// 0xAARRGGBB。为空时界面使用默认深色背景。
  final int? accentColor;

  /// 小写版本标记，如 {'live'}、{'remix'}、{'现场'}。
  final Set<String> versionMarkers;

  /// 跳转官方 App / 网页的地址，可为空。
  final Uri? officialHandoffUri;

  /// 该来源是否支持客户端内播放（仅描述能力，不代表当前账号一定可用）。
  final bool playable;

  const ProviderTrack({
    required this.service,
    required this.providerTrackId,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    this.artworkUrl,
    this.accentColor,
    this.versionMarkers = const {},
    this.officialHandoffUri,
    this.playable = false,
  });
}

/// 合并后曲目中的单个可用来源。
class TrackSource {
  final MusicService service;
  final String providerTrackId;
  final bool playable;
  final Uri? officialHandoffUri;

  const TrackSource({
    required this.service,
    required this.providerTrackId,
    required this.playable,
    this.officialHandoffUri,
  });

  @override
  bool operator ==(Object other) =>
      other is TrackSource &&
      other.service == service &&
      other.providerTrackId == providerTrackId;

  @override
  int get hashCode => Object.hash(service, providerTrackId);

  @override
  String toString() =>
      'TrackSource(${service.storageKey}:$providerTrackId, playable: $playable)';
}

/// 标准化后的曲目：一个曲目可以拥有多个服务来源。
class Track {
  /// 稳定标识；用于播放状态与列表 key，不应包含随机值。
  final String id;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final String? artworkUrl;
  final int? accentColor;
  final Set<String> versionMarkers;
  final List<TrackSource> sources;

  Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    this.artworkUrl,
    this.accentColor,
    this.versionMarkers = const {},
    List<TrackSource> sources = const [],
  }) : sources = List.unmodifiable(sources);

  TrackSource? sourceFor(MusicService service) {
    for (final source in sources) {
      if (source.service == service) return source;
    }
    return null;
  }

  /// 优先返回第一个可播放来源；全部不可播放时返回第一个来源；无来源时返回 null。
  TrackSource? get preferredSource {
    if (sources.isEmpty) return null;
    for (final source in sources) {
      if (source.playable) return source;
    }
    return sources.first;
  }

  bool get hasPlayableSource => sources.any((s) => s.playable);

  @override
  bool operator ==(Object other) => other is Track && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Track($id, $title - $artist, sources: ${sources.length})';
}
