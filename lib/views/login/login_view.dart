import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';

import 'login_controller.dart';

class LoginView extends StatelessWidget {
  const LoginView({super.key});

  @override
  Widget build(BuildContext context) {
    const themeColor = Color.fromRGBO(44, 123, 109, 1.0);

    return GetBuilder<LoginController>(
      init: LoginController(),
      dispose: (state) {
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

                      // 账号输入框（正常点击聚焦打字，无多余弹窗拦截）
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: TextField(
                          controller: controller.usernameController,
                          focusNode: controller.usernameFocusNode,
                          keyboardType: TextInputType.text,
                          decoration: InputDecoration(
                            hintText: 'phone_or_email'.tr,
                            counterText: "",
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 16,
                            ),
                            // 🌟 仅点击右侧钥匙图标才唤起保存的密码面板
                            suffixIcon: (controller.savedCredentials.isNotEmpty &&
                                !controller.isRegisterMode.value)
                                ? GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                controller.usernameFocusNode.unfocus();
                                controller.passwordFocusNode.unfocus();
                                controller.showSavedAccountsBottomSheet();
                              },
                              child: const Padding(
                                padding: EdgeInsets.only(right: 14.0),
                                child: HugeIcon(
                                  icon: HugeIcons.strokeRoundedKey01,
                                  color: Color.fromRGBO(44, 123, 109, 1.0),
                                  size: 20,
                                ),
                              ),
                            )
                                : null,
                            suffixIconConstraints: const BoxConstraints(
                              minWidth: 44,
                              minHeight: 44,
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

                      // 注册模式下显示昵称输入框
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

                      // 切换登录/注册模式
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