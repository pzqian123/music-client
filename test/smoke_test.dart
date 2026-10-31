import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_client/app.dart';
import 'package:music_client/application/music_controller.dart';
import 'package:music_client/application/playback_clock.dart';
import 'package:music_client/platform/official_handoff.dart';
import 'package:music_client/platform/secure_credentials.dart';
import 'package:music_client/providers/fake_netease_provider.dart';
import 'package:music_client/providers/fake_spotify_provider.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('应用壳显示三个导航入口', (tester) async {
    await tester.pumpWidget(const MusicApp());
    await tester.pumpAndSettle();

    expect(find.text('搜索'), findsWidgets);
    expect(find.text('播放'), findsWidgets);
    expect(find.text('连接'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('注入控制器时使用注入实例', (tester) async {
    final controller = MusicController(
      providers: [FakeSpotifyProvider(), FakeNeteaseProvider()],
      clock: ManualClock(),
      credentials: InMemoryCredentials(),
      handoff: FakeHandoff(),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(MusicApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('演示数据'), findsOneWidget);
  });
}
