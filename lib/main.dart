import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:get/get.dart';
import 'package:qorange/l10n/app_translations.dart';
import 'package:qorange/services/frontend_chat_service.dart';
import 'package:qorange/services/language_service.dart';
import 'package:qorange/theme.dart';
import 'package:qorange/user_controller.dart';
import 'package:reels_video_player/reels_video_player.dart';

import 'network/auth_state_manager.dart';
import 'views/comment/agreement_webview_page.dart';
import 'views/splash/splash_view.dart';

void main() async {
  // 确保 Flutter 绑定初始化，这是执行原生相关操作的前提
  WidgetsFlutterBinding.ensureInitialized();

  // 🌟 必须在 runApp 之前初始化本地视频缓存代理引擎
  await ReelsCacheManager.init();

  if (kReleaseMode) {
    // 将 debugPrint 重写为空函数，这样所有的 debugPrint 都会被静音
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  // 初始化多语言服务
  await Get.putAsync(() => LanguageService().init());

  Get.put(UserController());

  Get.put(FrontendChatService());

  // 强制竖屏
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // 配置沉浸式状态栏 (透明背景，暗色图标)
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );


  // 初始化网络权限状态
  await AuthStateManager.instance.checkInitialState();


  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
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
      theme: AppTheme.theme.copyWith(
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: Color.fromRGBO(44, 123, 109, 1.0),
          selectionColor: Color.fromRGBO(44, 123, 109, 0.3),
          selectionHandleColor: Color.fromRGBO(44, 123, 109, 1.0),
        ),
      ),
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
    );
  }
}

