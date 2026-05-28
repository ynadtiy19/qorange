import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:get/get.dart';
import 'package:qorange/services/frontend_chat_service.dart';
import 'package:qorange/theme.dart';
import 'package:qorange/user_controller.dart';

import 'network/auth_state_manager.dart';
import 'views/splash/splash_view.dart';

void main() async {
  // 确保 Flutter 绑定初始化，这是执行原生相关操作的前提
  WidgetsFlutterBinding.ensureInitialized();

  if (kReleaseMode) {
    // 将 debugPrint 重写为空函数，这样所有的 debugPrint 都会被静音
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

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
      title: '青橙',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      fallbackLocale: const Locale('zh', 'CN'),
      supportedLocales: [
        Locale('zh', 'CN'), // 支持简体中文（中国）
        Locale('en', 'US'), // 支持英语
      ],
      localizationsDelegates: const [
        FlutterQuillLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        // Material 组件的本地化（控制 Android 风格的复制/粘贴菜单）
        GlobalWidgetsLocalizations.delegate,
        // 基础 Widget 的文字方向等本地化
        GlobalCupertinoLocalizations.delegate,
        // Cupertino 组件的本地化（控制 iOS 风格的复制/粘贴菜单）
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
