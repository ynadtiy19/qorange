import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';

import 'login_controller.dart';

// 🌟 核心改进：改回 StatelessWidget，并使用自承载的 GetBuilder 来统一管理注入与销毁
class LoginView extends StatelessWidget {
  const LoginView({super.key});

  @override
  Widget build(BuildContext context) {
    final themeColor = const Color.fromRGBO(44, 123, 109, 1.0);

    return GetBuilder<LoginController>(
      init: LoginController(), // 🌟 挂载第一步：确保控制器立刻被注入，100% 解决 "not found" 问题
      dispose: (state) {
        // 🌟 卸载最后一步：页面退出时，物理销毁控制器，杜绝内存残留和软键盘失控问题
        Get.delete<LoginController>();
      },
      builder: (controller) {
        return Scaffold(
          backgroundColor: Colors.white,
          resizeToAvoidBottomInset: false,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const HugeIcon(
                icon: HugeIcons.strokeRoundedCancel01,
                color: Colors.black,
              ),
              onPressed: () => Get.back(result: false),
            ),
          ),
          body: Obx(
                () => IgnorePointer(
              ignoring: controller.isLoading.value,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      // 动态切换标题
                      Text(
                        controller.isRegisterMode.value ? 'app_name'.tr : 'welcome_login'.tr,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        controller.isRegisterMode.value ? 'enter_account'.tr : 'enter_password'.tr,
                        style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 40),

                      // 账号输入框
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: TextField(
                          controller: controller.usernameController,
                          focusNode: controller.usernameFocusNode,
                          keyboardType: TextInputType.text,
                          // 🌟 核心设计：如果本地安全存储有账号，点击输入框时拦截物理键盘，直接唤起 Edge 风格填充面板
                          onTap: () {
                            if (controller.savedCredentials.isNotEmpty &&
                                controller.usernameController.text.isEmpty &&
                                !controller.isRegisterMode.value) {
                              // 收起输入框物理焦点防止闪现物理键盘
                              controller.usernameFocusNode.unfocus();
                              // 唤起自动填充面板
                              controller.showSavedAccountsBottomSheet();
                            }
                          },
                          decoration: InputDecoration(
                            hintText: 'phone_or_email'.tr,
                            counterText: "",
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 16,
                            ),
                            // 🌟 核心设计：如果本地有已存凭据且非注册模式下，右侧显示科技感“钥匙安全锁”图标
                            suffixIcon: (controller.savedCredentials.isNotEmpty &&
                                !controller.isRegisterMode.value)
                                ? GestureDetector(
                              onTap: () {
                                controller.usernameFocusNode.unfocus();
                                controller.showSavedAccountsBottomSheet();
                              },
                              child: const Padding(
                                padding: EdgeInsets.only(right: 12.0),
                                child: HugeIcon(
                                  icon: HugeIcons.strokeRoundedKey01,
                                  color: Color.fromRGBO(44, 123, 109, 1.0),
                                  size: 20,
                                ),
                              ),
                            )
                                : null,
                            suffixIconConstraints: const BoxConstraints(
                              minWidth: 40,
                              minHeight: 40,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // 密码输入框
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: TextField(
                          controller: controller.passwordController,
                          focusNode: controller.passwordFocusNode,
                          obscureText: true,
                          decoration: InputDecoration(
                            hintText: 'password'.tr,
                            counterText: "",
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 16,
                            ),
                          ),
                        ),
                      ),

                      // 注册模式下显示“昵称”输入框
                      if (controller.isRegisterMode.value) ...[
                        const SizedBox(height: 16),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: TextField(
                            controller: controller.nicknameController,
                            focusNode: controller.nicknameFocusNode,
                            keyboardType: TextInputType.text,
                            decoration: InputDecoration(
                              hintText: 'nickname'.tr,
                              counterText: "",
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 16,
                              ),
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 32),

                      // 登录 / 注册 按钮
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: (controller.isUsernameValid.value &&
                              controller.isPasswordValid.value &&
                              (!controller.isRegisterMode.value || controller.isNicknameValid.value))
                              ? controller.submit
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: themeColor,
                            disabledBackgroundColor: Colors.grey.shade200,
                            foregroundColor: Colors.white,
                            disabledForegroundColor: Colors.grey.shade400,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                          child: controller.isLoading.value
                              ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                              : Text(
                            controller.isRegisterMode.value ? 'no_account'.tr : 'login_btn'.tr,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // 登录/注册模式快速切换
                      Center(
                        child: TextButton(
                          onPressed: () {
                            controller.toggleRegisterMode();
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: themeColor,
                          ),
                          child: Text(
                            controller.isRegisterMode.value ? 'login_btn'.tr : 'no_account'.tr,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}