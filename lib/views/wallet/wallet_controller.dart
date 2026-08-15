import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../network/http_client.dart';
import '../../network/api_exception.dart';

class WalletController extends GetxController {
  final RxMap<String, dynamic> walletData = <String, dynamic>{}.obs;
  final RxBool isLoading = true.obs;
  final RxList<dynamic> withdrawals = <dynamic>[].obs;

  @override
  void onInit() {
    super.onInit();
    loadWalletOverview();
  }

  /// 🌟 载入创作者钱包首页资产快照与对账流水
  Future<void> loadWalletOverview() async {
    isLoading.value = true;
    try {
      final res = await HttpClient.instance.get<Map<String, dynamic>>('/api-wallet/overview');
      if (res.respCode == 0 && res.datas != null) {
        walletData.value = res.datas!;
        withdrawals.assignAll(res.datas!['withdrawals'] ?? []);
      }
    } catch (_) {
      isLoading.value = false;
    } finally {
      isLoading.value = false;
    }
  }

  /// 🌟 向 Zeabur 提现网关申请起息扣减，进入人工对账打款流程 [1]
  Future<bool> requestWithdraw({
    required String alipayName,
    required String alipayAccount,
    required double amount,
  }) async {
    try {
      final res = await HttpClient.instance.post<Map<String, dynamic>>(
        '/api-withdraw/request',
        data: {
          'name': alipayName,
          'account': alipayAccount,
          'amount': amount.toString(),
        },
      );

      if (res.respCode == 0) {
        Fluttertoast.showToast(msg: 'withdrawal_submitted'.tr);
        loadWalletOverview(); // 重新拉取以更新冻结扣减后的余额和近期提现历史 [1]
        return true;
      } else {
        Fluttertoast.showToast(msg: res.respMsg ?? 'withdrawal_failed'.tr);
        return false;
      }
    } catch (e) {
      if (e is ApiException) {
        Fluttertoast.showToast(msg: e.message);
      } else {
        Fluttertoast.showToast(msg: 'withdrawal_failed_retry'.tr);
      }
      return false;
    }
  }
}