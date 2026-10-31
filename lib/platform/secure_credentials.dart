/// 平台能力抽象：凭证安全存储与官方 App 跳转。
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class SecureCredentials {
  Future<void> write(String key, String value);
  Future<String?> read(String key);
  Future<void> delete(String key);
}

/// 测试与演示用实现。
class InMemoryCredentials implements SecureCredentials {
  final Map<String, String> _store = {};

  @override
  Future<void> write(String key, String value) async => _store[key] = value;

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> delete(String key) async => _store.remove(key);
}

/// 生产实现：走操作系统安全存储。不得把内容写日志。
class FlutterSecureStorageCredentials implements SecureCredentials {
  FlutterSecureStorageCredentials([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
