// lib/services/theme_service.dart
//
// 白天/黑夜主题状态服务：负责读取/持久化用户选择的主题模式，并驱动全局刷新。
// Theme service: loads, persists and applies the user's light/dark theme choice.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService extends GetxService {
  static ThemeService get to => Get.find<ThemeService>();

  /// 本地持久化 key
  static const String _storageKey = 'app_theme_mode';

  /// 默认白天（白色基调）主题
  final Rx<ThemeMode> themeMode = ThemeMode.light.obs;

  /// 当前是否黑夜主题
  bool get isDark => themeMode.value == ThemeMode.dark;

  /// 供 Obx 监听的响应式主题模式
  Rx<ThemeMode> get rxThemeMode => themeMode;

  /// 启动时载入本地已保存的主题选择
  Future<ThemeService> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_storageKey);
      themeMode.value = (saved == 'dark') ? ThemeMode.dark : ThemeMode.light;
    } catch (_) {
      themeMode.value = ThemeMode.light;
    }
    _syncSystemUI();
    return this;
  }

  /// 切换主题：立即刷新界面并持久化保存
  Future<void> setMode(ThemeMode mode) async {
    if (themeMode.value == mode) return;
    themeMode.value = mode;
    _syncSystemUI();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, mode == ThemeMode.dark ? 'dark' : 'light');
    } catch (_) {
      // 持久化失败不影响本次切换效果
    }
  }

  /// 白天 <-> 黑夜 一键切换
  Future<void> toggle() async {
    await setMode(isDark ? ThemeMode.light : ThemeMode.dark);
  }

  /// 让状态栏 / 底部手势条样式跟随主题
  void _syncSystemUI() {
    SystemChrome.setSystemUIOverlayStyle(
      isDark
          ? const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.light,
              systemNavigationBarColor: Color(0xFF0F172A),
              systemNavigationBarIconBrightness: Brightness.light,
            )
          : const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.dark,
              systemNavigationBarColor: Colors.white,
              systemNavigationBarIconBrightness: Brightness.dark,
            ),
    );
  }
}
