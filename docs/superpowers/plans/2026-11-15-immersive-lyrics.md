# Immersive Apple Music Lyrics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild immersive lyrics as a centered, spring-animated Apple Music-style stage while preserving playback and lyric timing.

**Architecture:** `ImmersiveLyricsPage` composes a cached ambient backdrop, a focused lyric viewport, and translucent controls. The viewport derives all timing from `LyricTimeline` and `MusicController.playback.position`; it owns only presentation animation state.

**Tech Stack:** Flutter/Dart, Provider, Widget tests, `AnimationController`, `SpringSimulation`, `RepaintBoundary`.

## Global Constraints

- Keep `MusicController.playback.position` as the only playback clock.
- Do not change search, queue, provider, or lyric parsing contracts.
- Keep existing tests passing.
- `flutter analyze` must report no issues.
- Respect `MediaQuery.disableAnimations`.
- Use original implementation; copy no Lyricify assets or proprietary code.
- Target Windows, Android, 720p, 1080p, and narrow layouts.

---

### Task 1: Focus viewport geometry and active-line tests

**Files:**
- Create: `lib/presentation/widgets/focus_lyrics_viewport.dart`
- Test: `test/presentation/focus_lyrics_viewport_test.dart`

**Interfaces:**
- Consumes: `LyricTimeline`, `Duration position`, `ValueChanged<Duration> onSeek`.
- Produces: `FocusLyricsViewport({required LyricTimeline? timeline, required Duration position, required ValueChanged<Duration> onSeek, bool animate = true})`.

- [ ] **Step 1: Write failing viewport tests**

```dart
testWidgets('focused line follows position and invokes seek', (tester) async {
  final timeline = LyricTimeline([
    const LyricLine(text: '第一行', start: Duration.zero, end: Duration(seconds: 2)),
    const LyricLine(text: '第二行', start: Duration(seconds: 2), end: Duration(seconds: 4)),
  ]);
  Duration? sought;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: FocusLyricsViewport(
        timeline: timeline,
        position: const Duration(seconds: 2, milliseconds: 500),
        onSeek: (value) => sought = value,
      ),
    ),
  ));
  expect(find.byKey(const Key('focused-lyric-line-1')), findsOneWidget);
  await tester.tap(find.byKey(const Key('focused-lyric-line-1')));
  expect(sought, const Duration(seconds: 2));
});
```

- [ ] **Step 2: Run failing test**

Run: `flutter test test/presentation/focus_lyrics_viewport_test.dart`

Expected: FAIL because `FocusLyricsViewport` does not exist.

- [ ] **Step 3: Implement viewport geometry**

The state renders a centered `Stack`, calculates five or seven visible lines from
available height, marks the active index with `Key('focused-lyric-line-$index')`,
and calls `onSeek(line.start)` on tap. Empty and static timelines use explicit
fallback states.

- [ ] **Step 4: Verify**

Run: `flutter test test/presentation/focus_lyrics_viewport_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/widgets/focus_lyrics_viewport.dart test/presentation/focus_lyrics_viewport_test.dart
git commit -m "feat: add focused lyrics viewport"
```

---

### Task 2: Spring focus transition and responsive transforms

**Files:**
- Modify: `lib/presentation/widgets/focus_lyrics_viewport.dart`
- Modify: `test/presentation/focus_lyrics_viewport_test.dart`

**Interfaces:**
- Consumes: Task 1 viewport.
- Produces: continuous focus offset animation and line-specific scale/opacity.

- [ ] **Step 1: Add failing reduced-motion test**

```dart
testWidgets('reduced motion keeps the transition transform stable', (tester) async {
  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: FocusLyricsViewport(
        timeline: _timeline,
        position: const Duration(seconds: 3),
        onSeek: (_) {},
      ),
    ),
  ));
  expect(find.byKey(const Key('focused-lyric-transition')), findsOneWidget);
});
```

- [ ] **Step 2: Run failing test**

Run: `flutter test test/presentation/focus_lyrics_viewport_test.dart`

Expected: FAIL because the transition key is missing.

- [ ] **Step 3: Add spring simulation**

Use `SpringSimulation` with mass 1, stiffness 260, damping 28. Map focus distance
to scale `1.0 → 0.82`, opacity `1.0 → 0.24`, and horizontal offset `0 → 18`.
When `MediaQuery.disableAnimations` is true, snap to the target offset.

