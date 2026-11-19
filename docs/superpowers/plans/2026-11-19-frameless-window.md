# Frameless Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Windows native title bar with an in-app 44px title bar and circular minimize, maximize/restore, and close controls.

**Architecture:** A platform-neutral `DesktopWindowService` isolates `window_manager`. `AppWindowChrome` wraps all Flutter routes through `MaterialApp.builder`, adding a branded title bar above existing page content. Windows startup initializes a frameless resizable window before showing the first frame.

**Tech Stack:** Flutter, `window_manager`, Provider-style dependency injection, Widget tests, Win32-backed Windows runner.

## Global Constraints

- Windows only; Android behavior must remain unchanged.
- Window title bar height is exactly 44 logical pixels.
- Window buttons are visual 32px circles with at least 40px hit targets.
- Preserve resize, Windows Snap, DPI, multi-monitor movement and `Alt+F4`.
- If startup window initialization fails, keep the native title bar.
- Existing 152 tests must remain passing.
- `flutter analyze` must report no issues and the Windows build must succeed.

---

### Task 1: Desktop window service

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/platform/desktop_window_service.dart`
- Create: `test/platform/desktop_window_service_test.dart`

**Interfaces:**
- Produces: `DesktopWindowService` with `minimize()`, `toggleMaximize()`, `close()`, `startDragging()`, and `Future<bool> isMaximized()`.
- Produces: `WindowManagerService` Windows implementation.
- Produces: `FakeDesktopWindowService` for tests.

- [ ] **Step 1: Add the package**

Run: `flutter pub add window_manager`

- [ ] **Step 2: Write the failing fake-service contract test**

```dart
test('fake records window operations', () async {
  final service = FakeDesktopWindowService();
  await service.minimize();
  await service.toggleMaximize();
  await service.startDragging();
  await service.close();
  expect(service.calls, [
    'minimize',
    'toggleMaximize',
    'startDragging',
    'close',
  ]);
});
```

- [ ] **Step 3: Run the failing test**

Run: `flutter test test/platform/desktop_window_service_test.dart`

Expected: FAIL because the service does not exist.

- [ ] **Step 4: Implement the service**

```dart
abstract interface class DesktopWindowService {
  Future<void> minimize();
  Future<void> toggleMaximize();
  Future<void> close();
  Future<void> startDragging();
  Future<bool> isMaximized();
}
```

`WindowManagerService` delegates to `windowManager`. `FakeDesktopWindowService`
records calls and returns a configurable `maximized` value.

- [ ] **Step 5: Verify and commit**

Run: `flutter test test/platform/desktop_window_service_test.dart`

Expected: PASS.

```bash
git add pubspec.yaml pubspec.lock lib/platform/desktop_window_service.dart test/platform/desktop_window_service_test.dart
git commit -m "feat: add desktop window service"
```

---

### Task 2: Circular window title bar

**Files:**
- Create: `lib/presentation/widgets/window_title_bar.dart`
- Create: `test/presentation/window_title_bar_test.dart`

**Interfaces:**
- Consumes: `DesktopWindowService`.
- Produces: `WindowTitleBar({required DesktopWindowService windowService, bool immersive = false})`.

- [ ] **Step 1: Write failing interaction tests**

```dart
testWidgets('window controls call their operations', (tester) async {
  final service = FakeDesktopWindowService();
  await tester.pumpWidget(MaterialApp(
    home: WindowTitleBar(windowService: service),
  ));
  await tester.tap(find.byKey(const Key('window-minimize')));
  await tester.tap(find.byKey(const Key('window-maximize')));
  await tester.tap(find.byKey(const Key('window-close')));
  expect(service.calls, containsAll([
    'minimize',
    'toggleMaximize',
    'close',
  ]));
});
```

- [ ] **Step 2: Run the failing test**

Run: `flutter test test/presentation/window_title_bar_test.dart`

Expected: FAIL because `WindowTitleBar` does not exist.

- [ ] **Step 3: Implement title bar**

Use a fixed `SizedBox(height: 44)`. Build a left app mark, a central
`GestureDetector` drag zone, and three 40px hit targets containing 32px circles.
Dragging calls `startDragging()`. Double tap and maximize click call
`toggleMaximize()`. Query `isMaximized()` after each toggle. Use 140ms
`AnimatedContainer` hover colors.

- [ ] **Step 4: Add responsive and drag tests**

At 480px width assert the “音乐聚合” label is hidden and all three button keys
remain visible. Drag the central key `window-drag-region` and assert
`startDragging` was recorded.

- [ ] **Step 5: Verify and commit**

Run: `flutter test test/presentation/window_title_bar_test.dart`

Expected: PASS.

```bash
git add lib/presentation/widgets/window_title_bar.dart test/presentation/window_title_bar_test.dart
git commit -m "feat: add in-app window title bar"
```

---

### Task 3: Application chrome wrapper

**Files:**
- Create: `lib/presentation/app_window_chrome.dart`
- Create: `test/presentation/app_window_chrome_test.dart`

**Interfaces:**
- Consumes: `WindowTitleBar`.
- Produces: `AppWindowChrome({required DesktopWindowService windowService, required Widget child, bool showWindowControls = true, bool immersive = false})`.

- [ ] **Step 1: Write failing chrome tests**

```dart
testWidgets('chrome reserves title height and shows child', (tester) async {
  await tester.pumpWidget(MaterialApp(
    home: AppWindowChrome(
      windowService: FakeDesktopWindowService(),
      child: const Text('content'),
    ),
  ));
  expect(find.text('content'), findsOneWidget);
  expect(find.byType(WindowTitleBar), findsOneWidget);
});
```

- [ ] **Step 2: Implement wrapper**

Return a `Column` containing the 44px title bar and `Expanded(child: child)`.
When `showWindowControls` is false, return the child unchanged.

- [ ] **Step 3: Verify non-Windows behavior test**

Assert `showWindowControls: false` renders no `WindowTitleBar` and gives the
child the full available size.

- [ ] **Step 4: Verify and commit**

Run: `flutter test test/presentation/app_window_chrome_test.dart`

Expected: PASS.

```bash
git add lib/presentation/app_window_chrome.dart test/presentation/app_window_chrome_test.dart
git commit -m "feat: reserve space for in-app window chrome"
```

---

### Task 4: Windows startup and MaterialApp integration

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/app.dart`
- Modify: `test/smoke_test.dart`

