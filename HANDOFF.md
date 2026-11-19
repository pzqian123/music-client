# MusicMerge 交接说明

更新时间：2026-11-19（Asia/Shanghai）

## 正式项目位置

- 项目目录：`D:\dshws\music-client`
- 当前分支：`master`
- Git 工作区：有未提交改动（Spotify 网页播放器实现，见下方"本次改动"）
- Windows EXE：`build\windows\x64\runner\Debug\music_client.exe`（默认构建，未带调试 define）

所有以下功能都已合并到 D 盘正式项目，不需要再从旧 worktree 同步：

- 真实网易云官方网页搜索、歌词、封面和客户端内播放。
- 官方网易云播放列表读取、客户端队列展示和直接点击切歌。
- 网页自动播放队列外曲目时，自动接入应用队列并同步标题、进度、歌词和封面。
- Apple Music 风格沉浸歌词。
- 无边框 Windows 窗口、应用内 44px 标题栏。
- **Spotify 客户端内播放（网页播放器路线）**：官方页面搜索、曲目页起播、
  暂停/继续/跳转进度/音量、登录状态探测、服务切换与记忆。

## 本次改动（Spotify 播放）

### 为什么不用 Web API / Web Playback SDK

- 2026-02-06 起 Spotify 要求 Development Mode 应用所有者具备 Premium，
  当前账号没有 Premium，拿不到可用的 Client ID，Web API 搜索这条路走不通。
- Web Playback SDK 只在浏览器环境可用，桌面 Flutter 端不可用。

### 实现方式（与网易云同一条"隐藏网页播放器"路线）

1. **两家官方页面常驻**：应用启动即各挂一个 WebView2（网易云 + Spotify），
   共用一个 WebView2 profile（`%LOCALAPPDATA%\MusicMerge\webview2`），
   所以一次搜索能同时拿到两个平台的真实结果，登录态各自独立保存。
2. 应用把两个 WebView 盖在自己的界面下面，只通过注入脚本操作播放；
   要登录某一家时把那一家的页面翻上来（`WebPlayerUi.open(service)`）。
3. 搜索：网易云走 hash 搜索页解析 `.srchsongst .item`；
   Spotify 走 `/search/{关键词}/tracks` 解析 `[data-testid="tracklist-row"]`。
4. 起播：打开 `/track/{id}`（Spotify 会自动起播），必要时点曲目页的
   `[data-testid="play-button"]`（播放中时它的 aria-label 是「暂停」）。
5. 控制：直接操作**不挂 DOM 的播放元素**（`document.createElement('video')` 创建后被
   Spotify 隐藏），实测 `currentTime` / `pause()` / `play()` 会让官方界面同步。
6. **跨服务歌词**：Spotify 曲目起播后，用「标题 + 艺人」在网易云页面搜索，
   挑标题一致、时长最接近的一条，取它的 LRC 喂给同一套歌词引擎；
   匹配不到（分数不足）就显示"暂无歌词"，不硬套同名不同曲。
7. 切换播放来源时会先暂停另一家，保证同一时刻只有一家在出声。

### 实测证据（2026-11-19，Chrome 156 / WebView2 157）

| 验证项 | 结果 |
| --- | --- |
| 官方页面登录态在 WebView2 内可用 | ✅ `[data-testid="user-widget-link"]` 存在 |
| 页面内搜索并解析结果 | ✅ 20 条 `tracklist-row`，标题/艺人/时长/封面都对 |
| 两个平台同时出现在搜索结果 | ✅ 同一次搜索：Spotify 与网易云来源都在（见截图） |
| 打开曲目页自动起播 | ✅ `Love Story` 236.31s，`autoplay_ok=1` |
| 元素 seek | ✅ `currentTime=60` → 官方界面 1:00；点进度条 75% → 2:50 |
| 元素 pause/resume | ✅ 官方按钮变「播放」、进度冻结；恢复后继续推进 |
| 应用侧状态同步 | ✅ 播放页显示封面/标题/艺人/0:30→3:56 进度 |
| Spotify 播放时用网易云歌词 | ✅ 网易云页面被驱动到 `search/m/?s=Love Story Taylor Swift`，歌词面板显示同步 LRC |
| 登录状态探测 | ✅ 连接页两家各自显示登录状态 |
| 缺陷修复 | ⚠️ 同曲多版本合并后来源按钮重复 Key → 已在 dedupe/SourceSelector 修掉 |

