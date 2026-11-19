/// 凭证存储键名：与 MusicService.storageKey 区分，用于存令牌 JSON。
library;

/// Spotify 令牌（JSON：access_token / refresh_token / expires_at / scope）。
const String spotifyTokenStorageKey = 'spotify.tokens';

/// Spotify 公共客户端 ID（不是 secret，可持久化）。
const String spotifyClientIdStorageKey = 'spotify.client_id';

/// 网易云令牌占位（未获官方资质前不会写入）。
const String neteaseTokenStorageKey = 'netease.tokens';

/// 隐藏网页播放器上次承载的服务（netease / spotify），下次启动直接恢复。
const String webServiceStorageKey = 'web.service';
