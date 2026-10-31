# 隐藏式网页播放器：可行性验证记录

验证时间：2026-10-31
环境：Windows 10 21H2、WebView2 (Chrome/156.0.0.0, Edge 156)、Flutter 3.47.9、VS2026

## 结论速览

| 问题 | 结论 | 证据 |
| --- | --- | --- |
| WebView2 是否支持 Widevine | ✅ 支持 | EME 探针返回 `com.widevine.alpha → OK` |
| WebView2 是否支持 PlayReady | ✅ 支持 | EME 探针返回 `com.microsoft.playready → OK` |
| Spotify 网页版能否在 WebView2 内加载 | ✅ 能 | 首页完整渲染（热播歌曲、登录、搜索） |
| 网易云网页版能否在 WebView2 内加载 | ✅ 能 | 首页完整渲染（推荐、排行榜、登录） |
| 隐藏后能否继续由我们的 UI 控制 | ⏳ 待登录实测 | 桥接层已实现，Demo 已可运行 |

## 技术路线

1. 应用内嵌 WebView2，加载官方网页（`open.spotify.com` / `music.163.com`）。
2. 登录阶段显示该页面，用户**自己在官方页面里登录**，应用不接触账号密码。
3. 登录后把 WebView 缩到 2×2、`Opacity(0)`、`IgnorePointer`，但**不销毁**（否则登录态与音频会丢）。
4. 我们的 UI 通过 JS 注入直接操作底层 `<audio>/<video>`：
   - 状态：`currentTime`、`duration`、`paused`、`ended`、`volume`
   - 控制：`play()`、`pause()`、`currentTime = t`、`volume = v`
5. 歌词仍由我们的引擎按轮询到的 `currentTime` 驱动，官方页面完全不出现。

选择直接操作媒体元素而不是抓 DOM 选择器，是因为各服务前端改版频繁，
而 `<audio>/<video>` 是平台级标准接口，稳定性高得多。

## 已实现的代码

| 文件 | 作用 |
| --- | --- |
| `lib/platform/web_player_scripts.dart` | 注入用的 JS：状态探测、播放/暂停、跳转、音量 |
| `lib/platform/web_player_engine.dart` | 纯 Dart 状态模型 + 两家服务的入口/深链接适配 |
| `lib/platform/pkce.dart`、`oauth_flow.dart`、`spotify_auth.dart` | Spotify 官方 PKCE 登录（回环回调） |
| `lib/presentation/widgets/hidden_web_player.dart` | 隐藏/显示的 WebView 宿主 + 控制句柄 |
| `tool/web_player_demo.dart` | 可运行 Demo：登录 → 隐藏 → 用我们的控件播放/拖动 |

## 已知风险与对策

| 风险 | 现状 | 对策 |
| --- | --- | --- |
| 自动播放策略阻止 `play()` | 已在 WebView 设置 `mediaPlaybackRequiresUserGesture: false` | 仍失败时，可在 WebView2 启动参数加 `--autoplay-policy=no-user-gesture-required` |
| 隐藏后 Chromium 节流 | 未验证 | 保留 2×2 可视区域（不用 `Offstage`）；必要时定期调用 `window.focus()` |
| 页面改版导致选择器失效 | 已规避（操作媒体元素而非 DOM） | 保留调试面板，可现场注入 JS 检查 |
| 服务方检测到嵌入浏览器 | 未观察到拦截 | 不做 UA 伪装；若被拦，明示用户并回退官方 App |
| 版权与条款 | 播放发生在官方页面内，应用不提取音频流 | 不做解密/抓流；仅作为"官方页面的遥控器" |
| Spotify 需要 Premium | 已知 | 未登录/非 Premium 时给出明确提示 |

## 下一步（需要真实账号）

1. 用 `tool/web_player_demo.dart` 打开网易云页面，登录后点「隐藏播放器」，输入歌曲 ID 播放，观察：
   - 隐藏后音频是否继续
   - 进度条拖动是否生效
   - 状态回读是否连续（是否有跳变）
2. Spotify 同样流程（需 Premium），重点看 DRM 解密在隐藏状态下是否仍工作。
3. 验证通过后，把 `WebPlayerHandle` 接进 `MusicController`，让播放页直接驱动它。

## 复现命令

```powershell
# 需要：Flutter SDK、VS2026（含 C++ 桌面工作负载）、nuget.exe 在 PATH 中
flutter build windows --debug -t tool/web_player_demo.dart
build\windows\x64\runner\Debug\music_client.exe
```

构建前提（本机已处理）：

- `windows/CMakeLists.txt` 已加 `/D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS`，
  否则 flutter_inappwebview 在 VS2026 的 MSVC 14.5x 下编译失败。
- 插件需要 `nuget.exe` 拉取 WebView2 SDK，本机放在 `D:\dshws\.toolchains\nuget.exe`。
