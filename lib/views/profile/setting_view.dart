import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../network/api_exception.dart';
import '../../network/http_client.dart';
import '../../services/language_service.dart';

/// 🌟 MVC 控制器：专门负责实名认证数据的加载、校验与安全提交 [2]
class SettingController extends GetxController {
  final RxString realName = ''.obs;
  final RxString realPhone = ''.obs;
  final RxBool isLoading = true.obs;
  final RxBool isSubmitting = false.obs;

  @override
  void onInit() {
    super.onInit();
    loadVerificationData();
  }

  /// 🌟 自动反查回显学者当前在云端的实名认证信息 [2]
  Future<void> loadVerificationData() async {
    isLoading.value = true;
    try {
      final res = await HttpClient.instance.get<Map<String, dynamic>>('/api-users/verification');
      if (res.respCode == 0 && res.datas != null) {
        realName.value = res.datas!['real_name']?.toString() ?? '';
        realPhone.value = res.datas!['real_phone']?.toString() ?? '';
      }
    } catch (_) {
      isLoading.value = false;
    } finally {
      isLoading.value = false;
    }
  }

  /// 🌟 安全保存学者实名及手机号修改 [2]
  Future<bool> saveVerificationData(String name, String phone) async {
    if (isSubmitting.value) return false;
    isSubmitting.value = true;

    try {
      final res = await HttpClient.instance.put<Map<String, dynamic>>(
        '/api-users/verification',
        data: {
          'real_name': name,
          'real_phone': phone,
        },
      );

      isSubmitting.value = false;

      if (res.respCode == 0) {
        Fluttertoast.showToast(msg: 'save_success'.tr);
        realName.value = name;
        realPhone.value = phone;
        return true;
      } else {
        Fluttertoast.showToast(msg: res.respMsg ?? 'save_fail'.tr);
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

    // 🌟 通过监听回显自动填入
    ever(controller.realName, (name) => nameC.text = name);
    ever(controller.realPhone, (phone) => phoneC.text = phone);

    // 首次载入补位
    nameC.text = controller.realName.value;
    phoneC.text = controller.realPhone.value;

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

              // 1. 系统级实名认证安全告知大卡
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
                    FilteringTextInputFormatter.digitsOnly, // 强限制纯数字录入
                    LengthLimitingTextInputFormatter(11), // 强限制 11 位长度
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
              const SizedBox(height: 40),

              // 4. 一键提交核销绑定
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: controller.isSubmitting.value
                      ? null
                      : () async {
                    final name = nameC.text.trim();
                    final phone = phoneC.text.trim();

                    if (name.isEmpty || phone.isEmpty) {
                      Fluttertoast.showToast(msg: 'fill_name_and_phone'.tr);
                      return;
                    }

                    final success = await controller.saveVerificationData(name, phone);
                    if (success) {
                      Get.back(); // 🌟 保存成功，自动退回主页，then(_) 闭包会自动静默刷新
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