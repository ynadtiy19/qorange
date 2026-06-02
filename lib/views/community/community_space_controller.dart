import 'dart:convert';
import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../network/http_client.dart';
import '../../network/api_exception.dart';
import '../../services/epay_client_service.dart';
import 'community_model.dart';

class CommunitySpaceController extends GetxController
    with GetSingleTickerProviderStateMixin {
  final String communityId;
  CommunitySpaceController({required this.communityId});

  late TabController tabController;

  // 状态流
  final Rx<CommunityModel?> community = Rx<CommunityModel?>(null);
  final RxBool isLoadingDetails = true.obs;
  final RxList<dynamic> posts = <dynamic>[].obs;
  final RxBool isLoadingPosts = true.obs;
  final RxBool hasPostsPermission = true.obs; // 🌟 区分是否触发付费墙限制阻断

  final Color primaryColor = const Color.fromRGBO(44, 123, 109, 1.0);

  @override
  void onInit() {
    super.onInit();
    tabController = TabController(length: 2, vsync: this);
    loadSpaceDetails();
  }

  @override
  void onClose() {
    tabController.dispose();
    super.onClose();
  }

  Future<void> loadSpaceDetails() async {
    isLoadingDetails.value = true;
    try {
      final res = await HttpClient.instance.get<Map<String, dynamic>>('/api-communities/$communityId');
      if (res.respCode == 0 && res.datas != null) {
        community.value = CommunityModel.fromJson(res.datas!);

        // 🌟 详情拉取通过后，根据是否为群员，尝试加载内部发帖（若非付费会员会静默 403 触发防火墙）
        loadSpacePosts();
      }
    } catch (_) {
      isLoadingDetails.value = false;
    } finally {
      isLoadingDetails.value = false;
    }
  }

  Future<void> loadSpacePosts() async {
    isLoadingPosts.value = true;
    try {
      final res = await HttpClient.instance.get<List<dynamic>>('/api-communities/$communityId/posts');
      if (res.respCode == 0 && res.datas != null) {
        posts.assignAll(res.datas!);
        hasPostsPermission.value = true;
      }
    } catch (e) {
      if (e is ApiException && e.statusCode == 403) {
        // 🌟 触发防火墙拦截：表明这是付费群且该用户尚未加入，阻断内容读取并拉起 Paywall
        hasPostsPermission.value = false;
      }
    } finally {
      isLoadingPosts.value = false;
    }
  }

  /// 🌟 极速购买付费群入群特权全闭环（整合 App 统一代签）
  Future<void> purchaseJoinWorkflow(BuildContext context) async {
    final item = community.value;
    if (item == null) return;

    Get.dialog(
      const Center(child: CircularProgressIndicator(color: Color.fromRGBO(44, 123, 109, 1.0))),
      barrierDismissible: false,
    );

    try {
      // 1. 系统后台创建挂起订单（锁定金额并关联 goodsType 为 group 社群）
      final orderRes = await HttpClient.instance.post<Map<String, dynamic>>(
        '/api-pay/create_order',
        data: {
          'goodsId': item.id,
          'goodsType': 'group',
          'payType': 'alipay',
        },
      );

      if (orderRes.respCode != 0 || orderRes.datas == null) {
        Get.back();
        Fluttertoast.showToast(msg: orderRes.respMsg ?? '加入社群订单创建失败');
        return;
      }

      final outTradeNo = orderRes.datas!['outTradeNo'];
      final amount = orderRes.datas!['amount'];
      final goodsName = orderRes.datas!['goodsName'];

      // 2. 客户端 POST 直连易支付下单
      final epay = EpayClientService();
      final epayCreateRes = await epay.createPaymentDirectly(params: {
        'method': 'jump',
        'device': 'mobile',
        'type': 'alipay',
        'out_trade_no': outTradeNo,
        'name': goodsName,
        'money': amount,
      });

      Get.back();

      if (epayCreateRes['code'] == 0) {
        final payUrl = epayCreateRes['pay_info'] ?? epayCreateRes['pay_url'];
        if (payUrl != null) {
          // 3. 调起系统外部浏览器物理拉起支付
          await _launchExternalBrowser(payUrl.toString());
          _showPaymentCheckDialog(context, outTradeNo);
        }
      } else {
        Fluttertoast.showToast(msg: epayCreateRes['msg'] ?? '通道异常');
      }

    } catch (e) {
      Get.back();
      Fluttertoast.showToast(msg: '请求异常: $e');
    }
  }

  Future<void> _launchExternalBrowser(String urlString) async {
    final url = Uri.parse(urlString);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  void _showPaymentCheckDialog(BuildContext context, String outTradeNo) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('社群付款确认'),
          content: const Text('请您在新打开的浏览器页面中完成社群购买支付，支付完成后点击下方确认加入。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _verifyJoinSuccessOnBackend(outTradeNo);
              },
              style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
              child: const Text('确认已加入', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  /// 🌟 服务端非对称签名发货核验
  Future<void> _verifyJoinSuccessOnBackend(String outTradeNo) async {
    Get.dialog(
      const Center(child: CircularProgressIndicator(color: Color.fromRGBO(44, 123, 109, 1.0))),
      barrierDismissible: false,
    );

    try {
      final epay = EpayClientService();
      final realEpayData = await epay.queryOrderDirectly(outTradeNo: outTradeNo);

      final verifyRes = await HttpClient.instance.post<Map<String, dynamic>>(
        '/api-pay/verify_payment',
        data: {'epay_response': realEpayData},
      );

      Get.back();

      if (verifyRes.respCode == 0) {
        Fluttertoast.showToast(msg: "🎉 恭喜您，已成功解锁并加入付费社群空间！");
        loadSpaceDetails(); // 重新拉取空间状态，解除防火墙限制
      } else {
        Fluttertoast.showToast(msg: verifyRes.respMsg ?? "支付单据验证失败");
      }
    } catch (e) {
      Get.back();
      Fluttertoast.showToast(msg: "通信异常: $e");
    }
  }
}