// lib/views/shop/shop_view.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'shop_goods_model.dart';
import 'shop_controller.dart';
import 'confetti_celebration_overlay.dart';
import '../community/community_space_view.dart';
import '../post_detail/post_detail_view.dart';

class ShopView extends StatefulWidget {
  const ShopView({super.key});

  @override
  State<ShopView> createState() => _ShopViewState();
}

class _ShopViewState extends State<ShopView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late final ShopController controller;

  late ScrollController _allScrollController;
  late ScrollController _postScrollController;
  late ScrollController _groupScrollController;

  @override
  void initState() {
    super.initState();
    controller = Get.isRegistered<ShopController>()
        ? Get.find<ShopController>()
        : Get.put(ShopController());

    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabSelection);

    _allScrollController = ScrollController();
    _postScrollController = ScrollController();
    _groupScrollController = ScrollController();

    _allScrollController.addListener(() => _onScrollListener(_allScrollController, 'all'));
    _postScrollController.addListener(() => _onScrollListener(_postScrollController, 'post'));
    _groupScrollController.addListener(() => _onScrollListener(_groupScrollController, 'group'));
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabSelection);
    _tabController.dispose();
    _allScrollController.dispose();
    _postScrollController.dispose();
    _groupScrollController.dispose();
    super.dispose();
  }

  void _onScrollListener(ScrollController scrollController, String category) {
    if (scrollController.position.pixels >= scrollController.position.maxScrollExtent - 200) {
      controller.fetchMoreGoods(category);
    }
  }

  void _handleTabSelection() {
    if (!_tabController.indexIsChanging) {
      final category = controller.getCategoryByIndex(_tabController.index);
      controller.loadCategoryData(category);
    }
  }

  /// 🌟 自动平滑滚动并将刚刚购买的商品高亮居中展示
  void _scrollToPurchasedItem(String goodsId) {
    if (goodsId.isEmpty) return;

    final currentCategoryIndex = _tabController.index;
    ScrollController activeController;
    List<ShopGoods> activeList;

    if (currentCategoryIndex == 0) {
      activeController = _allScrollController;
      activeList = controller.allGoods;
    } else if (currentCategoryIndex == 1) {
      activeController = _postScrollController;
      activeList = controller.postGoods;
    } else {
      activeController = _groupScrollController;
      activeList = controller.groupGoods;
    }

    final targetIndex = activeList.indexWhere((item) => item.id == goodsId);
    if (targetIndex == -1 || !activeController.hasClients) return;

    final screenWidth = MediaQuery.of(context).size.width;
    final itemWidth = (screenWidth - 48) / 2;
    final itemHeight = itemWidth / 0.72;
    final rowIndex = targetIndex ~/ 2;
    final targetOffset = rowIndex * (itemHeight + 16.0);

    Future.delayed(const Duration(milliseconds: 250), () {
      if (activeController.hasClients) {
        activeController.animateTo(
          targetOffset.clamp(0.0, activeController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
        );
      }
    });

    // 4 秒后自动清除高亮边框
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && controller.highlightedGoodsId.value == goodsId) {
        controller.highlightedGoodsId.value = '';
      }
    });
  }

  /// 🌟 步骤 1：选择支付方式底部弹窗
  void _showPurchaseSheet(ShopGoods item) {
    String selectedPayType = 'alipay';

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(28),
                  topRight: Radius.circular(28),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: controller.primaryColor.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: HugeIcon(
                          icon: _getCategoryIconData(item.category),
                          color: controller.primaryColor,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF0F172A)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.desc,
                              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      )
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text('select_payment_method'.tr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B))),
                  const SizedBox(height: 12),
                  // 支付宝选项
                  InkWell(
                    onTap: () => setModalState(() => selectedPayType = 'alipay'),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: selectedPayType == 'alipay' ? controller.primaryColor : Colors.grey.shade200,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        color: selectedPayType == 'alipay' ? controller.primaryColor.withOpacity(0.03) : Colors.transparent,
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: const Color(0xFF1677FF).withOpacity(0.1), shape: BoxShape.circle),
                            child: const HugeIcon(icon: HugeIcons.strokeRoundedCreditCard, color: Color(0xFF1677FF), size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('alipay'.tr, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                const SizedBox(height: 2),
                                Text('支持快捷安全跳转支付', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                              ],
                            ),
                          ),
                          if (selectedPayType == 'alipay')
                            Icon(Icons.check_circle_rounded, color: controller.primaryColor, size: 22)
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 微信支付选项
                  InkWell(
                    onTap: () => setModalState(() => selectedPayType = 'wxpay'),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: selectedPayType == 'wxpay' ? controller.primaryColor : Colors.grey.shade200,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        color: selectedPayType == 'wxpay' ? controller.primaryColor.withOpacity(0.03) : Colors.transparent,
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: const Color(0xFF07C160).withOpacity(0.1), shape: BoxShape.circle),
                            child: const HugeIcon(icon: HugeIcons.strokeRoundedWallet01, color: Color(0xFF07C160), size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('wechat_pay'.tr, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                const SizedBox(height: 2),
                                Text('微信扫码或 App 跳转支付', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                              ],
                            ),
                          ),
                          if (selectedPayType == 'wxpay')
                            Icon(Icons.check_circle_rounded, color: controller.primaryColor, size: 22)
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('total_due'.tr, style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 2),
                          Text(
                            item.price <= 0 ? '免费' : '¥${item.price.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: item.price <= 0 ? const Color(0xFF059669) : controller.primaryColor,
                              fontWeight: FontWeight.w900,
                              fontSize: 22,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(
                        width: 160,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () async {
                            // 🌟 1. 立即关闭当前选择弹窗
                            Navigator.pop(context);
                            // 🌟 2. 唤起不可被手势关闭的支付监听弹窗
                            _showPaymentPollingSheet(item, selectedPayType);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: controller.primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                          child: Text('buy_now'.tr, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        ),
                      )
                    ],
                  ),
                  SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// 🌟 步骤 2：沉浸式支付中与自动轮询状态底部弹窗（不可由手势或点击外围关闭）
  void _showPaymentPollingSheet(ShopGoods item, String selectedPayType) {
    // 启动支付与轮询
    controller.startPaymentWorkflow(item, selectedPayType);

    showModalBottomSheet<void>(
      context: context,
      isDismissible: false,    // 禁止点击外围关闭
      enableDrag: false,       // 禁止下滑手势拖拽关闭
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (bottomSheetContext) {
        return PopScope(
          canPop: false, // 拦截物理返回键
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(32),
                topRight: Radius.circular(32),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Obx(() {
              final status = controller.paymentStatus.value;
              final msg = controller.paymentStatusMessage.value;

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 顶部呼吸指示条
                  Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // 核心动效区域（等待波纹 / 成功勾选 / 失败重试）
                  if (status == PaymentProcessingStatus.waiting) ...[
                    _buildRadarWaitingIndicator(),
                    const SizedBox(height: 24),
                    const Text(
                      '正在安全同步支付结果',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        msg,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.4),
                      ),
                    ),
                  ] else if (status == PaymentProcessingStatus.success) ...[
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: controller.primaryColor.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Icon(Icons.check_circle_rounded, color: controller.primaryColor, size: 56),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      '支付成功，权益已解锁',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '《${item.title}》已成功绑定至您的账号',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                  ] else ...[
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Icon(Icons.error_outline_rounded, color: Colors.red.shade400, size: 52),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      '支付未完成或检测超时',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        msg.isNotEmpty ? msg : '如已扣款，系统将稍后自动补单同步。',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.4),
                      ),
                    ),
                  ],

                  const SizedBox(height: 32),

                  // 底部操作按钮区域
                  if (status == PaymentProcessingStatus.success) ...[
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () {
                          // 🌟 1. 关闭底部弹窗
                          Navigator.pop(bottomSheetContext);

                          // 🌟 2. 屏幕中央释放全自绘制烟花彩带特效
                          ConfettiCelebrationOverlay.show(
                            context,
                            title: '恭喜！解锁成功 🎉',
                            subtitle: '《${item.title}》现已生效',
                            onFinished: () {
                              // 🌟 3. 动画完成后自动平滑滚动并高亮该卡片
                              _scrollToPurchasedItem(item.id);
                            },
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: controller.primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: const Text('完成', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ),
                  ] else if (status == PaymentProcessingStatus.waiting) ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              controller.cancelPolling();
                              Navigator.pop(bottomSheetContext);
                            },
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.grey.shade300),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Text('放弃支付', style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              if (controller.currentOutTradeNo != null) {
                                controller.verifyPaymentOnBackend(controller.currentOutTradeNo!, isSilent: false);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: controller.primaryColor,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              elevation: 0,
                            ),
                            child: const Text('我已完成支付', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () {
                          controller.cancelPolling();
                          Navigator.pop(bottomSheetContext);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade100,
                          foregroundColor: Colors.black87,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: const Text('关闭返回', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                    ),
                  ],

                  SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
                ],
              );
            }),
          ),
        );
      },
    );
  }

  /// 优雅的雷达脉冲呼吸加载指示部件
  Widget _buildRadarWaitingIndicator() {
    return SizedBox(
      width: 90,
      height: 90,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 80,
            height: 80,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(controller.primaryColor.withOpacity(0.3)),
            ),
          ),
          SizedBox(
            width: 80,
            height: 80,
            child: CircularProgressIndicator(
              strokeWidth: 3.5,
              valueColor: AlwaysStoppedAnimation<Color>(controller.primaryColor),
              strokeCap: StrokeCap.round,
            ),
          ),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: controller.primaryColor.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: HugeIcon(
                icon: HugeIcons.strokeRoundedCreditCard,
                color: controller.primaryColor,
                size: 26,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<List<dynamic>> _getCategoryIconData(String? category) {
    if (category == 'post') {
      return HugeIcons.strokeRoundedBookOpen02;
    } else if (category == 'group') {
      return HugeIcons.strokeRoundedUserGroup;
    } else if (category == 'token') {
      return HugeIcons.strokeRoundedCoins01;
    } else {
      return HugeIcons.strokeRoundedBug02;
    }
  }

  Widget _buildProductGrid({
    required List<ShopGoods> goods,
    required bool isLoading,
    required ScrollController scrollController,
    required bool hasMore,
    required bool isLoadingMore,
    required String categoryCode,
  }) {
    if (isLoading) {
      return Center(
        child: CircularProgressIndicator(color: controller.primaryColor, strokeWidth: 2.5),
      );
    }
    if (goods.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedShoppingBag01,
              color: Colors.grey.shade300,
              size: 54,
            ),
            const SizedBox(height: 14),
            Text('shop_empty_category'.tr, style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: controller.loadAllShopData,
      color: controller.primaryColor,
      child: GridView.builder(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.all(16),
        itemCount: goods.length + 1,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.72,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemBuilder: (context, index) {
          if (index == goods.length) {
            return _buildBottomIndicator(isLoadingMore, hasMore);
          }

          final item = goods[index];

          return Obx(() {
            final isHighlighted = controller.highlightedGoodsId.value == item.id;

            return AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: isHighlighted ? controller.primaryColor : Colors.grey.shade100,
                  width: isHighlighted ? 2.2 : 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isHighlighted
                        ? controller.primaryColor.withOpacity(0.25)
                        : Colors.grey.shade200.withOpacity(0.35),
                    blurRadius: isHighlighted ? 18 : 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 图片与标签
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: controller.primaryColor.withOpacity(0.04),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(20),
                          topRight: Radius.circular(20),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(20),
                          topRight: Radius.circular(20),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (item.imageUrl.isNotEmpty)
                              Image.network(
                                item.imageUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (c, e, s) => Center(
                                  child: HugeIcon(
                                    icon: _getCategoryIconData(item.category),
                                    color: controller.primaryColor.withOpacity(0.8),
                                    size: 44,
                                  ),
                                ),
                              )
                            else
                              Center(
                                child: HugeIcon(
                                  icon: _getCategoryIconData(item.category),
                                  color: controller.primaryColor.withOpacity(0.8),
                                  size: 44,
                                ),
                              ),
                            Positioned(
                              left: 10,
                              top: 10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: item.isPurchased
                                      ? const Color(0xFF059669).withOpacity(0.14)
                                      : controller.primaryColor.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  item.isPurchased ? 'owned'.tr : item.tag,
                                  style: TextStyle(
                                    color: item.isPurchased ? const Color(0xFF059669) : controller.primaryColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            )
                          ],
                        ),
                      ),
                    ),
                  ),

                  // 内容详情
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF0F172A)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.desc,
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 10),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              item.price <= 0 ? '免费' : '¥${item.price.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: item.price <= 0 ? const Color(0xFF059669) : controller.primaryColor, // 免费可使用清爽的绿色或保持主题色
                                fontWeight: FontWeight.w900,
                                fontSize: item.price <= 0 ? 14 : 15,
                              ),
                            ),
                            if (item.isPurchased || item.price <= 0)
                              SizedBox(
                                height: 28,
                                child: TextButton(
                                  onPressed: () {
                                    final String targetId = item.targetId;
                                    if (item.category == 'group' && targetId.isNotEmpty) {
                                      Get.to(() => CommunitySpaceView(communityId: targetId));
                                    } else if (item.category == 'post' && targetId.isNotEmpty) {
                                      Get.to(() => PostDetailView(postId: targetId));
                                    }
                                  },
                                  style: TextButton.styleFrom(
                                    backgroundColor: controller.primaryColor.withOpacity(0.1),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                  ),
                                  child: Text(
                                    item.category == 'group' ? 'enter_space'.tr : 'read_content'.tr,
                                    style: TextStyle(color: controller.primaryColor, fontSize: 11, fontWeight: FontWeight.w800),
                                  ),
                                ),
                              )
                            else
                              InkWell(
                                onTap: () => _showPurchaseSheet(item),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: controller.primaryColor,
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: [
                                      BoxShadow(
                                        color: controller.primaryColor.withOpacity(0.3),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(Icons.add, color: Colors.white, size: 16),
                                ),
                              )
                          ],
                        )
                      ],
                    ),
                  )
                ],
              ),
            );
          });
        },
      ),
    );
  }

  Widget _buildBottomIndicator(bool isLoadingMore, bool hasMore) {
    if (isLoadingMore) {
      return Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(color: controller.primaryColor, strokeWidth: 2),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          'shop_title'.tr,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: Color(0xFF0F172A)),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: controller.primaryColor,
          indicatorWeight: 2.5,
          labelColor: controller.primaryColor,
          unselectedLabelColor: Colors.grey.shade500,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          tabs: [
            Tab(text: 'shop_tab_all'.tr),
            Tab(text: 'shop_tab_posts'.tr),
            Tab(text: 'shop_tab_communities'.tr),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          Obx(() => _buildProductGrid(
            goods: controller.allGoods,
            isLoading: controller.isLoadingAll.value,
            scrollController: _allScrollController,
            hasMore: controller.hasMoreAll.value,
            isLoadingMore: controller.isLoadingMoreAll.value,
            categoryCode: 'all',
          )),
          Obx(() => _buildProductGrid(
            goods: controller.postGoods,
            isLoading: controller.isLoadingPost.value,
            scrollController: _postScrollController,
            hasMore: controller.hasMorePost.value,
            isLoadingMore: controller.isLoadingMorePost.value,
            categoryCode: 'post',
          )),
          Obx(() => _buildProductGrid(
            goods: controller.groupGoods,
            isLoading: controller.isLoadingGroup.value,
            scrollController: _groupScrollController,
            hasMore: controller.hasMoreGroup.value,
            isLoadingMore: controller.isLoadingMoreGroup.value,
            categoryCode: 'group',
          )),
        ],
      ),
    );
  }
}