/// 隐藏式网页播放引擎的领域模型与适配器（纯 Dart，可单测）。
library;

import '../domain/models.dart';

/// 从隐藏页面回读到的播放状态。
class WebPlayerState {
  final bool hasMedia;
  final bool paused;
  final bool ended;
  final Duration position;
  final Duration duration;
  final double volume;

  /// 页面标题，用于判断当前官方页面停在哪。
  final String pageTitle;

  /// 官方页面播放栏上的曲名（有则说明页面里确实在放某首歌）。
  final String nowPlaying;

  /// 官方播放栏或 Media Session 暴露的当前曲目 ID（网易云为数字歌曲 ID）。
  final String nowPlayingId;

  /// 浏览器 Media Session 元数据；页面自行切歌时通常比 DOM 更及时。
  final String mediaSessionTitle;
  final String mediaSessionArtist;
  final String mediaSessionAlbum;

  /// 状态来源：`element`（直接读媒体元素）或 `navbar`（从官方播放栏推断）。
  final String source;

  const WebPlayerState({
    required this.hasMedia,
    required this.paused,
    this.ended = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 1,
    this.pageTitle = '',
    this.nowPlaying = '',
    this.nowPlayingId = '',
    this.mediaSessionTitle = '',
    this.mediaSessionArtist = '',
    this.mediaSessionAlbum = '',
    this.source = '',
  });

  const WebPlayerState.empty()
      : hasMedia = false,
        paused = true,
        ended = false,
        position = Duration.zero,
        duration = Duration.zero,
        volume = 1,
        pageTitle = '',
        nowPlaying = '',
        nowPlayingId = '',
        mediaSessionTitle = '',
        mediaSessionArtist = '',
        mediaSessionAlbum = '',
        source = '';

  bool get isPlaying => hasMedia && !paused && !ended;

  double get progress {
    if (duration.inMilliseconds <= 0) return 0;
    final raw = position.inMilliseconds / duration.inMilliseconds;
    if (raw.isNaN || raw.isInfinite) return 0;
    return raw.clamp(0.0, 1.0);
  }

  static WebPlayerState fromJsonObject(Map<String, dynamic> json) {
    String asText(Object? value) => value is String ? value : '';
    if (json['hasMedia'] != true) {
      return WebPlayerState(
        hasMedia: false,
        paused: true,
        pageTitle: asText(json['pageTitle']),
        nowPlaying: asText(json['nowPlaying']),
        nowPlayingId: asText(json['nowPlayingId']),
        mediaSessionTitle: asText(json['mediaSessionTitle']),
        mediaSessionArtist: asText(json['mediaSessionArtist']),
        mediaSessionAlbum: asText(json['mediaSessionAlbum']),
      );
    }
    double asDouble(Object? value) =>
        value is num && value.isFinite ? value.toDouble() : 0;
    return WebPlayerState(
      hasMedia: true,
      paused: json['paused'] == true,
      ended: json['ended'] == true,
      position: Duration(milliseconds: (asDouble(json['position']) * 1000).round()),
      duration: Duration(milliseconds: (asDouble(json['duration']) * 1000).round()),
      volume: asDouble(json['volume']),
      pageTitle: asText(json['pageTitle']),
      nowPlaying: asText(json['nowPlaying']),
      nowPlayingId: asText(json['nowPlayingId']),
      mediaSessionTitle: asText(json['mediaSessionTitle']),
      mediaSessionArtist: asText(json['mediaSessionArtist']),
      mediaSessionAlbum: asText(json['mediaSessionAlbum']),
      source: asText(json['source']),
    );
  }
}

/// 各服务网页版的差异点：入口地址与曲目深链接。
class WebPlayerTarget {
  final MusicService service;

  /// 首次登录/浏览时的页面。
  final String homeUrl;

  /// 打开某首歌曲的深链接（页面内自行开始播放）。
  final String Function(String providerTrackId) trackUrl;

  /// 该页面是否需要用户先登录。
  final String loginHint;

  const WebPlayerTarget({
    required this.service,
    required this.homeUrl,
    required this.trackUrl,
    required this.loginHint,
  });
}

const WebPlayerTarget neteaseWebTarget = WebPlayerTarget(
  service: MusicService.netease,
  homeUrl: 'https://music.163.com',
  trackUrl: _neteaseTrackUrl,
  loginHint: '在打开的官方页面里用你自己的方式登录，登录完成后点「隐藏播放器」',
);

const WebPlayerTarget spotifyWebTarget = WebPlayerTarget(
  service: MusicService.spotify,
  homeUrl: 'https://open.spotify.com',
  trackUrl: _spotifyTrackUrl,
  loginHint: '在打开的官方页面里登录 Spotify（需要 Premium），完成后点「隐藏播放器」',
);

String _neteaseTrackUrl(String id) =>
    'https://music.163.com/#/song?id=${Uri.encodeComponent(id)}';

String _spotifyTrackUrl(String id) =>
    'https://open.spotify.com/track/${Uri.encodeComponent(id)}';

WebPlayerTarget? webTargetFor(MusicService service) {
  switch (service) {
    case MusicService.netease:
      return neteaseWebTarget;
    case MusicService.spotify:
      return spotifyWebTarget;
  }
}

/// 隐藏播放器的整体状态：哪家、是否就绪、当前是否在播。
class WebPlaybackSnapshot {
  final MusicService? service;
  final bool attached;
  final WebPlayerState state;
  final String? lastError;

  const WebPlaybackSnapshot({
    this.service,
    this.attached = false,
    this.state = const WebPlayerState.empty(),
    this.lastError,
  });

  WebPlaybackSnapshot copyWith({
    MusicService? service,
    bool? attached,
    WebPlayerState? state,
    String? lastError,
    bool clearError = false,
  }) {
    return WebPlaybackSnapshot(
      service: service ?? this.service,
      attached: attached ?? this.attached,
      state: state ?? this.state,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}
