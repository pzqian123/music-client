import 'package:flutter_test/flutter_test.dart';
import 'package:music_client/platform/secure_credentials.dart';

void main() {
  test('InMemoryCredentials 写入、读取、删除', () async {
    final store = InMemoryCredentials();

    expect(await store.read('spotify'), isNull);

    await store.write('spotify', 'demo-value');
    expect(await store.read('spotify'), 'demo-value');

    await store.write('spotify', 'updated');
    expect(await store.read('spotify'), 'updated');

    await store.delete('spotify');
    expect(await store.read('spotify'), isNull);
  });

  test('不同键互不影响', () async {
    final store = InMemoryCredentials();
    await store.write('spotify', 'a');
    await store.write('netease', 'b');

    await store.delete('spotify');

    expect(await store.read('spotify'), isNull);
    expect(await store.read('netease'), 'b');
  });
}
