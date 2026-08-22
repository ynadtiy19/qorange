import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:qorange/theme.dart';

class WithdrawalReceiptView extends StatefulWidget {
  final Map<String, dynamic> detail;
  const WithdrawalReceiptView({super.key, required this.detail});

  @override
  State<WithdrawalReceiptView> createState() => _WithdrawalReceiptViewState();
}

class _WithdrawalReceiptViewState extends State<WithdrawalReceiptView> {
  final GlobalKey _repaintKey = GlobalKey();

  // 曜石黑金高级色彩模型
  final Color premiumBg = const Color(0xFF0B0D17);     // 深太空蓝
  final Color premiumAmber = const Color(0xFFFFB636);  // 香槟琥珀金
  final Color premiumCard = const Color(0xFF161926);   // 暗调轻奢卡片

  bool _isCapturing = false;

  /// 将 UI Widget 物理捕获并渲染生成高清 PNG
  Future<void> _captureAndShareReceipt() async {
    if (_isCapturing) return;
    setState(() => _isCapturing = true);

    Fluttertoast.showToast(msg: 'generating_snapshot'.tr);

    try {
      await Future.delayed(const Duration(milliseconds: 300));

      final RenderRepaintBoundary boundary =
      _repaintKey.currentContext!.findRenderObject() as RenderRepaintBoundary;

      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final Uint8List pngBytes = byteData!.buffer.asUint8List();

      final Directory tempDir = await getTemporaryDirectory();
      final String filePath = '${tempDir.path}/QOrange_Receipt_${widget.detail['outBizNo']}.png';
      final File file = File(filePath);
      await file.writeAsBytes(pngBytes);

      setState(() => _isCapturing = false);

      await Share.shareXFiles(
        [XFile(filePath)],
        text: 'receipt_share_text'.trParams({'no': '${widget.detail['outBizNo']}'}),
      );

    } catch (e) {
      setState(() => _isCapturing = false);
      Fluttertoast.showToast(msg: 'snapshot_failed'.trParams({'error': '$e'}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final String nickname = widget.detail['nickname'] ?? 'scholar'.tr;
    final String handle = '@${widget.detail['username'] ?? ''}';
    final String outBizNo = widget.detail['outBizNo'] ?? '';
    final String account = widget.detail['account'] ?? '';
    final String realName = widget.detail['name'] ?? '';

    // 🌟 从详情里提取绑定的手机号 [1]
    final String realPhone = widget.detail['real_phone'] ?? 'not_bound'.tr;

    final String amount = double.tryParse(widget.detail['amount']?.toString() ?? '0')?.toStringAsFixed(2) ?? '0.00';
    final String taxDeducted = double.tryParse(widget.detail['tax_deducted']?.toString() ?? '0')?.toStringAsFixed(2) ?? '0.00';
    final String actualPayout = double.tryParse(widget.detail['actual_payout']?.toString() ?? '0')?.toStringAsFixed(2) ?? '0.00';
    final String createTime = widget.detail['created_at'] != null
        ? widget.detail['created_at'].toString().substring(0, 19).replaceAll('T', ' ')
        : '';

    return Scaffold(
      backgroundColor: AppColors.surfaceAlt, // 浅灰背景，更衬托票据纸张纯净感
      appBar: AppBar(
        title: Text('withdrawal_statement'.tr, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary)),
        centerTitle: true,
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Get.back(),
          icon: const Icon(Icons.arrow_back, color: Colors.black),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          children: [
            RepaintBoundary(
              key: _repaintKey,
              child: Container(
                decoration: BoxDecoration(color: AppColors.surface,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    )
                  ],
                ),
                child: Column(
                  children: [
                    // 极简暗雅头部栏
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                      decoration: BoxDecoration(
                        color: premiumBg,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(24),
                          topRight: Radius.circular(24),
                        ),
                      ),
                      child: Row(
                        children: [
                          HugeIcon(icon: HugeIcons.strokeRoundedCheckList, color: premiumAmber, size: 28),
                          const SizedBox(width: 14),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('QORANGE PLATFORM RECEIPT', style: TextStyle(color: premiumAmber, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                              const SizedBox(height: 4),
                              Text('statement_voucher_title'.tr, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                            ],
                          )
                        ],
                      ),
                    ),

                    // 票据账单信息排版
                    Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(nickname, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary)),
                                  const SizedBox(height: 2),
                                  Text(handle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                ],
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
                                child: Text('finance_reviewing'.tr, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                              )
                            ],
                          ),
                          const SizedBox(height: 24),
                          Divider(height: 1, color: AppColors.surfaceAlt),
                          const SizedBox(height: 20),

                          _buildReceiptItem('receipt_ref_no'.tr, outBizNo),
                          _buildReceiptItem('receipt_alipay_name'.tr, realName),
                          _buildReceiptItem('receipt_alipay_account'.tr, account),
                          // 🌟 追加展示学者的账户绑定电话，方便核算
                          _buildReceiptItem('receipt_phone'.tr, realPhone),
                          _buildReceiptItem('receipt_total'.tr, '¥$amount'),
                          _buildReceiptItem('receipt_tax'.tr, '- ¥$taxDeducted', textColor: Colors.redAccent),

                          const SizedBox(height: 16),
                          Divider(height: 1, color: AppColors.surfaceAlt),
                          const SizedBox(height: 20),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('receipt_net'.tr, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppColors.textPrimary)),
                              Text(
                                '¥$actualPayout',
                                style: TextStyle(color: premiumBg, fontWeight: FontWeight.bold, fontSize: 24, letterSpacing: -0.5),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text('receipt_created_at'.trParams({'time': '$createTime'}), style: TextStyle(fontSize: 9, color: AppColors.textHint)),
                          ),

                          const SizedBox(height: 32),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('QORANGE AUDITED', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.5)),
                                  const SizedBox(height: 4),
                                  Container(
                                    width: 140,
                                    height: 35,
                                    color: Colors.black,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                      children: List.generate(14, (idx) => Container(width: idx % 3 == 0 ? 4 : 2, color: Colors.white)),
                                    ),
                                  )
                                ],
                              ),
                              Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.redAccent.withOpacity(0.5), width: 2),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Transform.rotate(
                                    angle: -0.2,
                                    child: Text(
                                      'receipt_stamp'.tr,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.redAccent.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              )
                            ],
                          )
                        ],
                      ),
                    )
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _captureAndShareReceipt,
                style: ElevatedButton.styleFrom(
                  backgroundColor: premiumBg,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 4,
                  shadowColor: premiumBg.withOpacity(0.3),
                ),
                icon: HugeIcon(icon: HugeIcons.strokeRoundedShare01, color: premiumAmber, size: 20),
                label: Text('generate_and_send'.tr, style: TextStyle(color: premiumAmber, fontWeight: FontWeight.bold, fontSize: 14)),
              ),
            ),
            const SizedBox(height: 12),
            Text('statement_saved_notice'.tr, style: TextStyle(color: AppColors.textSecondary, fontSize: 10), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildReceiptItem(String label, String value, {Color? textColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
          Text(value, style: TextStyle(color: textColor ?? AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}