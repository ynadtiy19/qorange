import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 提供安全高效的加密解密本地缓存
class SecureStorageManager {
  SecureStorageManager._internal();

  static final SecureStorageManager _instance =
      SecureStorageManager._internal();

  static SecureStorageManager get instance => _instance;

  // 配置 Android 强制使用 EncryptedSharedPreferences (更安全)
  AndroidOptions _getAndroidOptions() =>
      const AndroidOptions(encryptedSharedPreferences: true);

  // 配置 iOS / macOS Keychain 策略
  IOSOptions _getIOSOptions() =>
      const IOSOptions(accessibility: KeychainAccessibility.first_unlock);

  late final FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: _getAndroidOptions(),
    iOptions: _getIOSOptions(),
  );

  static const String _keyAccessToken = 'access_token';
  static const String _keyRefreshToken = 'refresh_token';
  static const String _keyUserId = 'user_id';

  /// 保存 Access Token
  Future<void> saveAccessToken(String token) async {
    await _storage.write(key: _keyAccessToken, value: token);
  }

  /// 获取 Access Token
  Future<String?> getAccessToken() async {
    return await _storage.read(key: _keyAccessToken);
  }

  /// 保存 Refresh Token
  Future<void> saveRefreshToken(String token) async {
    await _storage.write(key: _keyRefreshToken, value: token);
  }

  /// 获取 Refresh Token
  Future<String?> getRefreshToken() async {
    return await _storage.read(key: _keyRefreshToken);
  }

  /// 保存普通字符串
  Future<void> saveString(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  /// 获取普通字符串
  Future<String?> getString(String key) async {
    return await _storage.read(key: key);
  }

  /// 删除某一项
  Future<void> delete(String key) async {
    await _storage.delete(key: key);
  }

  /// 清空所有数据 (退出登录时使用)
  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
