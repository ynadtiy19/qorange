import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../network/api_exception.dart';
import '../../network/http_client.dart';

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
        Fluttertoast.showToast(msg: "🎉 实名安全信息更新成功");
        realName.value = name;
        realPhone.value = phone;
        return true;
      } else {
        Fluttertoast.showToast(msg: res.respMsg ?? "保存失败");
        return false;
      }
    } catch (e) {
      isSubmitting.value = false;
      if (e is ApiException) {
        Fluttertoast.showToast(msg: e.message);
      } else {
        Fluttertoast.showToast(msg: "修改资料失败，请重试");
      }
      return false;
    }
  }
}

/// 🌟 曜石曜绿高颜值实名修改安全视图 🌟
class SettingView extends StatelessWidget {
  const SettingView({super.key});

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
        title: const Text('实名安全绑定', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87)),
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
                          Text('平台实名对账安全防线', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: primaryColor)),
                          const SizedBox(height: 6),
                          const Text(
                            '为了保障平台与创作者之间提现对账的绝对准确，手艺人请在此绑定您的支付宝实名信息 [INDEX: 1]。此信息仅用于财务核销平账审计使用，不对任何其他第三方学者透露 [INDEX: 2]！',
                            style: TextStyle(fontSize: 11, color: Colors.black54, height: 1.5),
                          )
                        ],
                      ),
                    )
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // 2. 实名录入
              const Text('支付宝真实实名', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black54)),
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
                    hintText: "请输入您的支付宝真实姓名",
                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                    prefixIcon: Icon(Icons.person_pin_rounded, color: primaryColor, size: 18),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // 3. 收款手机号录入
              const Text('支付宝收款绑定手机号', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black54)),
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
                    hintText: "请输入绑定的11位支付宝手机号",
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
                      Fluttertoast.showToast(msg: "请将姓名和手机号数据填写完整");
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
                      : const Text('保存修改并一键加密绑定', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}