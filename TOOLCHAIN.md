# 工具链验证记录

验证时间：2026-11-15（Windows 开发机）

## Flutter

```
Flutter 3.47.9 • channel stable
Framework revision c197ca5199 (2026-10-29)
Engine hash 9e025265bef30b838c0c1b68cad19decf97048f2
Tools • Dart 3.13.7 • DevTools 2.60.0
位置：<toolchain-root>\flutter
```

## Visual Studio（Windows 构建）

```
[√] Visual Studio - develop Windows apps (Visual Studio Community 2026 18.11.3)
    Visual Studio at <VS install>
    Visual Studio Community 2026 version 18.11.12328.437
    Windows 10 SDK version 10.0.26100.0
```

结论：**VS 2026 被 Flutter 3.47.9 接受**，不需要回退到 VS Build Tools 2022。

## Android

```
Android SDK at <toolchain-root>\android-sdk
Platform android-36, build-tools 36.0.0
JDK: <toolchain-root>\jdk-21.0.12+8 (Temurin 21.0.12+8)
licenses: All SDK package licenses accepted
```

已知告警：

- `Multiple adb binaries found`：系统里另有一份 `platform-tools\adb.exe`，不影响构建，仅可能影响设备识别。
- 无模拟器 / 无真机：只能构建 APK，不能 `flutter run -d android`。

## 网络限制（已通过镜像绕过）

| 主机 | 结果 | 处理 |
| --- | --- | --- |
| storage.googleapis.com（Flutter SDK） | 可访问 | 直接下载 3.47.9 |
| pub.dev | 可访问 | 正常 |
| maven.google.com | **不可用**（TLS 握手失败，代理亦失败） | 改用阿里云 `maven.aliyun.com/repository/google` |
| services.gradle.org → github.com | **不可用**（307 到 GitHub 被拦截） | 改用腾讯镜像 `mirrors.cloud.tencent.com/gradle/` |
| services.gradle.org 本身 | 200 | 仅重定向链路有问题 |

## Windows 构建状态

| 检查项 | 结果 |
| --- | --- |
| 开发人员模式 | ✅ 已开启（`AllowDevelopmentWithoutDevLicense=1`，`mklink` 验证可建链接） |
| `flutter build windows --debug` | ✅ 成功，产物 `build/windows/x64/runner/Debug/music_client.exe` |
| 实际启动 | ✅ 已启动并截图，见 `docs/screenshots/windows-app.png` |

注：PowerShell 的 `New-Item -ItemType SymbolicLink` 仍会报“需要管理员权限”，
但 `cmd /c mklink` 与 Flutter 工具链均可正常创建链接，不影响构建。

## 验证结论

| 目标 | 状态 | 证据 |
| --- | --- | --- |
| 静态检查 | ✅ | `flutter analyze` → No issues found |
| 测试 | ✅ | `flutter test` → 175 passed |
| Android APK | ✅ | `build/app/outputs/flutter-apk/app-debug.apk`（debug，含全部 ABI） |
| Windows 桌面 | ✅ | `build/windows/x64/runner/Debug/music_client.exe`，已启动验证 |
| Web 预览（仅用于看界面） | ✅ | `build/web` + `tools/serve_web.js`，截图见 `docs/screenshots/` |

Android 首次构建踩到的坑（已修复并写入 `android/gradle.properties`）：

- Kotlin 增量编译在「插件源码在 C: 盘 pub 缓存、工程在 D: 盘」时报
  `this and base files have different roots` 并卡住 → `kotlin.incremental=false`。
- 默认 30s 网络超时对不可达仓库不够快 → 调成 15s 连接/读超时。
- `flutter_inappwebview_android 1.1.3` 尚不兼容 AGP 9，项目固定使用 AGP 8.13.1 /
  Gradle 8.14.3 / Kotlin 2.3.0；升级该插件后再重新评估 AGP 9。

## Web 预览用法

```powershell
flutter build web --release -t tool/preview_main.dart   # 预览入口：直接渲染播放页
node tools/serve_web.js 8099 build/web                  # http://127.0.0.1:8099/?view=split
                                                        # http://127.0.0.1:8099/?view=immersive
```

`tool/preview_main.dart` 只用于视觉验证，不进入产品入口 `lib/main.dart`。

