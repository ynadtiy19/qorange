import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';

import '../../user_controller.dart';
import '../../network/api_exception.dart';
import '../../network/auth_state_manager.dart';
import '../../network/http_client.dart';
import '../../network/secure_storage_manager.dart';

class LoginController extends GetxController {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController nicknameController = TextEditingController(); // 注册时使用

  final FocusNode usernameFocusNode = FocusNode();
  final FocusNode passwordFocusNode = FocusNode();
  final FocusNode nicknameFocusNode = FocusNode();

  final RxBool isUsernameValid = false.obs;
  final RxBool isPasswordValid = false.obs;
  final RxBool isNicknameValid = false.obs;

  final RxBool isRegisterMode = false.obs; // 是否为注册模式
  final RxBool isLoading = false.obs;

  @override
  void onInit() {
    super.onInit();
    // 显式添加事件监听，避免匿名闭包垃圾回收失效
    usernameController.addListener(_validateUsername);
    passwordController.addListener(_validatePassword);
    nicknameController.addListener(_validateNickname);
  }

  void _validateUsername() {
    isUsernameValid.value = usernameController.text.trim().length >= 3;
  }

  void _validatePassword() {
    isPasswordValid.value = passwordController.text.trim().length >= 6;
  }

  void _validateNickname() {
    isNicknameValid.value = nicknameController.text.trim().isNotEmpty;
  }

  /// 动态切换登录和注册模式，并安全清空已输入的内容防止脏状态残留
  void toggleRegisterMode() {
    isRegisterMode.value = !isRegisterMode.value;
    passwordController.clear();
    nicknameController.clear();
    passwordFocusNode.unfocus();
    nicknameFocusNode.unfocus();
  }

  /// 登录或注册提交逻辑
  Future<void> submit() async {
    if (isRegisterMode.value) {
      await _register();
    } else {
      await _login();
    }
  }

  /// 账号密码登录
  Future<void> _login() async {
    if (!isUsernameValid.value || !isPasswordValid.value) {
      Fluttertoast.showToast(msg: "账号或密码长度不足");
      return;
    }

    try {
      isLoading.value = true;

      final response = await HttpClient.instance.post<Map<String, dynamic>>(
        '/api-users/login',
        data: {
          'username': usernameController.text.trim(),
          'password': passwordController.text.trim(),
        },
      );

      final datas = response.datas;
      if (datas != null) {
        final token = datas['token'];
        final refreshToken = datas['refresh_token'];

        // 1. 保存 Token 至安全存储
        await SecureStorageManager.instance.saveAccessToken(token);
        await SecureStorageManager.instance.saveRefreshToken(refreshToken);

        // 2. 保存非涉密信息到 UserController 缓存
        await UserController.to.saveUserInfo(datas);

        // 3. 更新全局 Auth 状态
        AuthStateManager.instance.onLoginSuccess();

        Fluttertoast.showToast(msg: "登录成功");

        // 🌟 核心机制升级：向上一层路由返回 true，通知导航控制器用户已完成登录行为
        Get.back(result: true);
      }
    } on ApiException catch (e) {
      Fluttertoast.showToast(msg: e.message);
    } catch (e) {
      Fluttertoast.showToast(msg: "登录失败，请重试");
    } finally {
      isLoading.value = false;
    }
  }

  /// 账号密码注册
  Future<void> _register() async {
    if (!isUsernameValid.value || !isPasswordValid.value || !isNicknameValid.value) {
      Fluttertoast.showToast(msg: "请完善注册信息");
      return;
    }

    try {
      isLoading.value = true;

      final response = await HttpClient.instance.post<Map<String, dynamic>>(
        '/api-users/register',
        data: {
          'username': usernameController.text.trim(),
          'password': passwordController.text.trim(),
          'nickname': nicknameController.text.trim(),
          'avatar': "https://api.multiavatar.com/${usernameController.text.trim()}.png", // 生成默认头像
        },
      );

      if (response.respCode == 0) {
        Fluttertoast.showToast(msg: "注册成功，请登录");
        // 注册成功自动切回登录状态
        isRegisterMode.value = false;
        passwordController.clear();
      }
    } on ApiException catch (e) {
      Fluttertoast.showToast(msg: e.message);
    } catch (e) {
      Fluttertoast.showToast(msg: "注册失败，请重新尝试");
    } finally {
      isLoading.value = false;
    }
  }

  @override
  void onClose() {
    // 销毁监听器
    usernameController.removeListener(_validateUsername);
    passwordController.removeListener(_validatePassword);
    nicknameController.removeListener(_validateNickname);

    // 释放资源，断开软键盘事件和节点内存泄漏
    usernameController.dispose();
    passwordController.dispose();
    nicknameController.dispose();
    usernameFocusNode.dispose();
    passwordFocusNode.dispose();
    nicknameFocusNode.dispose();
    super.onClose();
  }
}