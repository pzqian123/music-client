import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_client/app.dart';
import 'package:music_client/application/music_controller.dart';
import 'package:music_client/application/playback_clock.dart';
import 'package:music_client/platform/official_handoff.dart';
import 'package:music_client/platform/secure_credentials.dart';
import 'package:music_client/presentation/immersive_lyrics_page.dart';
import 'package:music_client/presentation/player_page.dart';
import 'package:music_client/providers/fake_netease_provider.dart';
import 'package:music_client/providers/fake_spotify_provider.dart';
import 'package:provider/provider.dart';

Future<void> runAsync(WidgetTester tester, Future<void> Function() action) async {
  var done = false;
  Object? error;
  StackTrace? stackTrace;
  action().then(
    (_) => done = true,
    onError: (Object e, StackTrace s) {
      error = e;
      stackTrace = s;
      done = true;
    },
  );
  for (var i = 0; i < 60 && !done; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  if (error != null) {
    Error.throwWithStackTrace(error!, stackTrace!);
  }
  expect(done, isTrue, reason: '异步操作未在预期时间内完成');
}

class _Harness {
  _Harness() {
    controller = MusicController(
      providers: [FakeSpotifyProvider(), FakeNeteaseProvider()],
      clock: ManualClock(),
      credentials: InMemoryCredentials(),
      handoff: FakeHandoff(),
    );
  }

  late final MusicController controller;

  Widget build(Widget child) {
    return ChangeNotifierProvider<MusicController>.value(
      value: controller,
      child: MaterialApp(
        theme: buildTheme(),
        home: Scaffold(body: child),
      ),
    );
  }

  Future<void> playMerged() async {
    await controller.searchFor('夜空');
    final track = controller.search.results.firstWhere(
      (item) => item.sources.length == 2,
    );
    await controller.selectTrack(track);
  }
}

void main() {
  testWidgets('从播放页进入沉浸模式并保留播放位置', (tester) async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);

    await tester.pumpWidget(harness.build(const PlayerPage()));
    await runAsync(tester, harness.playMerged);
    await tester.pumpAndSettle();
    final positionBefore = harness.controller.playback.position;

    await tester.tap(find.byKey(const Key('enter-immersive')));
    await tester.pumpAndSettle();

    expect(harness.controller.viewMode, ViewMode.immersive);
    expect(harness.controller.playback.position, positionBefore);
  });

  testWidgets('沉浸页显示歌词并可返回分栏视图', (tester) async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);

    await tester.pumpWidget(harness.build(const SizedBox.shrink()));
    await runAsync(tester, harness.playMerged);
    harness.controller.toggleImmersive();

    await tester.pumpWidget(harness.build(const ImmersiveLyricsPage()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('immersive-lyrics')), findsOneWidget);
    expect(find.text('夜空中最亮的星'), findsWidgets);

    await tester.tap(find.byKey(const Key('exit-immersive')));
    await tester.pumpAndSettle();

    expect(harness.controller.viewMode, ViewMode.split);
  });

  testWidgets('Esc 退出沉浸模式', (tester) async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);

    await tester.pumpWidget(harness.build(const SizedBox.shrink()));
    await runAsync(tester, harness.playMerged);
    harness.controller.toggleImmersive();

    await tester.pumpWidget(harness.build(const ImmersiveLyricsPage()));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(harness.controller.viewMode, ViewMode.split);
  });

  testWidgets('沉浸页在没有歌词时也可稳定渲染', (tester) async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);

    await tester.pumpWidget(harness.build(const SizedBox.shrink()));
    await runAsync(tester, harness.playMerged);
    harness.controller.toggleImmersive();

    await tester.pumpWidget(harness.build(const ImmersiveLyricsPage()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
