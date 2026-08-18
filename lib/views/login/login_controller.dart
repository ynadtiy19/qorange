import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../user_controller.dart';
import '../../network/api_exception.dart';
import '../../network/auth_state_manager.dart';
import '../../network/http_client.dart';
import '../../network/secure_storage_manager.dart';

class LoginController extends GetxController {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController nicknameController = TextEditingController();

  final FocusNode usernameFocusNode = FocusNode();
  final FocusNode passwordFocusNode = FocusNode();
  final FocusNode nicknameFocusNode = FocusNode();

  final RxBool isUsernameValid = false.obs;
  final RxBool isPasswordValid = false.obs;
  final RxBool isNicknameValid = false.obs;

  final RxBool isRegisterMode = false.obs;
  final RxBool isLoading = false.obs;

  final RxList<Map<String, String>> savedCredentials = <Map<String, String>>[].obs;
  final Color themeColor = const Color.fromRGBO(44, 123, 109, 1.0);

  @override
  void onInit() {
    super.onInit();
    usernameController.addListener(_validateUsername);
    passwordController.addListener(_validatePassword);
    nicknameController.addListener(_validateNickname);

    _loadSavedCredentials();
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

  Future<void> _loadSavedCredentials() async {
    final list = await SecureStorageManager.instance.getSavedCredentials();
    savedCredentials.assignAll(list);
  }

  void toggleRegisterMode() {
    isRegisterMode.value = !isRegisterMode.value;
    passwordController.clear();
    nicknameController.clear();
    passwordFocusNode.unfocus();
    nicknameFocusNode.unfocus();
  }

  Future<void> submit() async {
    if (isRegisterMode.value) {
      await _register();
    } else {
      await _login();
    }
  }

  /// 账号密码登录（严格按时钟序落地并广播全局通知）
  Future<void> _login() async {
    if (!isUsernameValid.value || !isPasswordValid.value) {
      Fluttertoast.showToast(msg: 'account_password_too_short'.tr);
      return;
    }

    final String inputUsername = usernameController.text.trim();
    final String inputPassword = passwordController.text.trim();

    try {
      isLoading.value = true;

      final response = await HttpClient.instance.post<Map<String, dynamic>>(
        '/api-users/login',
        data: {
          'username': inputUsername,
          'password': inputPassword,
        },
      );

      final datas = response.datas;
      if (datas != null) {
        final token = datas['token']?.toString() ?? '';
        final refreshToken = datas['refresh_token']?.toString() ?? '';

        // 1. 先落地 AccessToken 和 RefreshToken 到安全存储
        await SecureStorageManager.instance.saveAccessToken(token);
        await SecureStorageManager.instance.saveRefreshToken(refreshToken);

        // 2. 写入全局 UserController，触发全 App 各页面的 ever 监听
        await UserController.to.saveUserInfo(datas);

        // 3. 更新全局 Auth 状态
        AuthStateManager.instance.onLoginSuccess();

        Fluttertoast.showToast(msg: 'login_success'.tr);

        final isAlreadySaved = savedCredentials.any(
              (item) => item['username'] == inputUsername && item['password'] == inputPassword,
        );

        isLoading.value = false;

        if (!isAlreadySaved) {
          _showSavePasswordBottomSheet(inputUsername, inputPassword);
        } else {
          Get.back(result: true);
        }
      }
    } on ApiException catch (e) {
      isLoading.value = false;
      Fluttertoast.showToast(msg: e.message);
    } catch (e) {
      isLoading.value = false;
      Fluttertoast.showToast(msg: 'login_failed_retry'.tr);
    }
  }

  void _showSavePasswordBottomSheet(String username, String password) {
    Get.bottomSheet(
      Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: themeColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedAccess,
                      color: themeColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'save_password_title'.tr,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'save_password_desc'.tr,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600, height: 1.4),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text('account'.tr, style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                        const Spacer(),
                        Text(username, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.0),
                      child: Divider(height: 1),
                    ),
                    Row(
                      children: [
                        Text('password'.tr, style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                        const Spacer(),
                        const Text("••••••••", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Get.back();
                        Get.back(result: true);
                      },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text('dont_save'.tr, style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        await SecureStorageManager.instance.saveCredential(username, password);
                        await _loadSavedCredentials();
                        Fluttertoast.showToast(msg: 'password_saved'.tr);
                        Get.back();
                        Get.back(result: true);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: themeColor,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text('save_password'.tr, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      isDismissible: false,
    );
  }

  void showSavedAccountsBottomSheet() {
    if (savedCredentials.isEmpty) return;

    Get.bottomSheet(
      Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedKey01,
                    color: themeColor,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'use_saved_account'.tr,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'tap_account_autofill'.tr,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 250),
                child: Obx(
                      () => ListView.separated(
                    shrinkWrap: true,
                    itemCount: savedCredentials.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = savedCredentials[index];
                      final name = item['username'] ?? '';
                      final pwd = item['password'] ?? '';

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: themeColor.withOpacity(0.08),
                          child: HugeIcon(icon: HugeIcons.strokeRoundedUser, color: themeColor, size: 20),
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                        ),
                        subtitle: const Text("••••••••", style: TextStyle(letterSpacing: 2)),
                        trailing: IconButton(
                          icon: Icon(Icons.delete_outline, color: Colors.red.shade300, size: 20),
                          onPressed: () async {
                            await SecureStorageManager.instance.deleteCredential(name);
                            await _loadSavedCredentials();
                            if (savedCredentials.isEmpty) {
                              Get.back();
                            }
                          },
                        ),
                        onTap: () {
                          usernameController.text = name;
                          passwordController.text = pwd;
                          _validateUsername();
                          _validatePassword();

                          usernameFocusNode.unfocus();
                          passwordFocusNode.unfocus();

                          Get.back();
                          Fluttertoast.showToast(msg: 'credentials_autofilled'.tr);
                        },
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _register() async {
    if (!isUsernameValid.value || !isPasswordValid.value || !isNicknameValid.value) {
      Fluttertoast.showToast(msg: 'complete_registration_info'.tr);
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
          'avatar': "https://api.multiavatar.com/${usernameController.text.trim()}.png",
        },
      );

      if (response.respCode == 0) {
        Fluttertoast.showToast(msg: 'register_success_login'.tr);
        isRegisterMode.value = false;
        passwordController.clear();
      }
    } on ApiException catch (e) {
      Fluttertoast.showToast(msg: e.message);
    } catch (e) {
      Fluttertoast.showToast(msg: 'register_failed_retry'.tr);
    } finally {
      isLoading.value = false;
    }
  }

  @override
  void onClose() {
    usernameController.removeListener(_validateUsername);
    passwordController.removeListener(_validatePassword);
    nicknameController.removeListener(_validateNickname);

    usernameController.dispose();
    passwordController.dispose();
    nicknameController.dispose();
    usernameFocusNode.dispose();
    passwordFocusNode.dispose();
    nicknameFocusNode.dispose();
    super.onClose();
  }
}