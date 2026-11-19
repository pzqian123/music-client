import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_client/app.dart';
import 'package:music_client/application/music_controller.dart';
import 'package:music_client/application/playback_clock.dart';
import 'package:music_client/platform/official_handoff.dart';
import 'package:music_client/platform/secure_credentials.dart';
import 'package:music_client/presentation/search_page.dart';
import 'package:music_client/providers/fake_netease_provider.dart';
import 'package:music_client/providers/fake_spotify_provider.dart';
import 'package:provider/provider.dart';

/// 搜索期间存在不定长进度条，不能用 pumpAndSettle，改为定量推进。
Future<void> pumpSearch(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _Harness {
  _Harness() {
    spotify = FakeSpotifyProvider();
    netease = FakeNeteaseProvider();
    controller = MusicController(
      providers: [spotify, netease],
      clock: ManualClock(),
      credentials: InMemoryCredentials(),
      handoff: FakeHandoff(),
    );
  }

  late final FakeSpotifyProvider spotify;
  late final FakeNeteaseProvider netease;
  late final MusicController controller;

  Widget build() {
    return ChangeNotifierProvider<MusicController>.value(
      value: controller,
      child: MaterialApp(
        theme: buildTheme(),
        home: const Scaffold(body: SearchPage()),
      ),
    );
  }
}

void main() {
  testWidgets('初始显示搜索提示', (tester) async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);

    await tester.pumpWidget(harness.build());
    await tester.pump();

    expect(find.textContaining('输入关键词'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('提交关键词后显示合并结果与来源', (tester) async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);

    await tester.pumpWidget(harness.build());
    await tester.enterText(find.byKey(const Key('search-field')), '夜空');
    await tester.tap(find.byKey(const Key('search-submit')));
    await pumpSearch(tester);

    expect(find.text('夜空中最亮的星'), findsWidgets);
    final chips = tester.widgetList(find.byType(ActionChip)).length;
    expect(chips, greaterThanOrEqualTo(3)); // 合并曲 2 个来源 + Live 曲 1 个
  });

  testWidgets('点击来源 chip 会按该来源播放', (tester) async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);

    await tester.pumpWidget(harness.build());
    await tester.enterText(find.byKey(const Key('search-field')), '夜空');
    await tester.tap(find.byKey(const Key('search-submit')));
    await pumpSearch(tester);

    final merged = harness.controller.search.results.firstWhere(
      (track) => track.sources.length == 2,
    );
    final spotifySource = merged.sources.firstWhere(
      (source) => source.service.name == 'spotify',
    );
    await tester.tap(
      find.byKey(
        Key('source-${merged.id}-spotify-${spotifySource.providerTrackId}'),
      ),
    );
    await pumpSearch(tester);

    expect(harness.controller.playback.activeService?.name, 'spotify');
    expect(harness.controller.playback.status.name, 'blocked');
  });

  testWidgets('单个服务失败时显示局部错误与另一方结果', (tester) async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);
    harness.spotify.shouldFail = true;

    await tester.pumpWidget(harness.build());
    await tester.enterText(find.byKey(const Key('search-field')), '晴天');
    await tester.tap(find.byKey(const Key('search-submit')));
    await pumpSearch(tester);

    expect(find.text('重试'), findsOneWidget);
    expect(find.text('晴天'), findsWidgets);
  });

  testWidgets('无结果时显示空状态', (tester) async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);

    await tester.pumpWidget(harness.build());
    await tester.enterText(find.byKey(const Key('search-field')), 'zzzzzz');
    await tester.tap(find.byKey(const Key('search-submit')));
    await pumpSearch(tester);

    expect(find.textContaining('没有找到结果'), findsOneWidget);
  });

  testWidgets('窄屏下不出现布局溢出', (tester) async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);
    tester.view.physicalSize = const Size(360 * 3, 720 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness.build());
    await tester.enterText(find.byKey(const Key('search-field')), '夜空');
    await tester.tap(find.byKey(const Key('search-submit')));
    await pumpSearch(tester);

    expect(tester.takeException(), isNull);
  });
}
