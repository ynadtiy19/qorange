// lib/views/shop/shop_controller.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:url_launcher/url_launcher.dart';
import 'shop_goods_model.dart';
import '../../network/api_exception.dart';
import '../../network/http_client.dart';
import '../../services/epay_client_service.dart';
import '../../user_controller.dart';

/// 支付处理状态枚举
enum PaymentProcessingStatus {
  idle,
  waiting,     // 正在等待外部支付与轮询
  success,     // 验证成功
  failed,      // 失败
  timeout,     // 超时
}

class ShopController extends GetxController with WidgetsBindingObserver {
  static ShopController get to => Get.find<ShopController>();

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

  // 🌟 实时支付状态与当前轮询对象
  final Rx<PaymentProcessingStatus> paymentStatus = PaymentProcessingStatus.idle.obs;
  final RxString paymentStatusMessage = ''.obs;
  final Rx<ShopGoods?> purchasingItem = Rx<ShopGoods?>(null);
  final RxMap<String, dynamic> lastOrderDetails = <String, dynamic>{}.obs;

  // 🌟 购买成功后高亮呼吸聚焦的商品 ID
  final RxString highlightedGoodsId = ''.obs;

  String? currentOutTradeNo;
  Timer? _pollingTimer;
  int _pollingSecondsElapsed = 0;
  final int maxPollingDurationSeconds = 45;
  bool isPolling = false;

