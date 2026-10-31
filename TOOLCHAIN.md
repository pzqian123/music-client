# 工具链验证记录

验证时间：2026-10-31（本机 DESKTOP-Q7B00UD）

## Flutter

```
Flutter 3.47.9 • channel stable
Framework revision c197ca5199 (2026-10-29)
Engine hash 9e025265bef30b838c0c1b68cad19decf97048f2
Tools • Dart 3.13.7 • DevTools 2.60.0
位置：D:\dshws\.toolchains\flutter
```

## Visual Studio（Windows 构建）

```
[√] Visual Studio - develop Windows apps (Visual Studio Community 2026 18.11.3)
    Visual Studio at D:\Program Files\Microsoft Visual Studio\18\Community
    Visual Studio Community 2026 version 18.11.12328.437
    Windows 10 SDK version 10.0.26100.0
```

结论：**VS 2026 被 Flutter 3.47.9 接受**，不需要回退到 VS Build Tools 2022。

## Android

```
Android SDK at D:\dshws\.toolchains\android-sdk
Platform android-36, build-tools 36.0.0
JDK: D:\dshws\.toolchains\jdk-21.0.12+8 (Temurin 21.0.12+8)
licenses: All SDK package licenses accepted
```

已知告警：

- `Multiple adb binaries found`：另存在 `D:\platform-tools\adb.exe`，不影响构建，仅可能影响设备识别。
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
| `flutter build windows --debug` | **阻塞**：`Building with plugins requires symlink support`（需开启「开发人员模式」） |
| 解除方式 | 设置 → 系统 → 开发者选项 → 开发人员模式（需 UAC，当前进程非管理员无法代做） |

## 验证结论

- Windows：**待解除 Developer Mode 后复验**。
- Android：见 `flutter build apk --debug` 结果（首次构建需下载 Gradle 与依赖）。
- 测试：`flutter analyze` 0 issue；`flutter test` 全部通过（107 个用例）。
