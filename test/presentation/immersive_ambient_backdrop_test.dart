import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_client/presentation/widgets/immersive_ambient_backdrop.dart';

void main() {
  testWidgets('renders without artwork using accent color fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ImmersiveAmbientBackdrop(
            accentColor: 0xFF204060,
            trackKey: 'fallback',
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('immersive-ambient-backdrop')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
