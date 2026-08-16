import 'dart:convert';
import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../network/http_client.dart';
import '../../network/api_exception.dart';
import '../../services/epay_client_service.dart';
import '../../user_controller.dart';
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

  // 🌟 新增：提现与成员审批小红点状态计数
  final RxInt pendingApprovalsCount = 0.obs;

  // 🌟 新增：细颗粒度观察当前用户在该群的状态（none, active, applying, approved_to_pay） [1]
  final RxString memberStatus = 'none'.obs;

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

        // 🌟 记录当前的细颗粒度入群状态 [1]
        memberStatus.value = res.datas!['member_status']?.toString() ?? 'none';

        // 🌟 联动机制：如果是群主创作者本人，主页异步启动审批中心小红点加载拉取
        final isMeCreator = community.value?.creatorId == UserController.to.user.value?.id;
        if (isMeCreator) {
          loadPendingApprovals();
        }

        // 详情拉取通过后，根据是否为群员，尝试加载内部发帖
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
        // 🌟 触发防火墙拦截：表明这是付费群或私密群且该用户尚未加入，阻断内容读取并拉起 Paywall
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

    if (!UserController.to.isLoggedIn) {
      Fluttertoast.showToast(msg: 'login_to_purchase_join'.tr);
      return;
    }
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
        Fluttertoast.showToast(msg: orderRes.respMsg);
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
        Fluttertoast.showToast(msg: epayCreateRes['msg'] ?? 'channel_error'.tr);
      }

    } catch (e) {
      Get.back();
      Fluttertoast.showToast(msg: 'err_request_with_msg'.trParams({'error': '$e'}));
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
          title: Text('community_payment_confirm'.tr),
          content: Text('community_payment_confirm_desc'.tr),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('cancel'.tr, style: const TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _verifyJoinSuccessOnBackend(outTradeNo);
              },
              style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
              child: Text('confirm_joined'.tr, style: const TextStyle(color: Colors.white)),
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
        Fluttertoast.showToast(msg: 'paid_community_unlocked'.tr);
        loadSpaceDetails(); // 重新拉取空间状态，解除防火墙限制
      } else {
        Fluttertoast.showToast(msg: verifyRes.respMsg);
      }
    } catch (e) {
      Get.back();
      Fluttertoast.showToast(msg: 'err_comm_with_msg'.trParams({'error': '$e'}));
    }
  }

  /// 🌟 新增：针对免费私密群（或第一次发起入群申请），提交入群申请表单到服务端 [1]
  Future<void> applyToJoinCommunity() async {
    final item = community.value;
    if (item == null) return;

    if (!UserController.to.isLoggedIn) {
      Fluttertoast.showToast(msg: 'login_to_apply_join'.tr);
      return;
    }

    Get.dialog(
      const Center(child: CircularProgressIndicator(color: Color.fromRGBO(44, 123, 109, 1.0))),
      barrierDismissible: false,
    );

    try {
      final res = await HttpClient.instance.post<Map<String, dynamic>>(
        '/api-communities/$communityId/apply',
      );

      Get.back(); // 关闭加载框

      if (res.respCode == 0) {
        Fluttertoast.showToast(msg: res.respMsg);
        loadSpaceDetails(); // 🌟 重新拉取最新的状态（自动回显为：applying 审核中状态） [1]
      } else {
        Fluttertoast.showToast(msg: res.respMsg);
      }
    } catch (e) {
      Get.back();
      if (e is ApiException) {
        Fluttertoast.showToast(msg: e.message);
      } else {
        Fluttertoast.showToast(msg: 'apply_failed_network'.trParams({'error': '$e'}));
      }
    }
  }

  // 异步拉取成员审核列表以核验最新红点计数
  Future<void> loadPendingApprovals() async {
    try {
      final res = await HttpClient.instance.get<List<dynamic>>('/api-communities/$communityId/applicants');
      if (res.respCode == 0 && res.datas != null) {
        pendingApprovalsCount.value = res.datas!.length;
      }
    } catch (_) {}
  }

  /// 在已加入的社群内发布新Saysay帖子
  Future<bool> publishPostInCommunity({
    required String title,
    required String content,
    required bool isPinned,
  }) async {
    try {
      final Map<String, dynamic> deltaOp = {
        'insert': '$content\n'
      };
      final String formattedQuillContent = jsonEncode([deltaOp]);

      final res = await HttpClient.instance.post<Map<String, dynamic>>(
        '/api-communities/$communityId/posts',
        data: {
          'title': title,
          'content': formattedQuillContent,
          'is_pinned': isPinned,
        },
      );

      if (res.respCode == 0) {
        Fluttertoast.showToast(msg: 'discussion_posted'.tr);
        loadSpacePosts(); // 立即静默洗牌刷新群贴列表，展示最新数据
        return true;
      } else {
        Fluttertoast.showToast(msg: res.respMsg);
        return false;
      }
    } catch (e) {
      Fluttertoast.showToast(msg: 'err_post_with_msg'.trParams({'error': '$e'}));
      return false;
    }
  }

  /// 管理员一键置顶/取消置顶群贴（修改为安全的 /api-posts 普通鉴权路由）
  Future<void> togglePinPost(String postId, bool currentPinState) async {
    try {
      final res = await HttpClient.instance.put<Map<String, dynamic>>(
        '/api-posts/$postId',
        data: {
          'is_pinned': !currentPinState,
        },
      );
      if (res.respCode == 0) {
        Fluttertoast.showToast(msg: !currentPinState ? 'pin_success'.tr : 'unpin_success'.tr);
        loadSpacePosts(); // 静默重排拉取最新顺序
      }
    } catch (e) {
      Fluttertoast.showToast(msg: 'pin_failed'.trParams({'error': '$e'}));
    }
  }

  /// 群主管理员一键级联下架抹除
  Future<void> deletePostByAdmin(String postId) async {
    try {
      final res = await HttpClient.instance.delete('/api-posts/$postId');
      if (res.respCode == 0) {
        Fluttertoast.showToast(msg: 'post_deleted_cascade'.tr);
        loadSpacePosts(); // 刷新大厅
      }
    } catch (e) {
      Fluttertoast.showToast(msg: 'delete_failed_short'.trParams({'error': '$e'}));
    }
  }
}