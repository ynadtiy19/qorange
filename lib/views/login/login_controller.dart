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
  final TextEditingController nicknameController = TextEditingController(); // 注册时使用

  final FocusNode usernameFocusNode = FocusNode();
  final FocusNode passwordFocusNode = FocusNode();
  final FocusNode nicknameFocusNode = FocusNode();

  final RxBool isUsernameValid = false.obs;
  final RxBool isPasswordValid = false.obs;
  final RxBool isNicknameValid = false.obs;

  final RxBool isRegisterMode = false.obs; // 是否为注册模式
  final RxBool isLoading = false.obs;

  // 🌟 新增：本地已加密保存的账户列表观察者
  final RxList<Map<String, String>> savedCredentials = <Map<String, String>>[].obs;

  final Color themeColor = const Color.fromRGBO(44, 123, 109, 1.0);

  @override
  void onInit() {
    super.onInit();
    // 显式添加事件监听，避免匿名闭包垃圾回收失效
    usernameController.addListener(_validateUsername);
    passwordController.addListener(_validatePassword);
    nicknameController.addListener(_validateNickname);

    // 🌟 新增：页面初始化时自动读取本地保存的账号
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

  /// 🌟 新增：载入本地已加密保存的账户列表
  Future<void> _loadSavedCredentials() async {
    final list = await SecureStorageManager.instance.getSavedCredentials();
    savedCredentials.assignAll(list);
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

        // 🌟 核心改进：检查当前输入的密码是否已经被保存在本地安全存储中
        final isAlreadySaved = savedCredentials.any(
              (item) => item['username'] == inputUsername && item['password'] == inputPassword,
        );

        isLoading.value = false;

        if (!isAlreadySaved) {
          // 如果未保存，则唤起精美的“保存密码”询问弹窗
          _showSavePasswordBottomSheet(inputUsername, inputPassword);
        } else {
          // 已保存则直接返回上层路由
          Get.back(result: true);
        }
      }
    } on ApiException catch (e) {
      isLoading.value = false;
      Fluttertoast.showToast(msg: e.message);
    } catch (e) {
      isLoading.value = false;
      Fluttertoast.showToast(msg: "登录失败，请重试");
    }
  }

  /// 🌟 新增：唤起 Edge / Keychain 风格的“保存密码”底部确认弹窗
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
              // 居中指示条
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
                  const Text(
                    "保存密码到安全存储？",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                "下次登录 青橙 时，您可以一键自动填充此账户的凭据，无需再次手动输入。",
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600, height: 1.4),
              ),
              const SizedBox(height: 20),
              // 模拟账号信息展示卡片
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
                        Text("账号", style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
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
                        Text("密码", style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                        const Spacer(),
                        const Text("••••••••", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // 按钮区域
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Get.back(); // 关闭弹窗
                        Get.back(result: true); // 返回上层
                      },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text("暂不保存", style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        await SecureStorageManager.instance.saveCredential(username, password);
                        await _loadSavedCredentials(); // 刷新本地列表
                        Fluttertoast.showToast(msg: "密码已安全保存");
                        Get.back(); // 关闭弹窗
                        Get.back(result: true); // 返回上层
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: themeColor,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text("保存密码", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      isDismissible: false, // 强制用户选择，保证业务闭环
    );
  }

  /// 🌟 新增：唤起 Edge / 1Password 风格的“选择已保存账户一键填充”面板
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
                  const Text(
                    "使用已保存的账号登录",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                "点击账号即可一键自动填充并更新校验状态",
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 16),
              // 已存凭据列表
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
                            await _loadSavedCredentials(); // 刷新
                            if (savedCredentials.isEmpty) {
                              Get.back(); // 如果删空了则直接关闭面板
                            }
                          },
                        ),
                        onTap: () {
                          // 一键自动填充并强制触发校验器逻辑更新状态
                          usernameController.text = name;
                          passwordController.text = pwd;
                          _validateUsername();
                          _validatePassword();

                          // 收起焦点，避免软键盘顶起
                          usernameFocusNode.unfocus();
                          passwordFocusNode.unfocus();

                          Get.back(); // 关闭填充面板
                          Fluttertoast.showToast(msg: "已自动填充凭据");
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