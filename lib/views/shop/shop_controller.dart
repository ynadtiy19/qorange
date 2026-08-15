import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:url_launcher/url_launcher.dart';
import 'shop_goods_model.dart';
import 'shop_view.dart';
import '../../network/api_exception.dart';
import '../../network/http_client.dart';
import '../../services/epay_client_service.dart';
import '../../user_controller.dart';

class ShopController extends GetxController with WidgetsBindingObserver {
  final Color primaryColor = const Color.fromRGBO(44, 123, 109, 1.0);

  // 商品数据载荷
  final RxList<ShopGoods> allGoods = <ShopGoods>[].obs;
  final RxList<ShopGoods> postGoods = <ShopGoods>[].obs;
  final RxList<ShopGoods> groupGoods = <ShopGoods>[].obs;

  // 状态维护
  final RxBool isLoadingAll = true.obs;
  final RxBool isLoadingPost = true.obs;
  final RxBool isLoadingGroup = true.obs;

  final RxInt allPage = 1.obs;
  final RxInt postPage = 1.obs;
  final RxInt groupPage = 1.obs;
  final int pageSize = 10;

  final RxBool hasMoreAll = true.obs;
  final RxBool hasMorePost = true.obs;
  final RxBool hasMoreGroup = true.obs;

  final RxBool isLoadingMoreAll = false.obs;
  final RxBool isLoadingMorePost = false.obs;
  final RxBool isLoadingMoreGroup = false.obs;

