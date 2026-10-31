import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_client/app.dart';
import 'package:music_client/application/music_controller.dart';
import 'package:music_client/application/playback_clock.dart';
import 'package:music_client/domain/models.dart';
import 'package:music_client/platform/official_handoff.dart';
import 'package:music_client/platform/secure_credentials.dart';
import 'package:music_client/presentation/player_page.dart';
import 'package:music_client/providers/fake_netease_provider.dart';
import 'package:music_client/providers/fake_spotify_provider.dart';
import 'package:provider/provider.dart';

/// 测试体内直接 await 带 Future.delayed 的调用会卡住假时钟，
/// 必须一边 pump 一边等待。
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
    spotify = FakeSpotifyProvider();
    netease = FakeNeteaseProvider();
    clock = ManualClock();
    controller = MusicController(
      providers: [spotify, netease],
      clock: clock,
      credentials: InMemoryCredentials(),
      handoff: FakeHandoff(),
    );
  }

  late final FakeSpotifyProvider spotify;
  late final FakeNeteaseProvider netease;
  late final ManualClock clock;
  late final MusicController controller;

  Widget build() {
    return ChangeNotifierProvider<MusicController>.value(
      value: controller,
      child: MaterialApp(
        theme: buildTheme(),
        home: const Scaffold(body: PlayerPage()),
      ),
    );
  }

  Future<void> playMerged({MusicService? service}) async {
    await controller.searchFor('夜空');
    final track = controller.search.results.firstWhere(
      (item) => item.sources.length == 2,
    );
    await controller.selectTrack(track, service: service);
  }

  Future<void> playSingle(String query) async {
    await controller.searchFor(query);
    await controller.selectTrack(controller.search.results.first);
  }
}

void main() {
  testWidgets('无当前曲目时显示空状态', (tester) async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);

    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('player-empty')), findsOneWidget);
  });

  testWidgets('宽屏显示封面、标题与歌词列表', (tester) async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);

    await tester.pumpWidget(harness.build());
    await runAsync(tester, () => harness.playMerged());
    await tester.pumpAndSettle();

    expect(find.text('夜空中最亮的星'), findsWidgets);
    expect(find.byKey(const Key('lyrics-list')), findsOneWidget);
    expect(find.byKey(const Key('lyric-line-0')), findsOneWidget);
  });

  testWidgets('时钟推进后当前行高亮', (tester) async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);

    await tester.pumpWidget(harness.build());
    await runAsync(tester, () => harness.playMerged());
    await tester.pumpAndSettle();

    harness.clock.emit(const Duration(milliseconds: 5000));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final active = tester.widget<AnimatedOpacity>(
      find.byKey(const Key('lyric-line-1')),
    );
    final previous = tester.widget<AnimatedOpacity>(
      find.byKey(const Key('lyric-line-0')),
    );
    expect(active.opacity, 1.0);
    expect(previous.opacity, 0.45);
  });

  testWidgets('点击播放按钮切换暂停状态', (tester) async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);

    await tester.pumpWidget(harness.build());
    await runAsync(tester, () => harness.playMerged());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('transport-play-pause')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(harness.controller.playback.status.name, 'paused');
  });

  testWidgets('不可播放时显示原因与官方 App 回退', (tester) async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);

    await tester.pumpWidget(harness.build());
    await runAsync(
      tester,
      () => harness.playMerged(service: MusicService.spotify),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('playback-blocked-message')), findsOneWidget);
    expect(find.byKey(const Key('open-official-app')), findsOneWidget);
  });

  testWidgets('无歌词时显示暂无歌词', (tester) async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);

    await tester.pumpWidget(harness.build());
    await runAsync(tester, () => harness.playSingle('稻香'));
    await tester.pumpAndSettle();

    expect(find.text('暂无歌词'), findsOneWidget);
  });

  testWidgets('静态歌词显示提示', (tester) async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);

    await tester.pumpWidget(harness.build());
    await runAsync(tester, () => harness.playSingle('平凡之路'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('lyrics-static')), findsOneWidget);
    expect(find.text('暂无时间戳歌词'), findsOneWidget);
  });

  testWidgets('窄屏布局不溢出', (tester) async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);
    tester.view.physicalSize = const Size(360 * 3, 720 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness.build());
    await runAsync(tester, () => harness.playMerged());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
