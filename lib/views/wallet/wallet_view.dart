import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'wallet_controller.dart';
import 'withdrawal_receipt_view.dart';
import 'token_recharge_paywall_view.dart'; // 🌟 桥接全新高阶付费墙充值页面

class WalletView extends StatefulWidget {
  const WalletView({super.key});

  @override
  State<WalletView> createState() => _WalletViewState();
}

class _WalletViewState extends State<WalletView> {
  final WalletController controller = Get.put(WalletController());

  // 🌟 明亮极简奢雅色彩模型
  final Color premiumBg = const Color(0xFFF8FAFC);     // 明亮极简石蓝色
  final Color premiumAmber = const Color(0xFFD97706);  // 质感琥珀金（高对比度）
  final Color premiumTeal = const Color(0xFF4F46E5);   // 皇家深靛蓝（代替原本的浅绿）
  final Color premiumCard = const Color(0xFFFFFFFF);   // 纯白轻奢卡片
  final Color premiumGray = const Color(0xFF64748B);   // 钛空灰色

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: premiumBg,
      appBar: AppBar(
        title: Text(
          'creator_wallet'.tr,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E293B)),
        ),
        centerTitle: true,
        backgroundColor: premiumBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1E293B)),
        leading: IconButton(
          onPressed: () => Get.back(),
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1E293B)),
        ),
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return Center(child: CircularProgressIndicator(color: premiumTeal, strokeWidth: 2));
        }

        final data = controller.walletData;
        final double balance = double.tryParse(data['balance']?.toString() ?? '0.00') ?? 0.00;
        final double tokens = double.tryParse(data['virtual_currency']?.toString() ?? '0.00') ?? 0.00;

        final hasPending = data['has_pending_withdrawal'] as bool? ?? false;
        final pendingDetail = data['pending_withdrawal_detail'] as Map<String, dynamic>?;

        return RefreshIndicator(
          onRefresh: controller.loadWalletOverview,
          color: premiumTeal,
          backgroundColor: premiumCard,
          child: ListView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            children: [
              const SizedBox(height: 10),
              // 🌟 纯白高光资产大卡片（带高雅的微蓝色相光晕及琥珀金、深靛蓝功能区）
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [premiumCard, const Color(0xFFF1F5F9)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                    BoxShadow(
                      color: premiumAmber.withOpacity(0.05),
                      blurRadius: 30,
                      offset: const Offset(-5, -5),
                    )
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 14,
                              decoration: BoxDecoration(
                                color: premiumAmber,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'verified_wallet'.tr,
                              style: TextStyle(color: Color(0xFF475569), fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                            ),
                          ],
                        ),
                        HugeIcon(icon: HugeIcons.strokeRoundedWallet02, color: premiumAmber, size: 20),
                      ],
                    ),
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        // 创作者收益（人民币提现通道）
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('withdrawable_earnings'.tr, style: TextStyle(color: premiumGray, fontSize: 11, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              Text(
                                '¥${balance.toStringAsFixed(2)}',
                                style: TextStyle(
                                  color: premiumAmber,
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.5,
                                  shadows: [
                                    Shadow(color: premiumAmber.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 2))
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                              if (hasPending && pendingDetail != null) ...[
                                ElevatedButton.icon(
                                  onPressed: () => Get.to(() => WithdrawalReceiptView(detail: pendingDetail)),
                                  icon: HugeIcon(icon: HugeIcons.strokeRoundedCheckList, color: premiumAmber, size: 14.0),
                                  label: Text('generate_statement'.tr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFF1F5F9),
                                    foregroundColor: premiumAmber,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                ),
                              ] else ...[
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  child: ElevatedButton(
                                    onPressed: balance < 10.0
                                        ? () => Fluttertoast.showToast(msg: 'balance_below_minimum'.tr)
                                        : () => _showWithdrawSheet(context, controller, balance),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: balance < 10.0 ? const Color(0xFFE2E8F0) : premiumAmber,
                                      foregroundColor: balance < 10.0 ? premiumGray : Colors.white,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    ),
                                    child: Text('request_withdrawal'.tr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                  ),
                                ),
                              ]
                            ],
                          ),
                        ),
                        // 竖向对账分线
                        Container(
                          width: 1,
                          height: 110,
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.transparent, const Color(0xFFE2E8F0), Colors.transparent],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                        // 用户虚拟代币资产通道
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('my_tokens'.tr, style: TextStyle(color: premiumGray, fontSize: 11, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              Text(
                                '${tokens.toInt()}',
                                style: const TextStyle(
                                  color: Color(0xFF1E293B),
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 20),
                              ElevatedButton(
                                onPressed: () => Get.to(() => const TokenRechargePaywallView()),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: premiumTeal,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  shadowColor: premiumTeal.withOpacity(0.3),
                                ),
                                child: Text('recharge_tokens'.tr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 36),

              // 列表头部
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'recent_withdrawals'.tr,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B)),
                  ),
                  Text(
                    'recent_only_notice'.tr,
                    style: TextStyle(fontSize: 10, color: premiumGray.withOpacity(0.8)),
                  )
                ],
              ),
              const SizedBox(height: 16),

              if (controller.withdrawals.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 60),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: premiumCard,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      HugeIcon(icon: HugeIcons.strokeRoundedNote01, color: premiumGray.withOpacity(0.4), size: 36),
                      const SizedBox(height: 14),
                      Text('no_withdrawal_history'.tr, style: TextStyle(color: premiumGray, fontSize: 12)),
                    ],
                  ),
                )
              else
                ...controller.withdrawals.map((item) {
                  final String outBizNo = item['outBizNo']?.toString() ?? '';
                  final double amount = double.tryParse(item['amount']?.toString() ?? '0') ?? 0.0;
                  final String status = item['status']?.toString() ?? 'reviewing';
                  final String time = item['created_at'] != null ? item['created_at'].toString().substring(0, 10) : '';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: premiumCard,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.01),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'withdraw_to_alipay'.trParams({'amount': amount.toStringAsFixed(2)}),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'transaction_no_time'.trParams({'no': '$outBizNo', 'time': '$time'}),
                                style: TextStyle(fontSize: 10, color: premiumGray, letterSpacing: 0.2),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        _buildStatusBadge(status),
                      ],
                    ),
                  );
                }),
            ],
          ),
        );
      }),
    );
  }

  /// 🌟 质感状态角标
  Widget _buildStatusBadge(String status) {
    String text = 'status_reviewing'.tr;
    Color bgColor = Colors.orange.withOpacity(0.12);
    Color textColor = Colors.orange.shade800;

    if (status == 'success') {
      text = 'status_paid'.tr;
      bgColor = premiumTeal.withOpacity(0.1);
      textColor = premiumTeal; // 🌟 已安全替换为皇家靛蓝，彻底去除浅绿色
    } else if (status == 'failed') {
      text = 'status_rejected'.tr;
      bgColor = Colors.red.withOpacity(0.1);
      textColor = Colors.red.shade800;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textColor),
      ),
    );
  }

  /// 🌟 支付宝提现滑出模态面板（全面沉浸式纯白轻奢卡片）
  void _showWithdrawSheet(BuildContext context, WalletController controller, double maxBalance) {
    final TextEditingController nameC = TextEditingController();
    final TextEditingController accountC = TextEditingController();
    final TextEditingController amountC = TextEditingController();

    nameC.text = controller.walletData['real_name']?.toString() ?? '';
    accountC.text = controller.walletData['real_phone']?.toString() ?? '';

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: premiumCard,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 30,
                offset: const Offset(0, -10),
              )
            ],
          ),
          padding: EdgeInsets.only(
            top: 16,
            left: 24,
            right: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 30,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'withdraw_earnings_title'.tr,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B)),
              ),
              const SizedBox(height: 10),
              Text(
                'withdraw_notice'.tr,
                style: TextStyle(color: premiumGray, fontSize: 11, height: 1.5),
              ),
              const SizedBox(height: 24),

              // 姓名输入框
              TextField(
                controller: nameC,
                style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
                cursorColor: premiumAmber,
                decoration: InputDecoration(
                  hintText: 'alipay_name_hint'.tr,
                  hintStyle: TextStyle(color: premiumGray.withOpacity(0.5), fontSize: 12),
                  prefixIcon: Icon(Icons.person_outline_rounded, size: 18, color: premiumGray),
                  filled: true,
                  fillColor: const Color(0xFFF1F5F9),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: premiumAmber),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // 账号输入框
              TextField(
                controller: accountC,
                style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
                cursorColor: premiumAmber,
                decoration: InputDecoration(
                  hintText: 'alipay_account_hint'.tr,
                  hintStyle: TextStyle(color: premiumGray.withOpacity(0.5), fontSize: 12),
                  prefixIcon: Icon(Icons.phone_iphone_rounded, size: 18, color: premiumGray),
                  filled: true,
                  fillColor: const Color(0xFFF1F5F9),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: premiumAmber),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // 金额输入框
              TextField(
                controller: amountC,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
                cursorColor: premiumAmber,
                decoration: InputDecoration(
                  hintText: 'withdraw_amount_hint'.tr,
                  hintStyle: TextStyle(color: premiumGray.withOpacity(0.5), fontSize: 12),
                  prefixIcon: Icon(Icons.attach_money_rounded, size: 18, color: premiumGray),
                  suffixIcon: Container(
                    padding: const EdgeInsets.only(right: 14),
                    alignment: Alignment.centerRight,
                    width: 80,
                    child: GestureDetector(
                      onTap: () => amountC.text = maxBalance.toStringAsFixed(2),
                      child: Text(
                        'withdraw_all'.tr,
                        style: TextStyle(color: premiumAmber, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF1F5F9),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: premiumAmber),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // 确认按钮
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () async {
                    final name = nameC.text.trim();
                    final account = accountC.text.trim();
                    final amountText = amountC.text.trim();

                    if (name.isEmpty || account.isEmpty || amountText.isEmpty) {
                      Fluttertoast.showToast(msg: 'fill_withdrawal_data'.tr);
                      return;
                    }

                    final double amount = double.tryParse(amountText) ?? 0.0;
                    if (amount < 10.0) {
                      Fluttertoast.showToast(msg: 'minimum_withdrawal'.tr);
                      return;
                    }
                    if (amount > maxBalance) {
                      Fluttertoast.showToast(msg: 'insufficient_balance'.tr);
                      return;
                    }

                    final success = await controller.requestWithdraw(
                      alipayName: name,
                      alipayAccount: account,
                      amount: amount,
                    );

                    if (success) {
                      Navigator.pop(context);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: premiumAmber,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 4,
                    shadowColor: premiumAmber.withOpacity(0.2),
                  ),
                  child: Text(
                    'confirm_and_freeze'.tr,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              )
            ],
          ),
        );
      },
    );
  }
}