# 真实服务接入边界

本文件记录 Spotify 与网易云音乐的官方能力边界，以及本项目**允许**与**禁止**的实现方式。
当前代码已接入 Spotify PKCE 搜索与网易云官方网页播放器；未获网易云开放平台资质前，
不会调用任何非官方私有接口。

## 通用规则

- 只使用官方公开文档记录的接口与 OAuth 流程，不在客户端收集账号密码。
- 不绕过 Premium / VIP、DRM、地区限制；不提取私有音频地址；不伪造播放成功。
- client secret 只放环境变量或本地未跟踪文件，绝不提交，也不写入日志。
- 所有网络错误映射到领域状态：`network` / `unauthorized` / `forbidden` / `rateLimited` / `notSupported`。

## Spotify

| 能力 | 官方依据 | 本项目处理 |
| --- | --- | --- |
| OAuth 2.0（PKCE） | Spotify Authorization Code with PKCE | 外部浏览器 + loopback 回调，令牌存入 `SecureCredentials` |
| 搜索 / 元数据（API） | Web API `/v1/search`、`/v1/tracks/{id}` | 已实现；但 Development Mode 需应用所有者有 Premium，未配置时自动走网页搜索 |
| 搜索（网页） | `open.spotify.com/search/{q}/tracks` 页面结果 | 已实现：在隐藏页面里解析 `tracklist-row`，不依赖 Client ID |
| 客户端内播放 | 官方网页播放器（WebView2 内真实播放） | 已实现：曲目页起播 + 元素级暂停/进度/音量；音频由 Spotify 官方页面输出 |
| 歌词 | 网页版只在内嵌歌词视图里渲染 | 未实现，`lyricsFor` 返回 null |
| 官方队列 | 网页版 `control-button-queue` | 未接；应用用自己的队列驱动播放 |
| 跳转官方 App | `spotify:track:{id}` / `https://open.spotify.com/track/{id}` | 允许，用户显式点击 |

说明：播放发生在官方页面内部，应用只做"遥控器"（不发请求取音频流、不碰 DRM、不落盘音频）。
Web Playback SDK 仍然不可用于桌面端，它的作用是让**第三方页面**成为播放设备，
与本项目"让官方页面自己播"的路线不同。

公共客户端只注入 `SPOTIFY_CLIENT_ID`。`client secret` 不得提交、打包或写入日志。

桌面客户端也支持在「连接」页输入 Client ID。该 ID 是公开标识，不属于密钥，
保存后会重建 PKCE 授权器并立即进入官方登录流程。

## 网易云音乐

| 能力 | 现状 | 本项目处理 |
| --- | --- | --- |
| 官方开放平台 OAuth | 仅对已获资质的企业/开发者开放，审核严格 | 未获资质前 `connect()` 抛 `ProviderException(notConfigured)` |
| 搜索 / 元数据 | 通过官方音乐网页搜索并解析页面结果 | `WebPlaybackEngine` 负责解析，不调用私有 API |
| 歌词 | 在官方页面上下文读取当前曲目的 LRC | 映射为 `LyricTimeline`，逐字缺失自动回退逐行 |
| 客户端内播放 | 通过隐藏的官方网页媒体元素输出 | 保持官方页面登录态；失败时明确提示 VIP/版权/登录限制 |
| 跳转官方 App | `https://music.163.com/song?id={id}` 或官方 scheme | 允许，用户显式点击 |

**明确禁止**：使用 `weapi` / `eapi` 等逆向接口、抓包密钥、第三方破解库、任何绕过版权的音频地址提取。
这类实现会同时违反服务条款与法律风险，代码评审中一律拒绝。

## 接入步骤（获得资质后）

1. 在获得资质后，把 `NeteaseProvider` 接到官方开放平台接口，同时保留现有网页播放器作为回退。
2. 令牌写入 `SecureCredentials`，键使用 `MusicService.storageKey`。
3. 用注入的 HTTP client 写契约测试（不访问真实网络），覆盖：成功、401、403、429、超时、空结果。
4. 在连接页展示能力矩阵；能力不支持时按钮禁用并说明原因。
5. 更新本文件的能力表，注明日期与官方文档链接。

## 已知限制

- 上游 API / SDK 政策可能变化，实现前必须重新核对官方文档。
- 即使完成授权，也不代表拥有全部能力；界面展示以运行时能力为准。
- 本项目的演示数据与真实账号无关，不能作为上线依据。