  // 轮询与返回唤醒校验变量
  String? currentOutTradeNo;
  Timer? _pollingTimer;
  int _pollingSecondsElapsed = 0;
  final int maxPollingDurationSeconds = 30; // 30秒轮询超时时间
  bool isPolling = false;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollingTimer?.cancel();
    super.onClose();
  }

  /// 监听应用生命周期，当用户从外部浏览器支付返回 App 时，触发自动轮询校验
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (currentOutTradeNo != null && !isPolling) {
        startPollingVerification(currentOutTradeNo!);
      }
    }
  }

  /// 根据索引获取分类标识
  String getCategoryByIndex(int index) {
    switch (index) {
      case 0:
        return 'all';
      case 1:
        return 'post';
      case 2:
        return 'group';
      default:
        return 'all';
    }
  }

  /// 按需加载指定分类的数据（支持静默刷新）
  Future<void> loadCategoryData(String category) async {
    bool isSilent = false;

    if (category == 'all' && allGoods.isNotEmpty) isSilent = true;
    if (category == 'post' && postGoods.isNotEmpty) isSilent = true;
    if (category == 'group' && groupGoods.isNotEmpty) isSilent = true;

    if (!isSilent) {
      if (category == 'all') isLoadingAll.value = true;
      if (category == 'post') isLoadingPost.value = true;
      if (category == 'group') isLoadingGroup.value = true;
    }

    await fetchGoods(category: category, isRefresh: true);
  }

  /// 一键加载/刷新全部商店数据
  Future<void> loadAllShopData() async {
    isLoadingAll.value = true;
    isLoadingPost.value = true;
    isLoadingGroup.value = true;

    await Future.wait([
      fetchGoods(category: 'all', isRefresh: true),
      fetchGoods(category: 'post', isRefresh: true),
      fetchGoods(category: 'group', isRefresh: true),
    ]);
  }

  /// 统一分页异步网络拉取
  Future<void> fetchGoods({required String category, bool isRefresh = false}) async {
    int targetPage = 1;
    if (!isRefresh) {
      if (category == 'all') targetPage = ++allPage.value;
      if (category == 'post') targetPage = ++postPage.value;
      if (category == 'group') targetPage = ++groupPage.value;
    } else {
      if (category == 'all') allPage.value = 1;
      if (category == 'post') postPage.value = 1;
      if (category == 'group') groupPage.value = 1;
    }

    try {
      final res = await HttpClient.instance.get<Map<String, dynamic>>(
        '/api-goods',
        queryParameters: {
          'category': category,
          'page': targetPage,
          'limit': pageSize,
        },
      );

      if (res.respCode == 0 && res.datas != null) {
        final List<dynamic> rawGoodsList = res.datas!['goods'] as List? ?? [];
        final List<ShopGoods> parsedGoods = rawGoodsList.map((e) => ShopGoods.fromJson(e)).toList();

        if (category == 'all') {
          if (isRefresh) allGoods.assignAll(parsedGoods); else allGoods.addAll(parsedGoods);
          isLoadingAll.value = false;
          isLoadingMoreAll.value = false;
          hasMoreAll.value = parsedGoods.length >= pageSize;
        } else if (category == 'post') {
          if (isRefresh) postGoods.assignAll(parsedGoods); else postGoods.addAll(parsedGoods);
          isLoadingPost.value = false;
          isLoadingMorePost.value = false;
          hasMorePost.value = parsedGoods.length >= pageSize;
        } else if (category == 'group') {
          if (isRefresh) groupGoods.assignAll(parsedGoods); else groupGoods.addAll(parsedGoods);
          isLoadingGroup.value = false;
          isLoadingMoreGroup.value = false;
          hasMoreGroup.value = parsedGoods.length >= pageSize;
        }
      }
    } catch (_) {
      isLoadingAll.value = false;
      isLoadingPost.value = false;
      isLoadingGroup.value = false;
      isLoadingMoreAll.value = false;
      isLoadingMorePost.value = false;
      isLoadingMoreGroup.value = false;
    }
  }

  Future<void> fetchMoreGoods(String category) async {
    if (category == 'all' && (isLoadingMoreAll.value || !hasMoreAll.value || isLoadingAll.value)) return;
    if (category == 'post' && (isLoadingMorePost.value || !hasMorePost.value || isLoadingPost.value)) return;
    if (category == 'group' && (isLoadingMoreGroup.value || !hasMoreGroup.value || isLoadingGroup.value)) return;

    if (category == 'all') isLoadingMoreAll.value = true;
    if (category == 'post') isLoadingMorePost.value = true;
    if (category == 'group') isLoadingMoreGroup.value = true;

    await fetchGoods(category: category, isRefresh: false);
  }

  /// 安全外部支付跳转逻辑
  Future<void> launchExternalBrowser(String urlString) async {
    final url = Uri.parse(urlString);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      Fluttertoast.showToast(msg: 'cannot_launch_payment'.tr);
    }
  }

  /// 专门对齐易支付网关 RFC 3986 的编码拼接器，强制将 '+' 转换为 '%20'
  String buildEpayQueryString(Map<String, dynamic> params) {
    final List<String> parts = [];
    params.forEach((key, value) {
      final encodedKey = Uri.encodeQueryComponent(key);
      final encodedValue = Uri.encodeQueryComponent(value.toString()).replaceAll('+', '%20');
      parts.add('$encodedKey=$encodedValue');
    });
    return parts.join('&');
  }

  /// 极速付款流程全闭环执行
  Future<void> executePaymentWorkflow(ShopGoods item, String selectedPayType) async {
    if (!UserController.to.isLoggedIn) {
      Fluttertoast.showToast(msg: 'login_to_purchase'.tr);
      return;
    }

    Get.dialog(
      const Center(
        child: CircularProgressIndicator(color: Color.fromRGBO(44, 123, 109, 1.0)),
      ),
      barrierDismissible: false,
    );

    try {
      final orderRes = await HttpClient.instance.post<Map<String, dynamic>>(
        '/api-pay/create_order',
        data: {
          'goodsId': item.id,
          'goodsType': item.category,
          'payType': selectedPayType,
        },
      );

      if (orderRes.respCode != 0 || orderRes.datas == null) {
        Get.back();
        Fluttertoast.showToast(msg: orderRes.respMsg);
        return;
      }

      final outTradeNo = orderRes.datas!['outTradeNo']?.toString();
      final amount = orderRes.datas!['amount'];
      final goodsName = orderRes.datas!['goodsName'];

      if (outTradeNo == null) {
        Get.back();
        Fluttertoast.showToast(msg: 'no_order_number'.tr);
        return;
      }

      final epay = EpayClientService();
      final epayCreateRes = await epay.createPaymentDirectly(params: {
        'method': 'jump',
        'device': 'mobile',
        'type': selectedPayType,
        'out_trade_no': outTradeNo,
        'name': goodsName,
        'money': amount,
      });

      Get.back(); // 关闭等待弹窗

      if (epayCreateRes['code'] == 0) {
        final payUrl = epayCreateRes['pay_info'] ?? epayCreateRes['pay_url'];
        if (payUrl != null && payUrl.toString().isNotEmpty) {
          // 记录订单号，以便返回 App 后能够进行自动异步轮询
          currentOutTradeNo = outTradeNo;

          await launchExternalBrowser(payUrl.toString());

          // 开启备用手动确认弹窗
          showPaymentCheckDialog(outTradeNo);
        } else {
          Fluttertoast.showToast(msg: 'gateway_parse_error'.tr);
        }
      } else {
        Fluttertoast.showToast(msg: epayCreateRes['msg'] ?? 'gateway_launch_error'.tr);
      }
    } catch (e) {
      Get.back();
      if (e is ApiException) {
        Fluttertoast.showToast(msg: e.message);
      } else {
        Fluttertoast.showToast(msg: 'err_request_link'.trParams({'error': '$e'}));
      }
    }
  }

  /// 弹出手动确认支付框
  void showPaymentCheckDialog(String outTradeNo) {
    final BuildContext context = Get.context!;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('payment_confirm'.tr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          content: Text('payment_confirm_desc'.tr, style: const TextStyle(fontSize: 13, height: 1.4)),
          actions: [
            TextButton(
              onPressed: () {
                currentOutTradeNo = null;
                _pollingTimer?.cancel();
                isPolling = false;
                Navigator.pop(context);
              },
              child: Text('payment_cancelled'.tr, style: const TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                verifyPaymentOnBackend(outTradeNo, isSilent: false);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text('payment_completed'.tr, style: const TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  /// 开启定时器轮询拉取支付结果
  void startPollingVerification(String outTradeNo) {
    _pollingTimer?.cancel();
    _pollingSecondsElapsed = 0;
    isPolling = true;

    // 唤起时立刻执行一次静默校验
    verifyPaymentOnBackend(outTradeNo, isSilent: true);

    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _pollingSecondsElapsed += 3;
      if (_pollingSecondsElapsed >= maxPollingDurationSeconds) {
        timer.cancel();
        isPolling = false;
        currentOutTradeNo = null;
        Fluttertoast.showToast(msg: 'payment_not_detected'.tr);
      } else {
        verifyPaymentOnBackend(outTradeNo, isSilent: true);
      }
    });
  }

  /// 向服务器发起原装签名账本解密并验证接口
  Future<void> verifyPaymentOnBackend(String outTradeNo, {required bool isSilent}) async {
    if (!isSilent) {
      Get.dialog(
        const Center(
          child: CircularProgressIndicator(color: Color.fromRGBO(44, 123, 109, 1.0)),
        ),
        barrierDismissible: false,
      );
    }

    try {
      final epay = EpayClientService();
      final realEpayData = await epay.queryOrderDirectly(outTradeNo: outTradeNo);

      final verifyRes = await HttpClient.instance.post<Map<String, dynamic>>(
        '/api-pay/verify_payment',
        data: {'epay_response': realEpayData},
      );

      if (!isSilent) {
        Get.back(); // 关闭手动确认弹窗产生的 loading 圈
      }

      final Map<String, dynamic>? datas = verifyRes.datas;

      // 🌟 安全判断逻辑，只有返回数据包中包含 goodsName 且 userId 都不为空时才视为支付成功
      final bool isSuccess = verifyRes.respCode == 0 &&
          datas != null &&
          datas['goodsName'] != null &&
          datas['userId'] != null;

      if (isSuccess) {
        // 验证通过，终止一切轮询，清除等待状态
        _pollingTimer?.cancel();
        isPolling = false;
        currentOutTradeNo = null;

        // 如果存在底层弹出的校验对话框，则主动关闭
        _closePaymentDialogs();

        // 触发极速路由到动画交易成功详情页
        Get.to(() => ShopPaymentSuccessPage(
          orderDetails: Map<String, dynamic>.from(datas),
          primaryColor: primaryColor,
          onDone: () {
            // 回退静默刷新页面列表信息
            loadAllShopData();
          },
        ));
      } else {
        if (!isSilent) {
          Fluttertoast.showToast(msg: verifyRes.respMsg ?? 'order_not_paid'.tr);
        }
      }
    } catch (e) {
      if (!isSilent) {
        Get.back();
        if (e is ApiException) {
          Fluttertoast.showToast(msg: e.message);
        } else {
          Fluttertoast.showToast(msg: 'err_verify_gateway'.trParams({'error': '$e'}));
        }
      }
    }
  }

  /// 封装退出多余对话框的安全函数，避免路由上下文发生冲突
  void _closePaymentDialogs() {
    try {
      if (Get.isDialogOpen == true) {
        Get.back();
      }
    } catch (_) {}
  }
}