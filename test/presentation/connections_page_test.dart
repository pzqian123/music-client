import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_client/app.dart';
import 'package:music_client/application/music_controller.dart';
import 'package:music_client/application/playback_clock.dart';
import 'package:music_client/domain/models.dart';
import 'package:music_client/platform/official_handoff.dart';
import 'package:music_client/platform/secure_credentials.dart';
import 'package:music_client/presentation/connections_page.dart';
import 'package:music_client/platform/web_player_engine.dart';
import 'package:music_client/platform/web_playback_engine.dart';
import 'package:music_client/presentation/web_player_ui.dart';
import 'package:music_client/presentation/widgets/hidden_web_player.dart';
import 'package:music_client/providers/fake_netease_provider.dart';
import 'package:music_client/providers/fake_spotify_provider.dart';
import 'package:provider/provider.dart';

/// 连接页需要的最小假桥接（不触碰真实 WebView）。
class _FakeBridge implements WebPlayerBridge {
  @override
  bool get isAttached => false;

  @override
  Future<WebPlayerState> readState() async => const WebPlayerState.empty();

  @override
  Future<void> toggle() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> openTrack(WebPlayerTarget target, String id) async {}

  @override
  Future<String> clickOfficialPlay() async => 'no-play-button';

  @override
  Future<String> runScript(String source) async => '';

  @override
  Future<List<OfficialSearchResult>> searchNetease(
    String query, {
    Duration wait = const Duration(milliseconds: 0),
  }) async =>
      const [];
}

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
  _Harness({bool connected = false}) {
    spotify = FakeSpotifyProvider(initiallyConnected: connected);
    netease = FakeNeteaseProvider(initiallyConnected: connected);
    handoff = FakeHandoff();
    credentials = InMemoryCredentials();
    controller = MusicController(
      providers: [spotify, netease],
      clock: ManualClock(),
      credentials: credentials,
      handoff: handoff,
    );
  }

  late final FakeSpotifyProvider spotify;
  late final FakeNeteaseProvider netease;
  late final FakeHandoff handoff;
  late final InMemoryCredentials credentials;
  late final MusicController controller;

  Widget build() {
    final engine = WebPlaybackEngine(bridge: _FakeBridge());
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<MusicController>.value(value: controller),
        ChangeNotifierProvider<WebPlayerUi>.value(value: WebPlayerUi()),
        ChangeNotifierProvider<WebPlaybackEngine>.value(value: engine),
      ],
      child: MaterialApp(
        theme: buildTheme(),
        home: const Scaffold(body: ConnectionsPage()),
      ),
    );
  }
}

void main() {
  testWidgets('初始显示未连接与能力清单', (tester) async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);

    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(find.byKey(const Key('provider-state-spotify')))
          .data,
      '未连接',
    );
    expect(find.text('客户端内播放'), findsNWidgets(2));
  });

  testWidgets('连接后状态变为已连接', (tester) async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);

    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('connect-spotify')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(find.byKey(const Key('provider-state-spotify')))
          .data,
      '已连接',
    );
    expect(find.textContaining('已连接（演示）'), findsOneWidget);
  });

  testWidgets('断开后状态回到未连接并清除凭证', (tester) async {
    final harness = _Harness(connected: true);
    addTearDown(harness.controller.dispose);
    await harness.credentials.write('spotify', 'demo-token');

    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('disconnect-spotify')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(find.byKey(const Key('provider-state-spotify')))
          .data,
      '未连接',
    );
    expect(await harness.credentials.read('spotify'), isNull);
  });

  testWidgets('页面不包含任何密码输入框', (tester) async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);

    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('无当前曲目时官方 App 按钮禁用', (tester) async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);

    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    final button = tester.widget<TextButton>(
      find.byKey(const Key('handoff-spotify')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('有当前曲目时官方 App 按钮调用跳转', (tester) async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);

    await tester.pumpWidget(harness.build());
    await runAsync(tester, () async {
      await harness.controller.searchFor('夜空');
      final track = harness.controller.search.results.firstWhere(
        (item) => item.sources.length == 2,
      );
      await harness.controller.selectTrack(
        track,
        service: MusicService.spotify,
      );
    });
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('handoff-spotify')));
    await tester.pumpAndSettle();

    expect(harness.handoff.last, isNotNull);
    expect(harness.handoff.last!.toString(), contains('spotify:track:'));
  });
}
