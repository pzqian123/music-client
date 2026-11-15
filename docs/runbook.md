# 排障手册

## 构建类

### `Building with plugins requires symlink support`

Flutter 带插件的 Windows 构建需要创建符号链接。

1. 打开 设置 → 系统 → 开发者选项；
2. 打开「开发人员模式」（会弹一次 UAC）；
3. 重新运行 `flutter build windows --debug`。

备选：以管理员身份运行终端后再构建一次。

### Gradle 报 `SSLHandshakeException` / `Could not resolve com.android.tools.build:gradle`

本机无法直连 `maven.google.com` 与 GitHub。

1. 确认 `android/settings.gradle.kts`、`android/build.gradle.kts` 里的阿里云镜像仍在 `google()` 之前；
2. 确认 `android/gradle/wrapper/gradle-wrapper.properties` 使用腾讯镜像
   `https://mirrors.cloud.tencent.com/gradle/gradle-9.3.1-bin.zip`；
3. 清理缓存后重试：删除 `~/.gradle/caches`（可选）与 `build/` 目录。

### `Some Android licenses not accepted`

```powershell
flutter doctor --android-licenses   # 一路输入 y
```

### `Multiple adb binaries found`

本机同时存在 `D:\platform-tools\adb.exe` 与 Android SDK 内的 adb。
把 PATH 中 SDK 的 `platform-tools` 放在前面，或删除多余的那份。

## 运行类

### 界面显示「演示数据」

检查是否用 `--dart-define=SPOTIFY_CLIENT_ID=...` 启动，以及当前平台是否能挂载官方网页播放器。
未配置 Spotify 时会保留 Spotify 演示搜索；不能挂载网页播放器的平台会整体回退到演示数据。

### Spotify 登录后没有结果

1. 确认 Spotify Dashboard 已添加 loopback redirect URI，且路径为 `/callback`；
2. 确认启动参数只包含客户端 ID，不需要也不应包含 client secret；
3. 免费账号可用于搜索；若出现 401，请重新连接或检查应用是否被撤销授权。

### 点击播放后提示「该账号无客户端内播放权限」

演示 Spotify Provider 固定返回 `requiresSubscription`，用于验证降级路径。
可点「打开官方 App」跳转，或切换到网易云来源。

### 歌词不滚动 / 只有静态歌词

1. 「暂无时间戳歌词」= 该歌词只有纯文本，没有时间轴；
2. 「暂无歌词」= 该曲目没有歌词数据；
3. 歌词存在但不滚动时，检查播放状态是否为 `playing`（暂停时歌词不动是预期行为）。

### 沉浸模式无法退出

Esc、左上角向下箭头、Android 返回键都可以退出。
若都无效，切回暖色主题下的播放页再试；必要时重启应用。

## 隐私自查

提交前执行：

```powershell
Select-String -Path (Get-ChildItem -Recurse -Include *.dart,*.md -File) -Pattern "password|client_secret|Bearer |weapi"
```

期望：仅命中文档中的「禁止」说明与 `password` 相关字样（无实际输入控件），无真实密钥。
