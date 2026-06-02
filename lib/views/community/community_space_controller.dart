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

        // 🌟 联动机制：如果是群主创作者本人，异步启动审批中心小红点加载拉取
        final isMeCreator = community.value?.creatorId == UserController.to.user.value?.id;
        if (isMeCreator) {
          loadPendingApprovals();
        }

        // 🌟 详情拉取通过后，根据是否为群员，尝试加载内部发帖（若非付费会员会静默 403 触发防火墙）
        loadSpacePosts();
      }
    } catch (_) {
      isLoadingDetails.value = false;
    } finally {
      isLoadingDetails.value = false;
    }
  }

  // 🌟 新增：异步拉取成员审核列表以核验最新红点计数
  Future<void> loadPendingApprovals() async {
    try {
      final res = await HttpClient.instance.get<List<dynamic>>('/api-communities/$communityId/applicants');
      if (res.respCode == 0 && res.datas != null) {
        pendingApprovalsCount.value = res.datas!.length;
      }
    } catch (_) {
      // 容错静默
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

    if (!UserController.to.isLoggedIn) {
      Fluttertoast.showToast(msg: "请登录后购买加入");
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

  /// 🌟 核心新增 A：在已加入的社群内发布新Saysay帖子
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
        Fluttertoast.showToast(msg: "讨论观点发布成功！");
        loadSpacePosts(); // 立即静默洗牌刷新群贴列表，展示最新数据
        return true;
      } else {
        Fluttertoast.showToast(msg: res.respMsg ?? "发布讨论失败");
        return false;
      }
    } catch (e) {
      Fluttertoast.showToast(msg: "发帖异常: $e");
      return false;
    }
  }

  /// 🌟🌟 核心安全修正点 B：管理员一键置顶/取消置顶群贴（修改为安全的 /api-posts 普通鉴权路由） [1]
  Future<void> togglePinPost(String postId, bool currentPinState) async {
    try {
      final res = await HttpClient.instance.put<Map<String, dynamic>>(
        '/api-posts/$postId',
        data: {
          'is_pinned': !currentPinState,
        },
      );
      if (res.respCode == 0) {
        Fluttertoast.showToast(msg: !currentPinState ? "帖子置顶成功！" : "已成功取消置顶");
        loadSpacePosts(); // 静默重排拉取最新顺序
      }
    } catch (e) {
      Fluttertoast.showToast(msg: "置顶管理操作失败: $e");
    }
  }

  /// 🌟🌟 核心安全修正点 C：群主管理员一键级联下架抹除（修改为安全的 /api-posts 物理拦截路由） [1]
  Future<void> deletePostByAdmin(String postId) async {
    try {
      final res = await HttpClient.instance.delete('/api-posts/$postId');
      if (res.respCode == 0) {
        Fluttertoast.showToast(msg: "该违规帖子及其所有讨论回复已被级联安全抹除");
        loadSpacePosts(); // 刷新大厅
      }
    } catch (e) {
      Fluttertoast.showToast(msg: "抹除失败: $e");
    }
  }
}