截图：`docs/screenshots/search-both-platforms.png`、
`docs/screenshots/spotify-with-netease-lyrics.png`、
`docs/screenshots/spotify-player-page.png`、`docs/screenshots/spotify-connections.png`。

### 关键坑（已在代码里注释）

- Spotify 的 DOM 里确实有一个 `<video>`，但那是 **5.7 秒循环的占位视频**，
  `pause()` 它不影响播放；真正的播放元素不挂 DOM，必须靠
  `AT_DOCUMENT_START` 劫持 `createElement` / `play` / `pause` 登记（见
  `lib/platform/web_player_scripts.dart` 的 `mediaTapScript`）。
- 选择器改成打分制：时长越长越像真的、`loop` 的降权、挂 DOM 的略降权。
- 曲目页是整页重载（不是 SPA 跳转），所以 `_openAndClick` 对 Spotify 放宽到 24 轮。

## 最近验证

- `flutter analyze`：No issues found。
- `flutter test`：全部通过（含新增 Spotify 解析/脚本/服务切换测试）。
- `node tool/verify_web_player_scripts.mjs`：用生产注入脚本跑 Spotify 的 DOM 形状，
  确认选择器挑到真播放元素、状态时长/进度正确。
- Windows 调试构建：成功；默认构建已替换为不带调试 define 的版本。

## 调试开关（仅验证用）

| 开关 | 作用 |
| --- | --- |
| `--dart-define=DSH_WEB_SERVICE=spotify` | 启动时隐藏页面直接承载 Spotify |
| `--dart-define=DSH_AUTO_OPEN_OFFICIAL=true` | 启动即挂载并显示官方页面 |
| `--dart-define=DSH_AUTO_SEARCH=...` / `DSH_AUTO_PLAY_FIRST=true` | 启动后自动搜索并播放第一条 |
| 环境变量 `DSH_WEBVIEW_DEBUG_PORT=9223` | 打开 WebView2 远程调试端口 |
| `tool/spotify_cdp_verify.ps1` | 通过 CDP 注入会话 / 读取官方页面状态 |

## 使用方式（普通用户）

1. 打开应用：网易云与 Spotify 的官方页面已经在后台常驻，
   搜索框输入关键词，结果里会同时出现两家的来源按钮。
2. 「连接」页 → 官方网页播放器里两家各有「打开官方页面」：第一次用哪家就打开哪家登录一次。
3. 搜索页点结果（或点来源按钮）→ 播放页控制播放/进度；
   Spotify 曲目会自动配上网易云的同步歌词。
4. 想换来源：播放页的来源按钮，或在搜索页点同一条结果的另一个来源按钮。

## 已知构建问题

`flutter_inappwebview_windows` 偶尔会产生损坏的增量构建状态：

```text
MSB3501: 未能读取 flutter_inappwebview_windows_DEPENDENCIES_DOWNLOAD.lastbuildstate
```

优先只移走以下目录后重试：

```text
build\windows\x64\plugins\flutter_inappwebview_windows\x64\Debug\flutter_inappwebview_windows_DEPENDENCIES_DOWNLOAD\flutter_.145BDADF.tlog
```

如果仍有问题，再执行 `flutter clean` 和 `flutter pub get`。

Android 使用 AGP 8.13.1 / Gradle 8.14.3 / Kotlin 2.3.0；
不要单独升级到 AGP 9，现有 `flutter_inappwebview_android` 尚不兼容。

## 常用命令

```powershell
$env:PATH = "D:\dshws\.toolchains\flutter\bin;D:\dshws\.toolchains\flutter\bin\cache\dart-sdk\bin;$env:PATH"
flutter analyze
flutter test
flutter build windows --debug
node tool/verify_web_player_scripts.mjs

# 正式 App
.\build\windows\x64\runner\Debug\music_client.exe

# 沉浸页本地预览
flutter build windows --debug -t tool/preview_main.dart
.\build\windows\x64\runner\Debug\music_client.exe --immersive
```

## 未完成或需要产品决策

- Spotify 歌词（官方只在网页版内嵌视图里给歌词，无 LRC 文本）。
- Spotify 官方队列面板（`control-button-queue`）尚未接进应用队列；
  目前应用用自己的队列驱动，点下一首会重新打开曲目页。
- Spotify 广告（免费账号）会短暂出现在官方页面里，状态会显示成广告标题。
- Windows 后台播放、系统媒体控制和 Android 媒体通知。
- GitHub remote 和 PR 流程尚未配置。
- 工作区改动尚未提交（按约定不在未被要求时提交）。
