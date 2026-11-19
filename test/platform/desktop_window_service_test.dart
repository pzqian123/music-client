import 'package:flutter_test/flutter_test.dart';
import 'package:music_client/platform/desktop_window_service.dart';

void main() {
  test('fake records window operations', () async {
    final service = FakeDesktopWindowService();

    await service.minimize();
    await service.toggleMaximize();
    await service.startDragging();
    await service.close();

    expect(service.calls, [
      'minimize',
      'toggleMaximize',
      'startDragging',
      'close',
    ]);
    expect(service.maximized, isTrue);
  });
}
