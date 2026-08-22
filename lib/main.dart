import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:get/get.dart';
import 'package:qorange/l10n/app_translations.dart';
import 'package:qorange/services/frontend_chat_service.dart';
import 'package:qorange/services/language_service.dart';
import 'package:qorange/services/theme_service.dart';
import 'package:qorange/theme.dart';
import 'package:qorange/user_controller.dart';

import 'network/auth_state_manager.dart';
import 'views/comment/agreement_webview_page.dart';
import 'views/splash/splash_view.dart';

void main() async {
  // 确保 Flutter 绑定初始化，这是执行原生相关操作的前提
  WidgetsFlutterBinding.ensureInitialized();

  if (kReleaseMode) {
    // 将 debugPrint 重写为空函数，这样所有的 debugPrint 都会被静音
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  // 初始化多语言服务
  await Get.putAsync(() => LanguageService().init());

  // 初始化白天/黑夜主题服务（内部会同步状态栏样式）
  await Get.putAsync(() => ThemeService().init());

  Get.put(UserController());

  Get.put(FrontendChatService());

  // 强制竖屏
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // 初始化网络权限状态
  await AuthStateManager.instance.checkInitialState();


  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Obx 监听主题模式：切换白天/黑夜时整体重建 GetMaterialApp，
    // ThemeData 变化会驱动所有 Scaffold 子树重建，界面颜色即时跟随刷新
    return Obx(() => GetMaterialApp(
      title: 'Qorange',
      debugShowCheckedModeBanner: false,
      translations: AppTranslations(),
      locale: LanguageService.to.currentLocale,
      fallbackLocale: const Locale('zh', 'CN'),
      supportedLocales: const [
        Locale('zh', 'CN'), // 简体中文
        Locale('en', 'US'), // 英语
        Locale('es', 'ES'), // 西班牙语
        Locale('fr', 'FR'), // 法语
        Locale('it', 'IT'), // 意大利语
      ],
      localizationsDelegates: const [
        FlutterQuillLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.lightTheme.copyWith(
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: AppColors.primary,
          selectionColor: AppColors.primary.withOpacity(0.3),
          selectionHandleColor: AppColors.primary,
        ),
      ),
      darkTheme: AppTheme.darkTheme.copyWith(
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: AppColors.primary,
          selectionColor: AppColors.primary.withOpacity(0.3),
          selectionHandleColor: AppColors.primary,
        ),
      ),
      themeMode: ThemeService.to.themeMode.value,
      // 首次加载进入启动页
      home: const SplashView(),

      getPages: [
        GetPage(
          name: '/agreement_webview',
          page: () => const AgreementWebViewPage(),
          transition: Transition.cupertino, // 带来丝滑的 iOS 侧滑进场特效
        ),
      ],
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(
            textScaler: const TextScaler.linear(1.0),
          ),
          child: child!,
        );
      },
    ));
  }
}

