import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_client/domain/lyrics.dart';
import 'package:music_client/presentation/widgets/focus_lyrics_viewport.dart';

LyricTimeline _timeline() => LyricTimeline([
  const LyricLine(text: '第一行', start: Duration.zero, end: Duration(seconds: 2)),
  const LyricLine(
    text: '第二行',
    start: Duration(seconds: 2),
    end: Duration(seconds: 4),
  ),
  const LyricLine(
    text: '第三行',
    start: Duration(seconds: 4),
    end: Duration(seconds: 6),
  ),
]);

Widget _host(Widget child, {bool reduceMotion = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('focused line follows position and invokes seek', (tester) async {
    Duration? sought;
    await tester.pumpWidget(
      _host(
        FocusLyricsViewport(
          timeline: _timeline(),
          position: const Duration(seconds: 2, milliseconds: 500),
          onSeek: (value) => sought = value,
        ),
      ),
    );

    expect(find.byKey(const Key('focused-lyric-line-1')), findsOneWidget);
    expect(find.byKey(const Key('focused-lyric-line-0')), findsNothing);

    await tester.tap(find.byKey(const Key('focused-lyric-line-1')));
    expect(sought, const Duration(seconds: 2));
  });

  testWidgets('shows breathing dots during a long instrumental gap', (
    tester,
  ) async {
    final timeline = LyricTimeline([
      const LyricLine(
        text: '第一行',
        start: Duration.zero,
        end: Duration(seconds: 1),
      ),
      const LyricLine(
        text: '第二行',
        start: Duration(seconds: 8),
        end: Duration(seconds: 10),
      ),
    ]);
    await tester.pumpWidget(
      _host(
        FocusLyricsViewport(
          timeline: timeline,
          position: const Duration(seconds: 4),
          onSeek: (_) {},
        ),
      ),
    );

    expect(find.byKey(const Key('lyrics-breathing')), findsOneWidget);
  });

  testWidgets('reduced motion keeps a stable focus transition', (tester) async {
    await tester.pumpWidget(
      _host(
        FocusLyricsViewport(
          timeline: _timeline(),
          position: const Duration(seconds: 3),
          onSeek: (_) {},
        ),
        reduceMotion: true,
      ),
    );

    expect(find.byKey(const Key('focused-lyric-transition')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
