import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'wallet_controller.dart';
import '../../network/api_exception.dart';
import '../../network/http_client.dart';
import '../../user_controller.dart';
import '../../services/epay_client_service.dart';

class TokenRechargePaywallView extends StatefulWidget {
  const TokenRechargePaywallView({super.key});

  @override
  State<TokenRechargePaywallView> createState() => _TokenRechargePaywallViewState();
}

class _TokenRechargePaywallViewState extends State<TokenRechargePaywallView> {
  final WalletController walletController = Get.find<WalletController>();
  final TextEditingController _customAmountC = TextEditingController();

  Timer? _pollingTimer;
  bool _isPollingActive = false;

  // 🌟 明亮极简奢雅色彩模型
  final Color premiumBg = const Color(0xFFF8FAFC);     // 明亮极简石蓝色
  final Color premiumAmber = const Color(0xFFD97706);  // 质感琥珀金（高对比度）
  final Color premiumCard = const Color(0xFFFFFFFF);   // 纯白轻奢卡片
  final Color premiumGray = const Color(0xFF64748B);   // 钛空灰色

  double _selectedAmount = 10.0; // 默认面额 10 元
  String _selectedPayType = 'alipay';

  final List<Map<String, dynamic>> _presets = [
    {'cny': 10.0, 'tokens': 100},
    {'cny': 30.0, 'tokens': 300},
    {'cny': 50.0, 'tokens': 500},
    {'cny': 100.0, 'tokens': 1000},
    {'cny': 200.0, 'tokens': 2000},
    {'cny': 500.0, 'tokens': 5000},
  ];

  @override
  void dispose() {
    _stopRechargePolling();
    _customAmountC.dispose();
    super.dispose();
  }