- [ ] **Step 4: Verify**

Run: `flutter test test/presentation/focus_lyrics_viewport_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/widgets/focus_lyrics_viewport.dart test/presentation/focus_lyrics_viewport_test.dart
git commit -m "feat: animate focused lyrics transitions"
```

---

### Task 3: Karaoke sweep, glow, and breathing points

**Files:**
- Modify: `lib/presentation/widgets/focus_lyrics_viewport.dart`
- Modify: `test/presentation/focus_lyrics_viewport_test.dart`

**Interfaces:**
- Consumes: `LyricTimeline.wordProgressesAt`, `LyricLine.end`, next start.
- Produces: active word spans and `Key('lyrics-breathing')` during gaps > 4s.

- [ ] **Step 1: Add failing breathing test**

```dart
testWidgets('shows breathing dots during a long instrumental gap', (tester) async {
  final timeline = LyricTimeline([
    const LyricLine(text: '第一行', start: Duration.zero, end: Duration(seconds: 1)),
    const LyricLine(text: '第二行', start: Duration(seconds: 8), end: Duration(seconds: 10)),
  ]);
  await tester.pumpWidget(MaterialApp(
    home: FocusLyricsViewport(
      timeline: timeline,
      position: const Duration(seconds: 4),
      onSeek: (_) {},
    ),
  ));
  expect(find.byKey(const Key('lyrics-breathing')), findsOneWidget);
});
```

- [ ] **Step 2: Run failing test**

Run: `flutter test test/presentation/focus_lyrics_viewport_test.dart`

Expected: FAIL because breathing indicator is absent.

- [ ] **Step 3: Implement sweep and breathing**

Use `wordProgressesAt` only on the active line. Interpolate word color from
`white38` to white and glow opacity from 0 to 0.28. Show three pulsing dots when
the next lyric is more than four seconds away during the active-line tail.

- [ ] **Step 4: Verify**

Run: `flutter test test/presentation/focus_lyrics_viewport_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/widgets/focus_lyrics_viewport.dart test/presentation/focus_lyrics_viewport_test.dart
git commit -m "feat: add karaoke glow and lyric breathing"
```

---

### Task 4: Ambient blurred-cover backdrop

**Files:**
- Create: `lib/presentation/widgets/immersive_ambient_backdrop.dart`
- Test: `test/presentation/immersive_ambient_backdrop_test.dart`

**Interfaces:**
- Consumes: `accentColor`, optional `Uint8List artworkBytes`, `trackKey`.
- Produces: `ImmersiveAmbientBackdrop({int? accentColor, Uint8List? artworkBytes, required String trackKey, bool animate = true})`.

- [ ] **Step 1: Write failing fallback test**

```dart
testWidgets('renders without artwork using accent color fallback', (tester) async {
  await tester.pumpWidget(const MaterialApp(
    home: Scaffold(
      body: ImmersiveAmbientBackdrop(
        accentColor: 0xFF204060,
        trackKey: 'fallback',
      ),
    ),
  ));
  expect(find.byKey(const Key('immersive-ambient-backdrop')), findsOneWidget);
  expect(tester.takeException(), isNull);
});
```

- [ ] **Step 2: Run failing test**

Run: `flutter test test/presentation/immersive_ambient_backdrop_test.dart`

Expected: FAIL because the backdrop does not exist.

- [ ] **Step 3: Implement backdrop**

Render a `RepaintBoundary` with optional blurred `Image.memory`, two radial
gradients derived from the accent color, and a `trackKey` fade layer. Disable
drift when reduced motion is active.

- [ ] **Step 4: Verify**

Run: `flutter test test/presentation/immersive_ambient_backdrop_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/widgets/immersive_ambient_backdrop.dart test/presentation/immersive_ambient_backdrop_test.dart
git commit -m "feat: add immersive ambient backdrop"
```

---

### Task 5: Glass controls and keyboard behavior

**Files:**
- Create: `lib/presentation/widgets/immersive_controls.dart`
- Modify: `test/presentation/immersive_lyrics_page_test.dart`

**Interfaces:**
- Consumes: `MusicController`.
- Produces: `ImmersiveControls({required MusicController music, required bool chromeVisible})`.
- Produces Escape, Space, ArrowLeft, ArrowRight shortcuts on the page.

