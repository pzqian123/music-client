// 仅供视觉验证的预览入口，不参与产品入口（lib/main.dart）。
// 用法：flutter run -t tool/preview_main.dart
//      或在 web 上 ?view=immersive 查看沉浸页。
import 'package:flutter/material.dart';
import 'package:music_client/app.dart';
import 'package:music_client/application/music_controller.dart';
import 'package:music_client/application/playback_clock.dart';
import 'package:music_client/domain/models.dart';
import 'package:music_client/platform/official_handoff.dart';
import 'package:music_client/platform/secure_credentials.dart';
import 'package:music_client/presentation/immersive_lyrics_page.dart';
import 'package:music_client/presentation/player_page.dart';
import 'package:music_client/providers/fake_netease_provider.dart';
import 'package:music_client/providers/fake_spotify_provider.dart';
import 'package:provider/provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final clock = ManualClock();
  final controller = MusicController(
    providers: [FakeSpotifyProvider(), FakeNeteaseProvider()],
    clock: clock,
    credentials: InMemoryCredentials(),
    handoff: FakeHandoff(),
  );

  await controller.searchFor('夜空');
  final track = controller.search.results.firstWhere(
    (item) => item.sources.length == 2,
    orElse: () => controller.search.results.first,
  );
  await controller.selectTrack(track, service: MusicService.netease);
  clock.seek(const Duration(milliseconds: 9000));

  final immersive = Uri.base.queryParameters['view'] == 'immersive';
  if (immersive) controller.toggleImmersive();

  runApp(
    ChangeNotifierProvider<MusicController>.value(
      value: controller,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: Scaffold(
          body: immersive ? const ImmersiveLyricsPage() : const PlayerPage(),
        ),
      ),
    ),
  );
}
