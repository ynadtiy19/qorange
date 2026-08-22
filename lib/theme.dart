import 'package:flutter/material.dart';

import 'package:qorange/services/theme_service.dart';

/// 全局语义化颜色令牌 (Semantic color tokens)
///
/// 所有界面颜色都应引用这些令牌而不是写死色值：
/// * 白天主题 —— 白色基调，暖橙品牌色点缀（替代原先的绿色主调）
/// * 黑夜主题 —— 深石板色基调，亮橙品牌色保证对比度
///
/// 切换主题时，根部的 Obx 会重建 GetMaterialApp，ThemeData 变化会驱动
/// 所有 Scaffold 子树整体重建，因此各处的令牌取值会即时刷新。
class AppColors {
  AppColors._();

  static bool get isDark => ThemeService.to.isDark;

  // ───────────── 表面 / Surfaces ─────────────
  /// 页面大背景：白天纯白，黑夜深石板
  static Color get background => isDark ? const Color(0xFF0F172A) : Colors.white;

  /// 卡片 / 弹层表面
  static Color get surface => isDark ? const Color(0xFF1E293B) : Colors.white;

  /// 次级填充（输入框、轻底色块）
  static Color get surfaceAlt => isDark ? const Color(0xFF27334E) : const Color(0xFFF8FAFC);

  /// 分割线
  static Color get divider => isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

  /// 描边
  static Color get border => isDark ? const Color(0xFF475569) : const Color(0xFFE2E8F0);

  // ───────────── 文字 / Text ─────────────
  static Color get textPrimary => isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B);
  static Color get textSecondary => isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569);
  static Color get textHint => isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8);

  // ───────────── 品牌 / Brand ─────────────
  /// 品牌主色：白天暖橙（Qorange 橙），黑夜亮橙
  static Color get primary => isDark ? const Color(0xFFFB923C) : const Color(0xFFE8590C);

  /// 品牌辅助色
  static Color get primarySoft => isDark ? const Color(0xFFFB923C) : const Color(0xFFF97316);

  /// 我方聊天气泡底色
  static Color get bubbleOwn => primary;

  /// 对方聊天气泡底色
  static Color get bubbleOther => surface;
}

/// 应用主题 (Day / Night)
class AppTheme {
  AppTheme._();

  /// 白天主题：纯白基调 + 暖橙点缀
  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE8590C),
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          centerTitle: true,
          iconTheme: IconThemeData(color: Color(0xFF1E293B)),
          titleTextStyle: TextStyle(
            color: Color(0xFF1E293B),
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
        dialogTheme: const DialogTheme(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.white,
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: Color(0xFFE8590C),
        ),
      );

  /// 黑夜主题：深石板基调 + 亮橙点缀
  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFB923C),
          brightness: Brightness.dark,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F172A),
          elevation: 0,
          scrolledUnderElevation: 0.5,
          centerTitle: true,
          iconTheme: IconThemeData(color: Color(0xFFF8FAFC)),
          titleTextStyle: TextStyle(
            color: Color(0xFFF8FAFC),
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF27334E),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
        dialogTheme: const DialogTheme(
          backgroundColor: Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Color(0xFF1E293B),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: Color(0xFFFB923C),
        ),
      );

  /// 兼容旧引用
  static ThemeData get theme => lightTheme;
}
