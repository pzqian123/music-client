/// 凭证存储键名：与 MusicService.storageKey 区分，用于存令牌 JSON。
library;

/// Spotify 令牌（JSON：access_token / refresh_token / expires_at / scope）。
const String spotifyTokenStorageKey = 'spotify.tokens';

/// 网易云令牌占位（未获官方资质前不会写入）。
const String neteaseTokenStorageKey = 'netease.tokens';
