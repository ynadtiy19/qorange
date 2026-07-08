import 'dart:convert';
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

  // 🌟 新增：本地加密保存的账号密码列表 Key
  static const String _keySavedCredentials = 'saved_credentials_list';

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

  /// 🌟 新增：读取所有已保存的账户密码凭据
  Future<List<Map<String, String>>> getSavedCredentials() async {
    try {
      final jsonStr = await _storage.read(key: _keySavedCredentials);
      if (jsonStr == null || jsonStr.isEmpty) return [];
      final List<dynamic> decoded = jsonDecode(jsonStr);
      return decoded.map((item) => Map<String, String>.from(item)).toList();
    } catch (e) {
      return [];
    }
  }

  /// 🌟 新增：保存单条账户密码凭据（若存在则更新）
  Future<void> saveCredential(String username, String password) async {
    try {
      final list = await getSavedCredentials();
      // 避免重复，先删除已有同名账户
      list.removeWhere((item) => item['username'] == username);
      list.add({'username': username, 'password': password});
      await _storage.write(key: _keySavedCredentials, value: jsonEncode(list));
    } catch (_) {}
  }

  /// 🌟 新增：删除单条账户密码凭据
  Future<void> deleteCredential(String username) async {
    try {
      final list = await getSavedCredentials();
      list.removeWhere((item) => item['username'] == username);
      await _storage.write(key: _keySavedCredentials, value: jsonEncode(list));
    } catch (_) {}
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