- [ ] **Step 1: Add failing keyboard test**

```dart
testWidgets('space toggles playback in immersive mode', (tester) async {
  final harness = _Harness();
  addTearDown(harness.controller.dispose);
  await tester.pumpWidget(harness.build(const SizedBox.shrink()));
  await runAsync(tester, harness.playMerged);
  harness.controller.toggleImmersive();
  await tester.pumpWidget(harness.build(const ImmersiveLyricsPage()));
  await tester.sendKeyEvent(LogicalKeyboardKey.space);
  await tester.pumpAndSettle();
  expect(harness.controller.playback.status, PlaybackStatus.paused);
});
```

- [ ] **Step 2: Run failing test**

Run: `flutter test test/presentation/immersive_lyrics_page_test.dart`

Expected: FAIL because Space is not bound.

- [ ] **Step 3: Implement controls**

Create a translucent control bar with a progress line and transport controls.
Bind Space, ArrowLeft (`position - 5s`), and ArrowRight (`position + 5s`).
Track pointer activity with `MouseRegion` and fade chrome after three seconds.

- [ ] **Step 4: Verify**

Run: `flutter test test/presentation/immersive_lyrics_page_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/widgets/immersive_controls.dart test/presentation/immersive_lyrics_page_test.dart
git commit -m "feat: add immersive controls and shortcuts"
```

---

### Task 6: Integrate the immersive page

**Files:**
- Modify: `lib/presentation/immersive_lyrics_page.dart`
- Modify: `test/presentation/immersive_lyrics_page_test.dart`

**Interfaces:**
- Consumes: `ImmersiveAmbientBackdrop`, `FocusLyricsViewport`, `ImmersiveControls`.
- Produces: the complete immersive stage with click-to-seek and responsive chrome.

- [ ] **Step 1: Add failing integration assertions**

```dart
expect(find.byKey(const Key('immersive-ambient-backdrop')), findsOneWidget);
expect(find.byKey(const Key('focus-lyrics-viewport')), findsOneWidget);
expect(find.byKey(const Key('immersive-controls')), findsOneWidget);
```

- [ ] **Step 2: Run and confirm missing widgets**

Run: `flutter test test/presentation/immersive_lyrics_page_test.dart`

Expected: FAIL because the old page still uses `AlbumBackdrop` and `LyricsView`.

- [ ] **Step 3: Compose the new page**

Pass `music.coverBytesFor(track)` to the backdrop, `music.lyrics` and
`playback.position` to the viewport, and `music.seekTo` for lyric clicks.
Keep Escape and Android back behavior.

- [ ] **Step 4: Run targeted tests**

Run: `flutter test test/presentation/immersive_lyrics_page_test.dart test/presentation/focus_lyrics_viewport_test.dart test/presentation/immersive_ambient_backdrop_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/immersive_lyrics_page.dart test/presentation/immersive_lyrics_page_test.dart
git commit -m "feat: rebuild immersive lyrics experience"
```

---

### Task 7: Full verification and visual evidence

**Files:**
- Modify: `docs/screenshots/app-immersive-playing.png`
- Modify: `TOOLCHAIN.md`

**Interfaces:**
- Consumes: complete feature.
- Produces: verified Windows visual evidence and updated validation count.

- [ ] **Step 1: Run static analysis**

Run: `flutter analyze`

Expected: `No issues found!`

- [ ] **Step 2: Run all tests**

Run: `flutter test`

Expected: all tests pass; update the recorded count in `TOOLCHAIN.md`.

- [ ] **Step 3: Build Windows**

Set `PATH` to include `D:\dshws\.toolchains` for NuGet, then run:

```powershell
flutter build windows --debug
```

Expected: `Built build\windows\x64\runner\Debug\music_client.exe`.

- [ ] **Step 4: Capture immersive evidence**

Build a dedicated preview with `DSH_AUTO_SEARCH`, `DSH_AUTO_PLAY_FIRST`, and
`DSH_AUTO_IMMERSIVE`, capture the active lyric state, and replace
`docs/screenshots/app-immersive-playing.png`.

- [ ] **Step 5: Commit**

```bash
git add docs/screenshots/app-immersive-playing.png TOOLCHAIN.md
git commit -m "test: verify immersive lyrics experience"
```
