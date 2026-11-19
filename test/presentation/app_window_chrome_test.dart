import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_client/platform/desktop_window_service.dart';
import 'package:music_client/presentation/app_window_chrome.dart';
import 'package:music_client/presentation/widgets/window_title_bar.dart';

void main() {
  testWidgets('chrome reserves title height and shows child', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppWindowChrome(
          windowService: FakeDesktopWindowService(),
          child: const ColoredBox(
            key: Key('chrome-content'),
            color: Colors.black,
          ),
        ),
      ),
    );

    expect(find.text('音乐聚合'), findsOneWidget);
    expect(find.byType(WindowTitleBar), findsOneWidget);
    expect(find.byKey(const Key('chrome-content')), findsOneWidget);
    expect(
      tester.getRect(find.byType(WindowTitleBar)).height,
      closeTo(44, 0.01),
    );
  });

  testWidgets('can hide desktop chrome completely', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppWindowChrome(
          windowService: FakeDesktopWindowService(),
          showWindowControls: false,
          child: const Text('content'),
        ),
      ),
    );

    expect(find.byType(WindowTitleBar), findsNothing);
    expect(find.byKey(const Key('window-close')), findsNothing);
    expect(find.text('content'), findsOneWidget);
  });
}