  void _stopRechargePolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _isPollingActive = false;
  }

  /// 异步检测充值入账
  void _startRechargePolling(String outTradeNo) {
    _stopRechargePolling();
    _isPollingActive = true;

    int pollCount = 0;
    const int maxPolls = 60; // 最多轮询3分钟

    Fluttertoast.showToast(msg: "🔔 已开启到账安全检测，付款后将自动充值...");

    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!_isPollingActive || pollCount >= maxPolls) {
        _stopRechargePolling();
        return;
      }
      pollCount++;

      try {
        final epay = EpayClientService();
        final realEpayData = await epay.queryOrderDirectly(outTradeNo: outTradeNo);
        final String statusStr = realEpayData['status']?.toString() ?? '0';

        if (statusStr == '1') {
          _stopRechargePolling();

          final verifyRes = await HttpClient.instance.post<Map<String, dynamic>>(
            '/api-pay/verify_payment',
            data: {'epay_response': realEpayData},
          );

          if (verifyRes.respCode == 0) {
            final double added = double.tryParse(realEpayData['money']?.toString() ?? '0') ?? 0.0;
            Fluttertoast.showToast(
              msg: "🎉 充值成功！已为您成功增加 ${(added * 10).toInt()} 个平台代币！",
              toastLength: Toast.LENGTH_LONG,
            );
            // 🌟 静默刷新外层钱包资产快照
            walletController.loadWalletOverview();
            Get.back(); // 自动回退
          }
        }
      } catch (_) {}
    });
  }

  /// 物理下单执行充值
  Future<void> _executeRechargeWorkflow(double cnyAmount, String selectedPayType) async {
    Get.dialog(
      Center(child: CircularProgressIndicator(color: premiumAmber)),
      barrierDismissible: false,
    );

    try {
      final orderRes = await HttpClient.instance.post<Map<String, dynamic>>(
        '/api-pay/create_order',
        data: {
          'goodsId': cnyAmount.toStringAsFixed(2),
          'goodsType': 'recharge',
          'payType': selectedPayType,
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
        if (payUrl != null) {
          final url = Uri.parse(payUrl.toString());
          if (await canLaunchUrl(url)) {
            await launchUrl(url, mode: LaunchMode.externalApplication);
            _startRechargePolling(outTradeNo);
          }
        }
      } else {
        Fluttertoast.showToast(msg: epayCreateRes['msg'] ?? '充值网关异常');
      }
    } catch (e) {
      Get.back();
      if (e is ApiException) {
        Fluttertoast.showToast(msg: e.message);
      } else {
        Fluttertoast.showToast(msg: '充值异常: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 特权后门检查
    final String currentUserId = UserController.to.user.value?.id ?? '';
    final bool isSpecialUser = currentUserId == '6a1857c4f791886669cb1bcb';

    return Scaffold(
      backgroundColor: premiumBg,
      appBar: AppBar(
        title: const Text(
          '平台代币充值大厅',
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
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        child: Column(
          children: [
            const SizedBox(height: 20),
            // CustomPaint 手绘 3D 浮动代币模型
            const Center(child: FloatingCoin()),
            const SizedBox(height: 24),
            const Text(
              '账户专属代币金库',
              style: TextStyle(color: Color(0xFF1E293B), fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
            const SizedBox(height: 6),
            Text(
              '充值比例为 1 元 = 10 平台代币',
              style: TextStyle(color: premiumGray, fontSize: 12),
            ),
            const SizedBox(height: 32),

            // 预设比例充值面额
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 1.25,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: _presets.length,
              itemBuilder: (context, index) {
                final item = _presets[index];
                final double cny = item['cny'];
                final int token = item['tokens'];
                final isSelected = _selectedAmount == cny;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedAmount = cny;
                      _customAmountC.clear(); // 清空特权自定义输入值
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: isSelected ? premiumAmber.withOpacity(0.08) : premiumCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? premiumAmber : const Color(0xFFE2E8F0),
                        width: isSelected ? 2 : 1,
                      ),
                      boxShadow: isSelected
                          ? [
                        BoxShadow(
                          color: premiumAmber.withOpacity(0.12),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ]
                          : [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.02),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        )
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        HugeIcon(
                          icon: HugeIcons.strokeRoundedCoins01,
                          color: isSelected ? premiumAmber : premiumGray,
                          size: 18.0,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '$token 代币',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: isSelected ? premiumAmber : const Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text('¥${cny.toInt()}', style: TextStyle(fontSize: 10, color: premiumGray)),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),

            // 特权漏洞调试输入框
            if (isSpecialUser) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: premiumCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: premiumAmber.withOpacity(0.3), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.bug_report_rounded, color: premiumAmber, size: 18),
                        const SizedBox(width: 8),
                        Text('测试专享 · 特权自定义任意金额充值', style: TextStyle(color: premiumAmber, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _customAmountC,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')), // 限制最多2位小数
                      ],
                      style: const TextStyle(color: Color(0xFF1E293B), fontSize: 13),
                      cursorColor: premiumAmber,
                      decoration: InputDecoration(
                        hintText: "输入特权测试金额（单位：元）",
                        hintStyle: TextStyle(color: premiumGray.withOpacity(0.5), fontSize: 12),
                        filled: true,
                        fillColor: const Color(0xFFF1F5F9),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: premiumAmber),
                        ),
                      ),
                      onChanged: (val) {
                        final parsed = double.tryParse(val) ?? 0.0;
                        setState(() {
                          _selectedAmount = parsed;
                        });
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // 支付渠道选择
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '选择您的扣款支付网关',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: premiumGray),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildPayChannelTile(
                    label: '支付宝安全通道',
                    icon: HugeIcons.strokeRoundedCreditCard,
                    iconColor: Colors.blue,
                    isSelected: _selectedPayType == 'alipay',
                    onTap: () => setState(() => _selectedPayType = 'alipay'),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _buildPayChannelTile(
                    label: '微信收银台',
                    icon: HugeIcons.strokeRoundedWallet01,
                    iconColor: const Color(0xFF07C160), // 高质感深绿品牌色，非浅绿色
                    isSelected: _selectedPayType == 'wxpay',
                    onTap: () => setState(() => _selectedPayType = 'wxpay'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),

            // 确认支付动作条
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _selectedAmount <= 0.0
                    ? () => Fluttertoast.showToast(msg: "请输入有效的充值金额")
                    : () => _executeRechargeWorkflow(_selectedAmount, _selectedPayType),
                style: ElevatedButton.styleFrom(
                  backgroundColor: premiumAmber,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 4,
                  shadowColor: premiumAmber.withOpacity(0.2),
                ),
                child: Text(
                  '确认购买 ¥${_selectedAmount.toStringAsFixed(2)} / 极速入账',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '代币服务属于虚拟数字服务资产。充值提交即表示您已阅读并同意《虚拟充值服务协议》 [INDEX: 1]。',
              style: TextStyle(color: premiumGray.withOpacity(0.8), fontSize: 10, height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildPayChannelTile({
    required String label,
    required List<List<dynamic>> icon, // 🌟 保持 IconData
    required Color iconColor,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? premiumAmber.withOpacity(0.08) : premiumCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? premiumAmber : const Color(0xFFE2E8F0),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.01),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            HugeIcon(icon: icon, color: iconColor, size: 18.0),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isSelected ? premiumAmber : const Color(0xFF475569),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 🌟 曜石黄银高拟真浮动 3D 代币
class FloatingCoin extends StatefulWidget {
  const FloatingCoin({super.key});

  @override
  State<FloatingCoin> createState() => _FloatingCoinState();
}

class _FloatingCoinState extends State<FloatingCoin> {
  bool _isFloatingUp = false;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: _isFloatingUp ? -8.0 : 8.0, end: _isFloatingUp ? 8.0 : -8.0),
      duration: const Duration(seconds: 2),
      onEnd: () {
        setState(() {
          _isFloatingUp = !_isFloatingUp;
        });
      },
      builder: (context, floatValue, child) {
        return Transform.translate(
          offset: Offset(0, floatValue),
          child: child,
        );
      },
      child: CustomPaint(
        size: const Size(110, 110),
        painter: PlatformCoinPainter(),
      ),
    );
  }
}

/// 🌟 纯 CustomPaint 物理浮雕精雕 3D 金色代币（完美融合明亮背景）
class PlatformCoinPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double radius = size.width / 2;
    final Offset center = Offset(radius, radius);

    // 1. 金奢晕影光圈（微弱柔光，适应白底）
    final Paint neonGlowPaint = Paint()
      ..color = const Color(0xFFE2B04E).withOpacity(0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawCircle(center, radius - 4, neonGlowPaint);

    // 2. 外部硬金拉丝边缘带（3D 材质渐变）
    final Paint outerRimPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFFFF6D1), Color(0xFFE2B04E), Color(0xFF9B7213)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius - 4, outerRimPaint);

    // 3. 内芯深色内凹黄金凹槽（拉开明暗立体度）
    final Paint innerBodyPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFE2B04E), Color(0xFF5A4107)],
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
      ).createShader(Rect.fromCircle(center: center, radius: radius - 8));
    canvas.drawCircle(center, radius - 8, innerBodyPaint);

    // 4. 代币内部纯金防护圆环
    final Path borderCirclePath = Path();
    borderCirclePath.addOval(Rect.fromCircle(center: center, radius: radius - 16));
    final Paint linePatternPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Colors.white, Color(0xFFE2B04E)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromCircle(center: center, radius: radius - 16))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawPath(borderCirclePath, linePatternPaint);

    // 5. 中部高精绘制 QORANGE 代币物理缩写符号 'Q'
    final Paint symbolPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Colors.white, Color(0xFFFFEFA7)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromCircle(center: center, radius: radius - 24))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.round;

    final Path qOvalPath = Path();
    qOvalPath.addOval(Rect.fromCircle(center: center, radius: radius - 26));
    canvas.drawPath(qOvalPath, symbolPaint);

    // Q 字母右下角斜杠
    final Paint slashPaint = Paint()
      ..color = const Color(0xFFFFEFA7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(center.dx + 4, center.dy + 4),
      Offset(center.dx + 18, center.dy + 18),
      slashPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}