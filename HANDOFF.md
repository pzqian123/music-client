# MusicMerge 交接说明

更新时间：2026-11-19（Asia/Shanghai）

## 正式项目位置

- 项目目录：`D:\dshws\music-client`
- 当前分支：`master`
- 当前提交：`301f259 feat: configure Spotify client ID in app`
- Git 工作区：干净
- Windows EXE：`build\windows\x64\runner\Debug\music_client.exe`

所有以下功能都已合并到 D 盘正式项目，不需要再从旧 worktree 同步：

- 真实网易云官方网页搜索、歌词、封面和客户端内播放。
- 官方网易云播放列表读取、客户端队列展示和直接点击切歌。
- 网页自动播放队列外曲目时，自动接入应用队列并同步标题、进度、歌词和封面。
- Apple Music 风格沉浸歌词：焦点行弹簧动画、逐字发光、呼吸点、模糊封面背景和控件淡出。
- 无边框 Windows 窗口、应用内 44px 标题栏和最小化/最大化/关闭按钮。
- Spotify 运行时 Client ID 配置、持久化、PKCE 授权器和按需登录入口。

## 最近验证

- `flutter analyze`：No issues found。
- 最近一次完整测试：161 个测试通过。
- Windows 调试构建：成功。
- 最新 EXE 在 2026-11-19 完成构建。
- 交接时已停止 `music_client` 进程，下一位 agent 可以直接重新启动 EXE。

注意：交接前重新运行完整 `flutter test` 时，Flutter 测试进程在当前机器上出现无输出挂起；
分组运行 Spotify Provider 和连接页测试仍然通过。下一位 agent 如再次遇到挂起，先终止残留的
`dart.exe` / `dartvm.exe`，再重试；不要把挂起误判为测试失败。

## Spotify 当前状态

代码层已完成：

- 「连接」页可输入 Client ID。
- Client ID 保存到平台安全存储，键为 `spotify.client_id`。
- 保存后会重建 `SpotifyAuth` 并立即进入 PKCE 登录。
- 启动时自动恢复 Client ID 和已有令牌。
- 真实搜索、401 刷新和官方 App 跳转逻辑已实现。

外部阻塞：

- Spotify 自 2026-02-06 起要求 Development Mode Web API 应用所有者拥有有效 Premium。
- 当前账号没有 Premium，因此不能创建可工作的 Development Mode 应用。
- 浏览器 Dashboard 中的应用没有创建成功，也没有取得 Client ID。
- 自动化浏览器会话已关闭。
- 不要使用 client secret、网页逆向、绕过 Premium 或非官方音频 URL。

推荐后续：将 Spotify 明确定位为“官方 App 跳转来源”，并在配置面板中标注需要 Premium；
如果用户后续订阅 Premium，再继续 Dashboard 创建应用。

## 测试工作区

- 旧 worktree：`C:\Users\Jo\.codex\worktrees\immersive-lyrics\music-client`
- 分支：`feat/immersive-lyrics`
- 最后提交：`f9b06d3`
- 工作区干净
- 该分支比正式 `master` 落后一个 Spotify Client ID 配置提交。

如果继续使用该 worktree，先执行：

```powershell
git merge --ff-only master
```

如果不再使用，可保留作为备份，或在确认正式项目完整后清理。

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
$env:PATH = "D:\dshws\.toolchains;$env:PATH"
flutter analyze
flutter test
flutter build windows --debug

# 正式 App
.\build\windows\x64\runner\Debug\music_client.exe

# 沉浸页本地预览
flutter build windows --debug -t tool/preview_main.dart
.\build\windows\x64\runner\Debug\music_client.exe --immersive
```

## 未完成或需要产品决策

- 无 Premium 的 Spotify 产品降级方式。
- Spotify Client ID 配置面板是否在无 Premium 时直接禁用“保存并登录”。
- Windows 后台播放、系统媒体控制和 Android 媒体通知。
- GitHub remote 和 PR 流程尚未配置。

