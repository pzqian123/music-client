# 音乐聚合（MusicMerge）

Spotify 与网易云音乐的聚合客户端：Windows + Android（Flutter），
统一搜索、保守去重、来源切换、统一队列、分栏播放页与 Apple Music 风格的沉浸式同步歌词。

当前版本已经接入真实数据与播放链路：

- 网易云音乐：通过隐藏的官方网页搜索、抓取曲目/封面/歌词，并由官方网页媒体元素播放。
- 网易云队列：读取并接管官方网页播放列表，在客户端内展示并可直接点击官方队列行切歌。
- Spotify：配置客户端 ID 后走官方 Authorization Code + PKCE，使用 Web API 做搜索和元数据。
  搜索不要求 Spotify Premium；客户端内播放仍不支持，用户可显式跳转官方 App。
- 未配置 Spotify，或在无法挂载官方网页播放器的平台上，自动回退到可重复的演示数据。

接入边界与隐私要求见 [docs/provider-integration.md](docs/provider-integration.md)。

## 已实现

- 统一搜索：一个搜索框同时查询两个服务，结果标准化并合并高置信度同曲；来源可显式切换。
- 保守去重：标题/艺人标准化 + 版本标记（Live、Remix、现场等）必须完全一致 + 时长差 ≤ 8s 才合并。
- 播放页：宽屏左 38% 专辑与控制、右 62% 同步歌词；窄屏上下堆叠。
- 沉浸模式：全窗口歌词、专辑主色氛围背景、居中滚动、底部精简控制；Esc / 返回键退出。
- 歌词引擎：逐字优先，缺可靠逐字时间戳整体回退逐行，无时间戳显示静态并提示，无歌词显示「暂无歌词」。
- 能力状态：连接页逐项展示搜索 / 元数据 / 歌词 / 客户端内播放 / 跳转官方，未获授权不假装可用。
- 错误隔离：一个服务失败时另一个服务的结果照常展示，并给出局部重试。
- 隐私边界：不请求密码，界面无密码输入框；凭证抽象只接受服务端返回值。
- Spotify 令牌存入平台安全存储并在启动时恢复；授权过期时自动刷新。
- 播放到曲目结尾时自动进入队列下一首；队列对同一曲目去重。

## 环境准备（本机已装好）

| 工具 | 路径 |
| --- | --- |
| Flutter 3.47.9 / Dart 3.13.7 | `D:\dshws\.toolchains\flutter` |
| JDK 21 (Temurin) | `D:\dshws\.toolchains\jdk-21.0.12+8` |
| Android SDK 36 | `D:\dshws\.toolchains\android-sdk` |
| Visual Studio 2026 Community | `D:\Program Files\Microsoft Visual Studio\18\Community` |

每次新开终端需要设置环境变量（PowerShell）：

```powershell
$env:JAVA_HOME = "D:\dshws\.toolchains\jdk-21.0.12+8"
$env:ANDROID_HOME = "D:\dshws\.toolchains\android-sdk"
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:PATH = "D:\dshws\.toolchains\flutter\bin;$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:PATH"
```

## 常用命令

```powershell
flutter pub get                # 安装依赖
flutter analyze                # 静态检查，要求 0 issue
flutter test                   # 全部单元测试与 Widget 测试
flutter build apk --debug      # Android 调试包
flutter build windows --debug  # Windows 桌面（需要“开发人员模式”以支持插件符号链接）
flutter run -d windows         # 本地运行
```

### 启用 Spotify 真实搜索

1. 在 Spotify Developer Dashboard 创建应用。
2. 添加 loopback redirect URI，例如 `http://127.0.0.1:8080/callback`。
   Spotify 允许 loopback IP 使用动态端口，因此应用启动时会选择可用端口，但路径保持 `/callback`。
3. 不要把 client secret 放进客户端。本项目是公共客户端，只使用客户端 ID 与 PKCE。
4. 用构建参数启动：

```powershell
flutter run -d windows --dart-define=SPOTIFY_CLIENT_ID=你的客户端ID
```

Spotify 免费账号可用于本项目的搜索与元数据。Web Playback SDK 的客户端内流媒体播放要求
Premium，且不适合作为当前 Windows/Android 架构内的通用播放后端，因此本项目仍通过
“打开官方 App”处理 Spotify 播放。

## 构建环境注意事项

1. **符号链接**：Flutter 带插件的 Windows 构建要求系统开启「开发人员模式」
   （设置 → 系统 → 开发者选项 → 开发人员模式），否则报
   `Building with plugins requires symlink support`。
2. **国内网络**：本机无法直连 `maven.google.com` 与 GitHub，`android/settings.gradle.kts` 与
   `android/build.gradle.kts` 已把阿里云镜像放在 `google()` 之前；
   Gradle 发行包改用腾讯镜像（见 `android/gradle/wrapper/gradle-wrapper.properties`）。
   网络正常的环境可以把这两处改回官方源。
3. `flutter_inappwebview_android` 当前版本不兼容 AGP 9，项目固定为 AGP 8.13.1；
   不要单独升级 AGP，除非插件已发布兼容版本。

## 演示数据回退

| 服务 | 曲目 | 说明 |
| --- | --- | --- |
| Spotify | 夜空中最亮的星 / 夜空中最亮的星 (Live) / 晴天 / Bohemian Rhapsody | 账号无客户端内播放权限，播放会提示跳转官方 App |
| 网易云音乐 | 夜空中最亮的星 / 晴天 / 平凡之路 / 稻香 | 支持客户端内演示播放；含逐字、静态、无歌词三种歌词 |

当 Spotify 未配置或官方网页播放器不可用时，搜索「夜空」可直接看到同曲合并（2 个来源）
与 Live 版分开保留。真实网易云搜索由官方网页完成，不会调用 `weapi` / `eapi`。

## 手动验收清单

- [ ] 配置 Spotify 后搜索「夜空」：出现一条带 Spotify + 网易云两个来源的结果，以及一条 Live 版。
- [ ] 点击 Spotify 来源：进入 blocked 状态，显示原因与「打开官方 App」。
- [ ] 点击网易云来源：进入播放态，歌词按行/逐字推进。
- [ ] 播放到结尾：队列有下一首时自动切歌。
- [ ] 播放页「沉浸模式」：进入全屏歌词，Esc 或返回按钮回到分栏，进度不丢。
- [ ] 「平凡之路」：显示「暂无时间戳歌词」；「稻香」：显示「暂无歌词」。
- [ ] 一个服务失败后另一方结果仍显示，并出现「重试」。
- [ ] 连接页无任何密码输入框；「打开官方 App」在没有可跳转曲目时禁用。

## 目录

```
lib/
├── application/   播放时钟、唯一状态源 MusicController
├── domain/        模型、去重、歌词时间轴、播放状态机（纯 Dart）
├── platform/      凭证存储与官方跳转抽象
├── providers/     统一 Provider 契约 + Spotify 真实实现 + 演示实现
└── presentation/  搜索页、播放页、沉浸歌词页、连接页与组件
test/              领域 / 应用 / Provider / Widget 测试
docs/              设计文档、接入边界、排障手册
```

## 尚未完成

- 网易云开放平台正式资质与官方 API 播放/歌词接口（当前使用官方网页播放器）。
- Spotify 客户端内播放（Premium + Web Playback SDK，不在当前产品边界内）。
- 后台播放、系统媒体控制与跨平台媒体通知。
- 推荐、歌单迁移、曲库写同步、遥测（均不在首版范围）。
