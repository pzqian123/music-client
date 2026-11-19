import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_client/platform/desktop_window_service.dart';
import 'package:music_client/presentation/widgets/window_title_bar.dart';

Widget _host(Widget child, {Size size = const Size(900, 300)}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(width: size.width, height: size.height, child: child),
      ),
    ),
  );
}

void main() {
  testWidgets('window controls call their operations', (tester) async {
    final service = FakeDesktopWindowService();
    await tester.pumpWidget(_host(WindowTitleBar(windowService: service)));

    await tester.tap(find.byKey(const Key('window-minimize')));
    await tester.tap(find.byKey(const Key('window-maximize')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('window-close')));

    expect(service.calls, containsAll(['minimize', 'toggleMaximize', 'close']));
    expect(find.byIcon(Icons.filter_none_rounded), findsOneWidget);
  });

  testWidgets('title drag region starts native window dragging', (
    tester,
  ) async {
    final service = FakeDesktopWindowService();
    await tester.pumpWidget(_host(WindowTitleBar(windowService: service)));

    await tester.drag(
      find.byKey(const Key('window-drag-region')),
      const Offset(40, 0),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(service.calls, contains('startDragging'));
  });

  testWidgets('narrow title bar hides app name but keeps controls', (
    tester,
  ) async {
    final service = FakeDesktopWindowService();
    await tester.pumpWidget(
      _host(WindowTitleBar(windowService: service), size: const Size(480, 44)),
    );

    expect(find.text('音乐聚合'), findsNothing);
    expect(find.byKey(const Key('window-minimize')), findsOneWidget);
    expect(find.byKey(const Key('window-maximize')), findsOneWidget);
    expect(find.byKey(const Key('window-close')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