**Interfaces:**
- Consumes: `DesktopWindowService`, `WindowManagerService`, `AppWindowChrome`.
- Produces: Windows frameless startup with native-title-bar fallback.
- Produces: `MusicApp({MusicController? controller, DesktopWindowService? windowService})`.

- [ ] **Step 1: Write failing app chrome test**

```dart
testWidgets('app shows in-app window controls on desktop injection', (tester) async {
  final windowService = FakeDesktopWindowService();
  await tester.pumpWidget(MusicApp(
    controller: controller,
    windowService: windowService,
    showWindowControls: true,
  ));
  expect(find.byKey(const Key('window-close')), findsOneWidget);
});
```

- [ ] **Step 2: Implement startup**

In `lib/main.dart`, guard all `window_manager` setup with `Platform.isWindows`.
Call `waitUntilReadyToShow(WindowOptions(titleBarStyle: TitleBarStyle.hidden,
windowButtonVisibility: false, size: Size(1280, 720), minimumSize: Size(820,
560)), ...)` and then show/focus. Catch initialization errors and retain native
decorations.

- [ ] **Step 3: Integrate `MaterialApp.builder`**

Wrap every route:

```dart
builder: (context, child) => AppWindowChrome(
  windowService: _windowService,
  showWindowControls: _showWindowControls,
  child: child!,
),
```

Derive `_showWindowControls` from Windows and successful initialization. Add
constructor overrides solely so widget tests can inject a fake service.

- [ ] **Step 4: Verify**

Run: `flutter test test/smoke_test.dart`

Expected: PASS with no Material ancestor errors.

```bash
git add lib/main.dart lib/app.dart test/smoke_test.dart
git commit -m "feat: enable frameless Windows application shell"
```

---

### Task 5: Full verification and visual evidence

**Files:**
- Modify: `docs/screenshots/windows-app.png`
- Modify: `TOOLCHAIN.md`

**Interfaces:**
- Consumes: the complete frameless window.
- Produces: tested and documented Windows build.

- [ ] **Step 1: Run static analysis**

Run: `flutter analyze`

Expected: `No issues found!`

- [ ] **Step 2: Run all tests**

Run: `flutter test`

Expected: all tests pass; update the count in `TOOLCHAIN.md`.

- [ ] **Step 3: Build Windows**

Run: `flutter build windows --debug`

Expected: `Built build\windows\x64\runner\Debug\music_client.exe`.

- [ ] **Step 4: Perform Windows interaction verification**

Launch the EXE and verify drag, double-click maximize/restore, minimize,
maximize button, close, edge resizing, official page, and immersive mode.
Capture the result and replace `docs/screenshots/windows-app.png`.

- [ ] **Step 5: Commit**

```bash
git add docs/screenshots/windows-app.png TOOLCHAIN.md
git commit -m "test: verify frameless window behavior"
```
