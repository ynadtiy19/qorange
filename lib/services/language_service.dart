// lib/services/language_service.dart
//
// 多语言状态服务：负责读取/持久化用户选择的语言，并驱动 GetX 全局刷新。
// Language service: loads, persists and applies the user's locale choice.

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageService extends GetxService {
  static LanguageService get to => Get.find<LanguageService>();

  /// 本地持久化 key
  static const String _storageKey = 'app_language_code';

  /// 默认语言（与 GetMaterialApp 的 fallbackLocale 保持一致）
  static const Locale defaultLocale = Locale('zh', 'CN');

  /// 应用支持的语言清单。
  /// nameKey 为词条 key，交由界面调用 .tr 呈现（语言名称本身各语言下保持母语写法）。
  final List<Map<String, dynamic>> supportedLanguages = const [
    {'nameKey': 'lang_zh_cn', 'locale': Locale('zh', 'CN')},
    {'nameKey': 'lang_en_us', 'locale': Locale('en', 'US')},
    {'nameKey': 'lang_es_es', 'locale': Locale('es', 'ES')},
    {'nameKey': 'lang_fr_fr', 'locale': Locale('fr', 'FR')},
    {'nameKey': 'lang_it_it', 'locale': Locale('it', 'IT')},
  ];

  final Rx<Locale> _currentLocale = defaultLocale.obs;

  /// 当前生效的语言
  Locale get currentLocale => _currentLocale.value;

  /// 供 Obx 监听的响应式语言对象
  Rx<Locale> get rxLocale => _currentLocale;

  /// 启动时载入本地已保存的语言选择
  Future<LanguageService> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_storageKey);
      if (saved != null && saved.isNotEmpty) {
        final parsed = _parseLocale(saved);
        if (parsed != null) {
          _currentLocale.value = parsed;
        }
      } else {
        // 首次启动：优先跟随系统语言，系统语言不受支持时回落到默认语言
        final systemLocale = Get.deviceLocale;
        if (systemLocale != null) {
          final matched = _matchSupported(systemLocale);
          if (matched != null) _currentLocale.value = matched;
        }
      }
    } catch (_) {
      _currentLocale.value = defaultLocale;
    }
    return this;
  }

  /// 切换语言：立即刷新界面并持久化保存
  Future<void> changeLanguage(Locale locale) async {
    final target = _matchSupported(locale) ?? defaultLocale;
    if (target.languageCode == _currentLocale.value.languageCode &&
        target.countryCode == _currentLocale.value.countryCode) {
      return;
    }

    _currentLocale.value = target;
    Get.updateLocale(target);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, '${target.languageCode}_${target.countryCode}');
    } catch (_) {
      // 持久化失败不影响本次切换效果
    }
  }

  /// 取得当前语言在语言清单中的展示词条 key
  String get currentLanguageNameKey {
    final match = supportedLanguages.firstWhere(
      (item) => (item['locale'] as Locale).languageCode == _currentLocale.value.languageCode,
      orElse: () => supportedLanguages.first,
    );
    return match['nameKey'] as String;
  }

  /// 将 "zh_CN" 形式的字符串还原为 Locale
  Locale? _parseLocale(String raw) {
    final parts = raw.split('_');
    if (parts.isEmpty || parts.first.isEmpty) return null;
    final candidate = parts.length >= 2 ? Locale(parts[0], parts[1]) : Locale(parts[0]);
    return _matchSupported(candidate);
  }

  /// 仅接受受支持的语言，按 languageCode 匹配
  Locale? _matchSupported(Locale locale) {
    for (final item in supportedLanguages) {
      final supported = item['locale'] as Locale;
      if (supported.languageCode == locale.languageCode) return supported;
    }
    return null;
  }
}
