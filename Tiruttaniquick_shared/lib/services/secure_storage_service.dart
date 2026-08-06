import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
    ),
  );

  // Singleton instance
  static final SecureStorageService _instance = SecureStorageService._internal();
  factory SecureStorageService() => _instance;
  SecureStorageService._internal();

  /// Write data to secure storage
  Future<void> write(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  /// Read data from secure storage
  Future<String?> read(String key) async {
    return await _storage.read(key: key);
  }

  /// Delete data from secure storage
  Future<void> delete(String key) async {
    await _storage.delete(key: key);
  }

  /// Check if a key exists in secure storage
  Future<bool> containsKey(String key) async {
    return await _storage.containsKey(key: key);
  }

  /// Clear all data in secure storage
  Future<void> clear() async {
    await _storage.deleteAll();
  }
}
