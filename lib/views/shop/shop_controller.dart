// lib/views/shop/shop_controller.dart
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

  String? currentOutTradeNo;
  Timer? _pollingTimer;
  int _pollingSecondsElapsed = 0;
  final int maxPollingDurationSeconds = 30;
  bool isPolling = false;

  Worker? _userStateWorker;
  Worker? _globalSyncWorker;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);

    // 🌟 1. 监听用户状态变动（切号后第一个 Tab 强制清空并全量重拉）
    _userStateWorker = ever(UserController.to.user, (_) {
      loadAllShopData();
    });

    // 🌟 2. 监听全局同步信号（在任何页面购买、加群、发帖后，所有 Tab 物理同步已购状态）
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
      if (currentOutTradeNo != null && !isPolling) {
        startPollingVerification(currentOutTradeNo!);
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

  /// 一键刷新所有 Tab，确保第 1 个 Tab 与其他页面 100% 同步
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

      Get.back();

      if (epayCreateRes['code'] == 0) {
        final payUrl = epayCreateRes['pay_info'] ?? epayCreateRes['pay_url'];
        if (payUrl != null && payUrl.toString().isNotEmpty) {
          currentOutTradeNo = outTradeNo;
          await launchExternalBrowser(payUrl.toString());
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

  void startPollingVerification(String outTradeNo) {
    _pollingTimer?.cancel();
    _pollingSecondsElapsed = 0;
    isPolling = true;

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

  /// 🌟 核心修复：精准判定支付成功，并彻底打通全局广播同步
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
        Get.back();
      }

      final Map<String, dynamic>? datas = verifyRes.datas;

      // 🌟 核心修正：只要接口返回 0 并且包含 datas，即确认支付发货成功
      final bool isSuccess = verifyRes.respCode == 0 && datas != null;

      if (isSuccess) {
        _pollingTimer?.cancel();
        isPolling = false;
        currentOutTradeNo = null;

        _closePaymentDialogs();

        // 🌟 1. 广播全 App 页面同步（首页、社群与商店全部生效已拥有）
        triggerGlobalDataSync();

        // 🌟 2. 立即主动刷新商店自身全部 Tab
        await loadAllShopData();

        Get.to(() => ShopPaymentSuccessPage(
          orderDetails: Map<String, dynamic>.from(datas),
          primaryColor: primaryColor,
          onDone: () {
            loadAllShopData();
          },
        ));
      } else {
        if (!isSilent) {
          Fluttertoast.showToast(msg: verifyRes.respMsg);
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

  void _closePaymentDialogs() {
    try {
      if (Get.isDialogOpen == true) {
        Get.back();
      }
    } catch (_) {}
  }
}