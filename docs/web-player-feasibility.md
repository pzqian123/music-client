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
| 桥接层能否控制真实 `<audio>` | ✅ 能 | 自测：play / pause / seek / 状态回读全部正确 |
| 页面被盖住后音频是否继续 | ✅ 继续 | 自测：覆盖后 2.5s 内位置推进 2502ms |

## 双网页播放器（2026-11-19）：两家常驻 + 跨服务歌词

同一次搜索要看到两个平台，就不能只留一个 WebView：

- 应用启动时同时挂 `music.163.com` 与 `open.spotify.com` 两个 WebView2，
  它们共用同一个 WebView2 profile，因此两家的登录态互不干扰但都可用。
- 每个 WebView 配一个 `WebPlaybackEngine`（服务固定），
  `MusicController` 用 `webEngines` 映射决定"这条轨道该由谁播"。
- 显示层只决定"谁翻到最上面"：`WebPlayerUi.open(service)`；
  另一家的 WebView 只是被盖住，不卸载（卸载会立刻停音频）。
- 切到另一家播放时，先对上一家 `pausePlayback()`，保证只有一家出声。

**跨服务歌词**：Spotify 网页版不给 LRC，但网易云页面能按歌名搜到同曲并返回带时间戳歌词。
于是 Spotify 曲目起播后，用「标题 + 艺人」在网易云页面搜索，挑分数最高的一条
（标题完全一致 +3、包含 +2、艺人匹配 +1、时长差 ≤3s +2 / ≤10s +1，低于 2 分放弃），
再取它的 LRC。实测 "Love Story / Taylor Swift" 能正确匹配并同步高亮。

## 真实环境验证（Spotify，2026-11-19 已通过）

环境：Chrome 156 / WebView2（Edge 157）、登录的真实 Spotify 账号。

| 采样 | 播放元素 | 官方界面 | 结论 |
| --- | --- | --- | --- |
| 起播 | `paused=false, t=17.4, d=236.31` | 0:16 / 3:56，按钮「暂停」 | 曲目页打开即自动起播 |
| `el.currentTime = 60` | `t=61.0` | 1:00 | 元素 seek 生效，官方界面同步 |
| 点进度条 75% | `t=170.3` | 2:50 | 应用侧 seek 也走元素 |
| `el.pause()` | `paused=true, t` 冻结 | 按钮变「播放」 | 暂停真生效 |
| `el.play()` | `paused=false, t` 继续 | 按钮变「暂停」 | 继续播放生效 |

### Spotify 的两个致命坑

1. **DOM 里的 `<video>` 不是播放源**。它是 `loop` 的 5.7 秒占位视频，
   `querySelectorAll('audio, video')` 只能拿到它；`pause()` 它，音乐照放。
   真正的播放元素是 `document.createElement('video')` 创建后**不挂 DOM** 的对象，
   必须靠 `mediaTapScript` 在 `AT_DOCUMENT_START` 劫持 `createElement` / `play` / `pause` 登记。
   验证方法：先注入劫持脚本，再切歌触发 `play()`，然后读登记表拿到 `duration=242.19` 的真元素。
2. **曲目页是整页重载**。`/track/{id}` 会重新加载文档（并自动附上 `?autoplay_ok=1`），
   所以每次导航后注入脚本会重新安装，等待时间要放宽（实测 24 轮 × 500ms 足够）。

### Spotify 已核对的选择器（2026-11 生产 DOM）

| 用途 | 选择器 |
| --- | --- |
| 当前曲名 | `[data-testid="context-item-link"]`（文本；href 指向 album/playlist，不是曲目） |
| 当前艺人 | `[data-testid="now-playing-widget-v2-byline"]` |
| 播放/暂停 | `[data-testid="control-button-playpause"]`（aria-label「播放」/「暂停」） |
| 上一首/下一首 | `[data-testid="control-button-skip-back"|"control-button-skip-forward"]` |
| 进度文本 | `[data-testid="playback-position"]` / `[data-testid="playback-duration"]` |
| 进度条 | `[data-testid="playback-progressbar"]`（role=slider） |
| 播放条封面 | `[data-testid="cover-art-image"]`（640px） |
| 搜索结果行 | `[data-testid="tracklist-row"]`，行内 `a[href*="/track/"]` / `a[href*="/artist/"]` |
| 曲目页大按钮 | `[data-testid="action-bar-row"] [data-testid="play-button"]` |
| 登录判定 | `[data-testid="user-widget-link"]` 存在即已登录 |

封面可以直接用 `i.scdn.co` 的 URL（实测 Dart 侧带浏览器 UA 即可 200），
列表里的 64px 尺寸段 `ab67616d00004851` 换成 `ab67616d0000b273` 就是 640px。

## 真实环境验证（网易云，已通过）

2026-10-31 23:5x，用户在本应用内登录网易云并播放《少女的祈祷》，随后点「盖住官方页面」：

| 采样时刻 | 我们的 UI | 诊断行 |
| --- | --- | --- |
| 盖住后第 1 次 | 0:58 / 3:38，暂停按钮 | 媒体元素 3 个 · 播放中 · 页面「▶ 少女的祈祷」 |
| 约 14 秒后 | 1:12 / 3:38，进度条前移 | 同上，位置持续增大 |

结论：官方页面被完全盖住后，音频继续输出，我们的界面实时显示真实进度并可暂停/拖动。
截图：`docs/screenshots/hidden-player-working.png`

## 桥接层自测结果（2026-10-31，本地音频页，不依赖任何账号）

```
initial       paused=true   0ms / 120000ms
afterPlay     paused=false  1476ms          ← play() 生效
afterSeek20   paused=false  21167ms         ← seek(20s) 生效
afterPause    paused=true   21168ms         ← pause() 生效
pausedStill   paused=true   21168ms         ← 暂停后不再推进（+0ms）
coveredStart  paused=false  22029ms         ← 盖上不透明面板（模拟隐藏）
coveredLater  paused=false  24531ms         ← 覆盖期间继续推进 2502ms
```

### 必须的两个 WebView2 启动参数

缺一个都会失败，这是踩过的坑：

```
--autoplay-policy=no-user-gesture-required
--disable-features=CalculateNativeWinOcclusion
```

- 第一个：否则 JS 调 `play()` 会被自动播放策略拦截（实测 `paused` 永远为 true）。
- 第二个：否则页面被盖住/遮挡时 Chromium 判定不可见，会节流甚至暂停播放。

在 `WebViewEnvironmentSettings.additionalBrowserArguments` 里设置。

### 另一个坑：官方播放器的音频对象不在 DOM 里

网易云用 `new Audio()` 创建音频对象但**不挂到 document**，
`document.querySelectorAll('audio, video')` 永远返回 0，进度条一直是 0:00。

解决：在 `AT_DOCUMENT_START` 注入脚本劫持 `Audio` 构造函数、`Document.createElement`
与 `HTMLMediaElement.prototype.play`，把创建过的元素登记到 `window.__dshMediaEls`；
再叠加一层「官方播放栏文本」兜底（读 `.m-playbar .time` 与播放按钮 title）。

### 还有：登录态要持久化

不指定 `userDataFolder` 时每次启动都是全新的浏览器会话，官方页面要重新登录。
现在固定用 `%LOCALAPPDATA%\MusicMerge\webview2`。

### 另一个坑：本地/自建静态服务器必须支持 Range

不支持 `Accept-Ranges` / 206 时，Chromium 会把音频当成未知长度的流，
`duration` 为 `Infinity`，进度条和跳转全部失效（自测第一次就是 0/0）。
`tools/serve_web.js` 已补上 Range 支持。

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
