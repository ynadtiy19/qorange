import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../views/login/login_view.dart';
import 'secure_storage_manager.dart';

/// 用户的三种模式：游客、已登录、登录过期
enum AuthMode { guest, loggedIn, expired }

/// 负责维护全局登录状态以及路由跳转扩展
class AuthStateManager {
  // 单例模式
  AuthStateManager._internal();

  static final AuthStateManager _instance = AuthStateManager._internal();

  static AuthStateManager get instance => _instance;

  /// 当前用户状态监听器
  final ValueNotifier<AuthMode> authModeNotifier = ValueNotifier(
    AuthMode.guest,
  );

  AuthMode get currentMode => authModeNotifier.value;

  /// 初始化应用时检查状态
  Future<void> checkInitialState() async {
    final token = await SecureStorageManager.instance.getAccessToken();
    if (token != null && token.isNotEmpty) {
      authModeNotifier.value = AuthMode.loggedIn;
    } else {
      authModeNotifier.value = AuthMode.guest;
    }
  }

  /// 成功登录后调用
  void onLoginSuccess() {
    authModeNotifier.value = AuthMode.loggedIn;
  }

  /// Token 彻底过期或刷新失败时调用 (触发路由跳转)
  Future<void> onTokenExpired() async {
    authModeNotifier.value = AuthMode.expired;
    await SecureStorageManager.instance.clearAll();

    debugPrint("【AuthStateManager】检测到登录过期，执行 GetX 路由跳转到登录页。");

    // 使用 Get.offAll 清空页面栈，防止用户按返回键返回 [2]
    Get.offAll(
          () => const LoginView(),
      transition: Transition.rightToLeftWithFade,
    );
  }

  /// 用户主动退出登录
  Future<void> logout() async {
    await SecureStorageManager.instance.clearAll();
    authModeNotifier.value = AuthMode.guest;

    debugPrint("【AuthStateManager】用户登出完毕，跳转至登录页。");

    Get.offAll(
          () => const LoginView(),
      transition: Transition.rightToLeftWithFade,
    );
  }
}
