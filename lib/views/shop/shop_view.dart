import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'shop_goods_model.dart';
import 'shop_controller.dart';
import '../community/community_space_view.dart';
import '../post_detail/post_detail_view.dart';

class ShopView extends StatefulWidget {
  const ShopView({super.key});

  @override
  State<ShopView> createState() => _ShopViewState();
}

class _ShopViewState extends State<ShopView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ShopController controller = Get.put(ShopController());

  // 🌟 核心改进：在 Widget 状态类中本地化声明与管理 ScrollController 实例，
  // 保证它们随 Widget 的销毁而精准同步销毁，彻底解决 "ScrollController was used after being disposed" 崩溃
  late ScrollController _allScrollController;
  late ScrollController _postScrollController;
  late ScrollController _groupScrollController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabSelection);

    _allScrollController = ScrollController();
    _postScrollController = ScrollController();
    _groupScrollController = ScrollController();

    _allScrollController.addListener(() => _onScrollListener(_allScrollController, 'all'));
    _postScrollController.addListener(() => _onScrollListener(_postScrollController, 'post'));
    _groupScrollController.addListener(() => _onScrollListener(_groupScrollController, 'group'));

    // 默认初始加载当前选中的页面数据
    controller.loadCategoryData(controller.getCategoryByIndex(_tabController.index));
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
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
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
                          color: controller.primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: HugeIcon(
                          icon: _getCategoryIconData(item.category),
                          color: controller.primaryColor,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
                  const Text('选择支付方式', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 12),
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
                        color: selectedPayType == 'alipay' ? controller.primaryColor.withOpacity(0.02) : Colors.transparent,
                      ),
                      child: Row(
                        children: [
                          const HugeIcon(
                            icon: HugeIcons.strokeRoundedCreditCard,
                            color: Colors.blue,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          const Expanded(child: Text('支付宝支付', style: TextStyle(fontWeight: FontWeight.w600))),
                          if (selectedPayType == 'alipay')
                            Icon(Icons.check_circle, color: controller.primaryColor, size: 20)
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
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
                        color: selectedPayType == 'wxpay' ? controller.primaryColor.withOpacity(0.02) : Colors.transparent,
                      ),
                      child: Row(
                        children: [
                          const HugeIcon(
                            icon: HugeIcons.strokeRoundedWallet01,
                            color: Colors.green,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          const Expanded(child: Text('微信支付', style: TextStyle(fontWeight: FontWeight.w600))),
                          if (selectedPayType == 'wxpay')
                            Icon(Icons.check_circle, color: controller.primaryColor, size: 20)
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('应付总额', style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                          const SizedBox(height: 4),
                          Text(
                            '¥${item.price.toStringAsFixed(2)}',
                            style: TextStyle(color: controller.primaryColor, fontWeight: FontWeight.bold, fontSize: 22),
                          ),
                        ],
                      ),
                      SizedBox(
                        width: 160,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            controller.executePaymentWorkflow(item, selectedPayType);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: controller.primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                          child: const Text('立即购买', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        ),
                      )
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // 🌟 按照用户要求，返回类型依然保持为原版 List<List<dynamic>> 签名结构
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
        child: CircularProgressIndicator(color: controller.primaryColor, strokeWidth: 2),
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
              size: 48,
            ),
            const SizedBox(height: 12),
            Text("商店暂无此品类商品上架", style: TextStyle(color: Colors.grey.shade400)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: controller.loadAllShopData,
      color: controller.primaryColor,
      child: GridView.builder(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
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

          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade100, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.shade200.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                                  size: 48,
                                ),
                              ),
                            )
                          else
                            Center(
                              child: HugeIcon(
                                icon: _getCategoryIconData(item.category),
                                color: controller.primaryColor.withOpacity(0.8),
                                size: 48,
                              ),
                            ),
                          Positioned(
                            left: 12,
                            top: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: controller.primaryColor.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                item.isPurchased
                                    ? '已拥有'
                                    : item.tag,
                                style: TextStyle(
                                  color: item.isPurchased ? Colors.green.shade800 : controller.primaryColor,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
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
                            '¥${item.price.toStringAsFixed(2)}',
                            style: TextStyle(color: controller.primaryColor, fontWeight: FontWeight.w900, fontSize: 15),
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
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                ),
                                child: Text(
                                  item.category == 'group' ? '进入空间' : '阅读内容',
                                  style: TextStyle(color: controller.primaryColor, fontSize: 11, fontWeight: FontWeight.bold),
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
        },
      ),
    );
  }

  Widget _buildBottomIndicator(bool isLoadingMore, bool hasMore) {
    if (isLoadingMore) {
      return Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(color: controller.primaryColor, strokeWidth: 2),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('商店', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.black)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: controller.primaryColor,
          labelColor: controller.primaryColor,
          unselectedLabelColor: Colors.grey,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          tabs: const [
            Tab(text: '全部'),
            Tab(text: '付费帖子'),
            Tab(text: '社群'),
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

/// 🌟 好看配色的交易成功动画页面
class ShopPaymentSuccessPage extends StatefulWidget {
  final Map<String, dynamic> orderDetails;
  final Color primaryColor;
  final VoidCallback onDone;

  const ShopPaymentSuccessPage({
    super.key,
    required this.orderDetails,
    required this.primaryColor,
    required this.onDone,
  });

  @override
  State<ShopPaymentSuccessPage> createState() => _ShopPaymentSuccessPageState();
}

class _ShopPaymentSuccessPageState extends State<ShopPaymentSuccessPage> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _scaleAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.elasticOut,
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.4, 1.0, curve: Curves.easeIn),
      ),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String targetId = widget.orderDetails['goodsId']?.toString() ?? '';
    final String targetType = widget.orderDetails['goodsType']?.toString() ?? '';

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
          child: Column(
            children: [
              const SizedBox(height: 30),
              // 顶部成功的动画绿圆标
              ScaleTransition(
                scale: _scaleAnimation,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: widget.primaryColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Icon(
                      Icons.check_circle_rounded,
                      color: widget.primaryColor,
                      size: 64,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FadeTransition(
                opacity: _fadeAnimation,
                child: const Text(
                  '订单支付成功',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              FadeTransition(
                opacity: _fadeAnimation,
                child: const Text(
                  '商品已成功解锁发货',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              // 订单信息纸质凭证风格卡片
              FadeTransition(
                opacity: _fadeAnimation,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '凭证清单详情',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1, color: Colors.grey),
                      const SizedBox(height: 16),
                      ...widget.orderDetails.entries.map((entry) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${entry.key}:',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: Colors.black54,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${entry.value}',
                                  textAlign: TextAlign.end,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 40),
              // 底部的交互操作响应区
              FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  children: [
                    // 第一动作按钮：若具备快捷入口直接提供路由体验
                    if (targetId.isNotEmpty && (targetType == 'group' || targetType == 'post')) ...[
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: () {
                            widget.onDone(); // 触发静默刷新
                            Get.back(); // 关闭成功页
                            if (targetType == 'group') {
                              Get.to(() => CommunitySpaceView(communityId: targetId));
                            } else if (targetType == 'post') {
                              Get.to(() => PostDetailView(postId: targetId));
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: widget.primaryColor,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            '立即进入体验',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    // 第二动作按钮：回退至商店列表
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: TextButton(
                        onPressed: () {
                          widget.onDone(); // 触发列表刷新
                          Get.back(); // 退出页面
                        },
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.grey.shade100,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          '完成并返回',
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}