  Worker? _userStateWorker;
  Worker? _globalSyncWorker;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);

    // 🌟 1. 监听用户状态变动（切号后全量重拉）
    _userStateWorker = ever(UserController.to.user, (_) {
      loadAllShopData();
    });

    // 🌟 2. 监听全局同步信号（在任何页面购买、加群、发帖后物理同步已购状态）
    _globalSyncWorker = ever(globalDataSyncSignal, (_) {
      loadAllShopData();
    });

    loadAllShopData();
  }

  @override
  void onClose() {
    _userStateWorker?.dispose();
    _globalSyncWorker?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _pollingTimer?.cancel();
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (currentOutTradeNo != null && isPolling) {
        // 用户切回 App 时立即触发一次静默校准
        verifyPaymentOnBackend(currentOutTradeNo!, isSilent: true);
      }
    }
  }

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

  Future<void> loadCategoryData(String category) async {
    if (category == 'all') isLoadingAll.value = true;
    if (category == 'post') isLoadingPost.value = true;
    if (category == 'group') isLoadingGroup.value = true;

    await fetchGoods(category: category, isRefresh: true);
  }

  /// 一键刷新所有 Tab，确保数据 100% 同步
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
          if (isRefresh) {
            allGoods.assignAll(parsedGoods);
          } else {
            allGoods.addAll(parsedGoods);
          }
          allGoods.refresh();
          isLoadingAll.value = false;
          isLoadingMoreAll.value = false;
          hasMoreAll.value = parsedGoods.length >= pageSize;
        } else if (category == 'post') {
          if (isRefresh) {
            postGoods.assignAll(parsedGoods);
          } else {
            postGoods.addAll(parsedGoods);
          }
          postGoods.refresh();
          isLoadingPost.value = false;
          isLoadingMorePost.value = false;
          hasMorePost.value = parsedGoods.length >= pageSize;
        } else if (category == 'group') {
          if (isRefresh) {
            groupGoods.assignAll(parsedGoods);
          } else {
            groupGoods.addAll(parsedGoods);
          }
          groupGoods.refresh();
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

  Future<void> launchExternalBrowser(String urlString) async {
    final url = Uri.parse(urlString);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      Fluttertoast.showToast(msg: 'cannot_launch_payment'.tr);
    }
  }

  /// 发起支付并拉起外部收银台与自动轮询流程
  Future<bool> startPaymentWorkflow(ShopGoods item, String selectedPayType) async {
    if (!UserController.to.isLoggedIn) {
      Fluttertoast.showToast(msg: 'login_to_purchase'.tr);
      return false;
    }

    purchasingItem.value = item;
    paymentStatus.value = PaymentProcessingStatus.waiting;
    paymentStatusMessage.value = '正在安全创建订单...';

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
        paymentStatus.value = PaymentProcessingStatus.failed;
        paymentStatusMessage.value = orderRes.respMsg.isNotEmpty ? orderRes.respMsg : '订单创建失败';
        return false;
      }

      final outTradeNo = orderRes.datas!['outTradeNo']?.toString();
      final amount = orderRes.datas!['amount'];
      final goodsName = orderRes.datas!['goodsName'];

      if (outTradeNo == null) {
        paymentStatus.value = PaymentProcessingStatus.failed;
        paymentStatusMessage.value = 'no_order_number'.tr;
        return false;
      }

      paymentStatusMessage.value = '正在唤起收银台...';

      final epay = EpayClientService();
      final epayCreateRes = await epay.createPaymentDirectly(params: {
        'method': 'jump',
        'device': 'mobile',
        'type': selectedPayType,
        'out_trade_no': outTradeNo,
        'name': goodsName,
        'money': amount,
      });

      if (epayCreateRes['code'] == 0) {
        final payUrl = epayCreateRes['pay_info'] ?? epayCreateRes['pay_url'];
        if (payUrl != null && payUrl.toString().isNotEmpty) {
          currentOutTradeNo = outTradeNo;
          paymentStatusMessage.value = '已打开支付页面，正在实时监听支付结果...';

          await launchExternalBrowser(payUrl.toString());
          startPollingVerification(outTradeNo);
          return true;
        } else {
          paymentStatus.value = PaymentProcessingStatus.failed;
          paymentStatusMessage.value = 'gateway_parse_error'.tr;
          return false;
        }
      } else {
        paymentStatus.value = PaymentProcessingStatus.failed;
        paymentStatusMessage.value = epayCreateRes['msg'] ?? 'gateway_launch_error'.tr;
        return false;
      }
    } catch (e) {
      paymentStatus.value = PaymentProcessingStatus.failed;
      if (e is ApiException) {
        paymentStatusMessage.value = e.message;
      } else {
        paymentStatusMessage.value = 'err_request_link'.trParams({'error': '$e'});
      }
      return false;
    }
  }

  /// 开启高频自动轮询检测
  void startPollingVerification(String outTradeNo) {
    _pollingTimer?.cancel();
    _pollingSecondsElapsed = 0;
    isPolling = true;

    // 立即触发一次
    verifyPaymentOnBackend(outTradeNo, isSilent: true);

    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _pollingSecondsElapsed += 2;
      if (_pollingSecondsElapsed >= maxPollingDurationSeconds) {
        timer.cancel();
        isPolling = false;
        if (paymentStatus.value == PaymentProcessingStatus.waiting) {
          paymentStatus.value = PaymentProcessingStatus.timeout;
          paymentStatusMessage.value = '未在规定时间内检测到到账，若已扣款请稍后手动刷新';
        }
      } else {
        verifyPaymentOnBackend(outTradeNo, isSilent: true);
      }
    });
  }

  /// 向后端核验订单状态
  Future<void> verifyPaymentOnBackend(String outTradeNo, {required bool isSilent}) async {
    try {
      final epay = EpayClientService();
      final realEpayData = await epay.queryOrderDirectly(outTradeNo: outTradeNo);

      final verifyRes = await HttpClient.instance.post<Map<String, dynamic>>(
        '/api-pay/verify_payment',
        data: {'epay_response': realEpayData},
      );

      final Map<String, dynamic>? datas = verifyRes.datas;
      final bool isSuccess = verifyRes.respCode == 0 && datas != null;

      if (isSuccess) {
        _pollingTimer?.cancel();
        isPolling = false;
        currentOutTradeNo = null;

        lastOrderDetails.assignAll(datas);
        paymentStatus.value = PaymentProcessingStatus.success;
        paymentStatusMessage.value = '支付成功，权益已实时解锁！';

        // 🌟 1. 全局数据信号广播
        triggerGlobalDataSync();

        // 🌟 2. 标记需要高亮聚焦的商品
        if (purchasingItem.value != null) {
          highlightedGoodsId.value = purchasingItem.value!.id;
        }

        // 🌟 3. 静默全量刷新当前商城列表
        await loadAllShopData();
      } else {
        if (!isSilent) {
          Fluttertoast.showToast(msg: verifyRes.respMsg);
        }
      }
    } catch (_) {
      // 轮询中的网络波动静默忽略，继续下次轮询
    }
  }

  /// 手动取消/关闭轮询
  void cancelPolling() {
    _pollingTimer?.cancel();
    isPolling = false;
    currentOutTradeNo = null;
    paymentStatus.value = PaymentProcessingStatus.idle;
  }
}