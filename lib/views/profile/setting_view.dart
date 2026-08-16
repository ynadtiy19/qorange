import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../network/api_exception.dart';
import '../../network/http_client.dart';
import '../../services/language_service.dart';

/// 🌟 MVC 控制器：专门负责用户实名认证与安全邮箱数据的加载、校验与安全提交
class SettingController extends GetxController {
  final RxString realName = ''.obs;
  final RxString realPhone = ''.obs;
  final RxString email = ''.obs; // 🌟 响应式邮箱属性
  final RxBool isLoading = true.obs;
  final RxBool isSubmitting = false.obs;

  @override
  void onInit() {
    super.onInit();
    loadVerificationData();
  }

  /// 🌟 自动反查回显用户当前在云端的实名与邮箱绑定信息
  Future<void> loadVerificationData() async {
    isLoading.value = true;
    try {
      final res = await HttpClient.instance.get<Map<String, dynamic>>('/api-users/verification');
      if (res.respCode == 0 && res.datas != null) {
        realName.value = res.datas!['real_name']?.toString() ?? '';
        realPhone.value = res.datas!['real_phone']?.toString() ?? '';
        email.value = res.datas!['email']?.toString() ?? '';
      }
    } catch (_) {
      isLoading.value = false;
    } finally {
      isLoading.value = false;
    }
  }

  /// 🌟 安全保存用户实名、手机号与联系邮箱修改
  Future<bool> saveVerificationData(String name, String phone, String emailText) async {
    if (isSubmitting.value) return false;
    isSubmitting.value = true;

    try {
      final res = await HttpClient.instance.put<Map<String, dynamic>>(
        '/api-users/verification',
        data: {
          'real_name': name,
          'real_phone': phone,
          'email': emailText,
        },
      );

      isSubmitting.value = false;

      if (res.respCode == 0) {
        Fluttertoast.showToast(msg: 'save_success'.tr);
        realName.value = name;
        realPhone.value = phone;
        email.value = emailText;
        return true;
      } else {
        Fluttertoast.showToast(msg: res.respMsg);
        return false;
      }
    } catch (e) {
      isSubmitting.value = false;
      if (e is ApiException) {
        Fluttertoast.showToast(msg: e.message);
      } else {
        Fluttertoast.showToast(msg: 'save_fail'.tr);
      }
      return false;
    }
  }
}

/// 🌟 曜石曜绿高颜值系统设置与安全视图 🌟
class SettingView extends StatelessWidget {
  const SettingView({super.key});

  void _showLanguageSelector(BuildContext context, Color primaryColor) {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'select_language'.tr,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),
            ...LanguageService.to.supportedLanguages.map((lang) {
              final String nameKey = lang['nameKey'];
              final Locale locale = lang['locale'];
              final bool isSelected = LanguageService.to.currentLocale.languageCode == locale.languageCode;

              return ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                tileColor: isSelected ? primaryColor.withOpacity(0.08) : null,
                title: Text(
                  nameKey.tr,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? primaryColor : Colors.black87,
                  ),
                ),
                trailing: isSelected ? Icon(Icons.check_circle_rounded, color: primaryColor) : null,
                onTap: () {
                  LanguageService.to.changeLanguage(locale);
                  Get.back();
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(SettingController());
    final Color primaryColor = const Color.fromRGBO(44, 123, 109, 1.0); // 柔绿
    final Color obsidianBg = const Color(0xFF0F172A); // 曜石黑

    final TextEditingController nameC = TextEditingController();
    final TextEditingController phoneC = TextEditingController();
    final TextEditingController emailC = TextEditingController();

    // 🌟 通过监听回显自动填入
    ever(controller.realName, (name) => nameC.text = name);
    ever(controller.realPhone, (phone) => phoneC.text = phone);
    ever(controller.email, (em) => emailC.text = em);

    // 首次载入补位
    nameC.text = controller.realName.value;
    phoneC.text = controller.realPhone.value;
    emailC.text = controller.email.value;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('settings'.tr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Get.back(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black, size: 20),
        ),
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return Center(child: CircularProgressIndicator(color: primaryColor, strokeWidth: 2));
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 0. 多语言切换入口大卡片
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 10, offset: const Offset(0, 4))
                  ],
                ),
                child: ListTile(
                  leading: HugeIcon(icon: HugeIcons.strokeRoundedGlobal, color: primaryColor, size: 20.0),
                  title: Text('language_setting'.tr, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    LanguageService.to.supportedLanguages.firstWhere(
                          (l) => (l['locale'] as Locale).languageCode == LanguageService.to.currentLocale.languageCode,
                      orElse: () => LanguageService.to.supportedLanguages.first,
                    )['nameKey'].toString().tr,
                    style: const TextStyle(fontSize: 12, color: Colors.black45),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.black38),
                  onTap: () => _showLanguageSelector(context, primaryColor),
                ),
              ),
              const SizedBox(height: 24),

              // 1. 系统级实名认证与安全邮箱告知大卡
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: primaryColor.withOpacity(0.15)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    HugeIcon(icon: HugeIcons.strokeRoundedShieldUser, color: primaryColor, size: 20.0),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('realname_binding'.tr, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: primaryColor)),
                          const SizedBox(height: 6),
                          Text(
                            'realname_notice'.tr,
                            style: const TextStyle(fontSize: 11, color: Colors.black54, height: 1.5),
                          )
                        ],
                      ),
                    )
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // 2. 实名录入
              Text('alipay_real_name'.tr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black54)),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 10, offset: const Offset(0, 4))
                  ],
                ),
                child: TextField(
                  controller: nameC,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'alipay_real_name_hint'.tr,
                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                    prefixIcon: Icon(Icons.person_pin_rounded, color: primaryColor, size: 18),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // 3. 收款手机号录入
              Text('alipay_phone'.tr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black54)),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 10, offset: const Offset(0, 4))
                  ],
                ),
                child: TextField(
                  controller: phoneC,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(11),
                  ],
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'alipay_phone_hint'.tr,
                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                    prefixIcon: Icon(Icons.phone_iphone_rounded, color: primaryColor, size: 18),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // 🌟 4. 新增：安全联系邮箱录入（用于接收邮件分享与系统通知）
              Text('security_email'.tr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black54)), // 或 '联系与接收邮箱'
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 10, offset: const Offset(0, 4))
                  ],
                ),
                child: TextField(
                  controller: emailC,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'security_email_hint'.tr, // 或 '输入邮箱以开启站内好友邮件分享接收'
                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                    prefixIcon: Icon(Icons.alternate_email_rounded, color: primaryColor, size: 18),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 40),

              // 5. 一键提交核销绑定
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: controller.isSubmitting.value
                      ? null
                      : () async {
                    final name = nameC.text.trim();
                    final phone = phoneC.text.trim();
                    final emailText = emailC.text.trim();

                    if (name.isEmpty || phone.isEmpty) {
                      Fluttertoast.showToast(msg: 'fill_name_and_phone'.tr);
                      return;
                    }

                    // 邮箱非空时进行格式强校验
                    if (emailText.isNotEmpty) {
                      final emailRegExp = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
                      if (!emailRegExp.hasMatch(emailText)) {
                        Fluttertoast.showToast(msg: 'invalid_email_format'.tr); // 或 '邮箱格式不正确'
                        return;
                      }
                    }

                    final success = await controller.saveVerificationData(name, phone, emailText);
                    if (success) {
                      Get.back();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: obsidianBg,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: controller.isSubmitting.value
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('save'.tr, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}