import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';

import '../../network/auth_state_manager.dart';
import '../../network/http_client.dart';
import '../../network/secure_storage_manager.dart';
import '../../user_controller.dart';
import '../main/main_nav_view.dart';

class ProfileController extends GetxController {
  // 退出登录加载状态
  RxBool isLoggingOut = false.obs;

  /// 退出登录逻辑
  Future<void> logout() async {
    try {
      isLoggingOut.value = true;

      // 1. 获取当前缓存的 token 与 refresh_token
      final token = await SecureStorageManager.instance.getAccessToken() ?? '';
      final refreshToken =
          await SecureStorageManager.instance.getRefreshToken() ?? '';

      // 2. 调用后端退出登录接口
      // 采用 try-catch 包裹，即使由于断网等原因后端接口报错，本地退出逻辑仍然会执行，防止本地死锁
      try {
        await HttpClient.instance.post(
          '/api-users/login/logout',
          data: {"token": token, "refresh_token": refreshToken},
        );
      } catch (e) {
        print("后端退出接口调用异常(已忽略): $e");
      }

      // 3. 清除安全存储中的Token
      await AuthStateManager.instance.logout();

      // 4. 清除 UserController 用户信息全局缓存
      await UserController.to.clearUserInfo();

      Fluttertoast.showToast(msg: "已退出登录");

      // 5. 路由处理：回到主页
      Get.offAll(() => const MainNavView(), transition: Transition.fadeIn);
    } catch (e) {
      Fluttertoast.showToast(msg: "退出登录失败，请重试");
    } finally {
      isLoggingOut.value = false;
    }
  }
}