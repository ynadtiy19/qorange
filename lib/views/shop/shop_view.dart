import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fluttertoast/fluttertoast.dart'; // 🌟 引入 Toast
import '../../network/api_exception.dart';
import '../../network/http_client.dart';
import '../../services/epay_client_service.dart';
import '../../user_controller.dart'; // 🌟 引入用户信息控制器

class ShopView extends StatefulWidget {
  const ShopView({super.key});

  @override
  State<ShopView> createState() => _ShopViewState();
}

class _ShopViewState extends State<ShopView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Color primaryColor = const Color.fromRGBO(44, 123, 109, 1.0);

  // 滚动控制器
  final ScrollController _allScrollController = ScrollController();
  final ScrollController _postScrollController = ScrollController();
  final ScrollController _groupScrollController = ScrollController();
  final ScrollController _tokenScrollController = ScrollController();

  // 商品数据载荷
  List<dynamic> _allGoods = [];
  List<dynamic> _postGoods = [];
  List<dynamic> _groupGoods = [];
  List<dynamic> _tokenGoods = [];

  // 状态维护
  bool _isLoadingAll = true;
  bool _isLoadingPost = true;
  bool _isLoadingGroup = true;
  bool _isLoadingToken = true;

  int _allPage = 1;
  int _postPage = 1;
  int _groupPage = 1;
  int _tokenPage = 1;
  final int _pageSize = 10;

  bool _hasMoreAll = true;
  bool _hasMorePost = true;
  bool _hasMoreGroup = true;
  bool _hasMoreToken = true;

  bool _isLoadingMoreAll = false;
  bool _isLoadingMorePost = false;
  bool _isLoadingMoreGroup = false;
  bool _isLoadingMoreToken = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_handleTabSelection);

    _allScrollController.addListener(() => _onScrollListener(_allScrollController, 'all'));
    _postScrollController.addListener(() => _onScrollListener(_postScrollController, 'post'));
    _groupScrollController.addListener(() => _onScrollListener(_groupScrollController, 'group'));
    _tokenScrollController.addListener(() => _onScrollListener(_tokenScrollController, 'token'));

    // 初始化时仅加载当前选中的 tab 数据
    _loadCategoryData(_getCategoryByIndex(_tabController.index));
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabSelection);
    _tabController.dispose();
    _allScrollController.dispose();
    _postScrollController.dispose();
    _groupScrollController.dispose();
    _tokenScrollController.dispose();
    super.dispose();
  }

  /// 监听 Tab 切换
  void _handleTabSelection() {
    if (!_tabController.indexIsChanging) {
      final category = _getCategoryByIndex(_tabController.index);
      _loadCategoryData(category);
    }
  }

  /// 根据索引获取分类标识
  String _getCategoryByIndex(int index) {
    switch (index) {
      case 0:
        return 'all';
      case 1:
        return 'post';
      case 2:
        return 'group';
      case 3:
        return 'token';
      default:
        return 'all';
    }
  }

  /// 按需加载指定分类的数据（支持静默刷新）
  Future<void> _loadCategoryData(String category) async {
    bool isSilent = false;

    // 如果对应分类已经有数据，则启用静默刷新，不展示大加载菊花
    if (category == 'all' && _allGoods.isNotEmpty) isSilent = true;
    if (category == 'post' && _postGoods.isNotEmpty) isSilent = true;
    if (category == 'group' && _groupGoods.isNotEmpty) isSilent = true;
    if (category == 'token' && _tokenGoods.isNotEmpty) isSilent = true;

    if (!isSilent) {
      setState(() {
        if (category == 'all') _isLoadingAll = true;
        if (category == 'post') _isLoadingPost = true;
        if (category == 'group') _isLoadingGroup = true;
        if (category == 'token') _isLoadingToken = true;
      });
    }

    await _fetchGoods(category: category, isRefresh: true);
  }

  /// 保留的原装加载全部数据的方法
  Future<void> _loadAllShopData() async {
    setState(() {
      _isLoadingAll = true;
      _isLoadingPost = true;
      _isLoadingGroup = true;
      _isLoadingToken = true;
    });
    await Future.wait([
      _fetchGoods(category: 'all', isRefresh: true),
      _fetchGoods(category: 'post', isRefresh: true),
      _fetchGoods(category: 'group', isRefresh: true),
      _fetchGoods(category: 'token', isRefresh: true),
    ]);
  }

  void _onScrollListener(ScrollController controller, String category) {
    if (controller.position.pixels >= controller.position.maxScrollExtent - 200) {
      _fetchMoreGoods(category);
    }
  }

  /// 统一分页异步网络拉取
  Future<void> _fetchGoods({required String category, bool isRefresh = false}) async {
    int targetPage = 1;
    if (!isRefresh) {
      if (category == 'all') targetPage = ++_allPage;
      if (category == 'post') targetPage = ++_postPage;
      if (category == 'group') targetPage = ++_groupPage;
      if (category == 'token') targetPage = ++_tokenPage;
    } else {
      if (category == 'all') _allPage = 1;
      if (category == 'post') _postPage = 1;
      if (category == 'group') _groupPage = 1;
      if (category == 'token') _tokenPage = 1;
    }

    try {
      final res = await HttpClient.instance.get<Map<String, dynamic>>(
        '/api-goods',
        queryParameters: {
          'category': category,
          'page': targetPage,
          'limit': _pageSize,
        },
      );

      // 🌟 使用封装好的实体属性判断
      if (res.respCode == 0 && res.datas != null) {
        final List<dynamic> newGoods = res.datas!['goods'] as List? ?? [];
        setState(() {
          if (category == 'all') {
            if (isRefresh) _allGoods = newGoods; else _allGoods.addAll(newGoods);
            _isLoadingAll = false;
            _isLoadingMoreAll = false;
            _hasMoreAll = newGoods.length >= _pageSize;
          } else if (category == 'post') {
            if (isRefresh) _postGoods = newGoods; else _postGoods.addAll(newGoods);
            _isLoadingPost = false;
            _isLoadingMorePost = false;
            _hasMorePost = newGoods.length >= _pageSize;
          } else if (category == 'group') {
            if (isRefresh) _groupGoods = newGoods; else _groupGoods.addAll(newGoods);
            _isLoadingGroup = false;
            _isLoadingMoreGroup = false;
            _hasMoreGroup = newGoods.length >= _pageSize;
          } else if (category == 'token') {
            if (isRefresh) _tokenGoods = newGoods; else _tokenGoods.addAll(newGoods);
            _isLoadingToken = false;
            _isLoadingMoreToken = false;
            _hasMoreToken = newGoods.length >= _pageSize;
          }
        });
      }
    } catch (_) {
      setState(() {
        _isLoadingAll = false;
        _isLoadingPost = false;
        _isLoadingGroup = false;
        _isLoadingToken = false;
        _isLoadingMoreAll = false;
        _isLoadingMorePost = false;
        _isLoadingMoreGroup = false;
        _isLoadingMoreToken = false;
      });
    }
  }

  Future<void> _fetchMoreGoods(String category) async {
    if (category == 'all' && (_isLoadingMoreAll || !_hasMoreAll || _isLoadingAll)) return;
    if (category == 'post' && (_isLoadingMorePost || !_hasMorePost || _isLoadingPost)) return;
    if (category == 'group' && (_isLoadingMoreGroup || !_hasMoreGroup || _isLoadingGroup)) return;
    if (category == 'token' && (_isLoadingMoreToken || !_hasMoreToken || _isLoadingToken)) return;

    setState(() {
      if (category == 'all') _isLoadingMoreAll = true;
      if (category == 'post') _isLoadingMorePost = true;
      if (category == 'group') _isLoadingMoreGroup = true;
      if (category == 'token') _isLoadingMoreToken = true;
    });

    await _fetchGoods(category: category, isRefresh: false);
  }

  /// 安全外部支付跳转逻辑
  Future<void> _launchExternalBrowser(String urlString) async {
    final url = Uri.parse(urlString);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      // 🌟 移除 Get.snackbar 替换为 Fluttertoast
      Fluttertoast.showToast(msg: "无法启动外部支付页面，请确保手机已安装支付宝或相应浏览器");
    }
  }

  /// 极速付款流程全闭环执行
  Future<void> _executePaymentWorkflow(Map<String, dynamic> item, String selectedPayType) async {
    // 🌟 拦截未登录用户强制要求登录并提示
    if (!UserController.to.isLoggedIn) {
      Fluttertoast.showToast(msg: "请登录后购买");
      return;
    }

    Get.dialog(
      const Center(
        child: CircularProgressIndicator(color: Color.fromRGBO(44, 123, 109, 1.0)),
      ),
      barrierDismissible: false,
    );

    try {
      // 1. 服务器下单，锁定价格
      final orderRes = await HttpClient.instance.post<Map<String, dynamic>>(
        '/api-pay/create_order',
        data: {
          'goodsId': item['id'],
          'goodsType': item['category'],
          'payType': selectedPayType,
        },
      );

      // 🌟 核心调整：利用内置属性进行结果校验，直接获取 inner datas
      if (orderRes.respCode != 0 || orderRes.datas == null) {
        Get.back();
        // 🌟 替换为 Fluttertoast
        Fluttertoast.showToast(msg: orderRes.respMsg ?? '生成系统待支付单失败');
        return;
      }

      final outTradeNo = orderRes.datas!['outTradeNo'];
      final amount = orderRes.datas!['amount'];
      final goodsName = orderRes.datas!['goodsName'];

      // 2. 客户端直连平台发起下单（调用统一网关防墙方案）
      final epay = EpayClientService();
      final epayCreateRes = await epay.createPaymentDirectly(params: {
        'method': 'jump',
        'device': 'mobile',
        'type': selectedPayType,
        'out_trade_no': outTradeNo,
        'name': goodsName,
        'money': amount,
      });

      Get.back(); // 关掉加载框

      if (epayCreateRes['code'] == 0) {
        final payUrl = epayCreateRes['pay_info'] ?? epayCreateRes['pay_url'];
        if (payUrl != null && payUrl.toString().isNotEmpty) {
          // 3. 调起支付页面
          await _launchExternalBrowser(payUrl.toString());

          // 展示支付完成确认框
          _showPaymentCheckDialog(outTradeNo);
        } else {
          // 🌟 替换为 Fluttertoast
          Fluttertoast.showToast(msg: '网关返回参数异常，数据缺失');
        }
      } else {
        // 🌟 替换为 Fluttertoast
        Fluttertoast.showToast(msg: epayCreateRes['msg'] ?? '通道唤起故障');
      }
    } catch (e) {
      Get.back(); // 确保关闭加载圈
      if (e is ApiException) {
        Fluttertoast.showToast(msg: e.message);
      } else {
        // 🌟 替换为 Fluttertoast
        Fluttertoast.showToast(msg: '请求链路异常: $e');
      }
    }
  }

  void _showPaymentCheckDialog(String outTradeNo) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('支付确认', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          content: const Text('请您在打开的页面中完成支付，支付完成后请点击下方按钮。', style: TextStyle(fontSize: 13, height: 1.4)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('已取消付款', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _verifyPaymentOnBackend(outTradeNo);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('我已支付完成', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  /// 极速付款安全校验闭环，向国外服务器提交原装签名账本
  Future<void> _verifyPaymentOnBackend(String outTradeNo) async {
    Get.dialog(
      const Center(
        child: CircularProgressIndicator(color: Color.fromRGBO(44, 123, 109, 1.0)),
      ),
      barrierDismissible: false,
    );

    try {
      final epay = EpayClientService();
      // 客户端直连国内获取账本
      final realEpayData = await epay.queryOrderDirectly(outTradeNo: outTradeNo);

      // 将原装签名账本传送给 Zeabur 后台解锁内容
      final verifyRes = await HttpClient.instance.post<Map<String, dynamic>>(
        '/api-pay/verify_payment',
        data: {'epay_response': realEpayData},
      );

      Get.back();

      // 🌟 核心调整：利用内置属性进行结果校验与弹窗信息组装展示，排除外层多余解析
      if (verifyRes.respCode == 0 && verifyRes.datas != null) {
        // 🌟 绘制一连串精美原生弹窗，平铺展示返回的 datas 所有核心参数
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            final Map<String, dynamic> responseDetails = Map<String, dynamic>.from(verifyRes.datas!);

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Color.fromRGBO(44, 123, 109, 1.0), size: 24),
                  SizedBox(width: 8),
                  Text('支付验证成功', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '商品已完成安全发货并解锁，以下为订单返回数据详情：',
                      style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: responseDetails.entries.map((entry) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${entry.key}: ',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: Colors.black87,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    '${entry.value}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    // 重新加载当前选中的 tab 数据
                    _loadCategoryData(_getCategoryByIndex(_tabController.index));
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('完成', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      } else {
        // 🌟 替换为 Fluttertoast
        Fluttertoast.showToast(msg: verifyRes.respMsg ?? '账单解密验签未通过');
      }
    } catch (e) {
      Get.back(); // 确保关闭加载圈
      if (e is ApiException) {
        Fluttertoast.showToast(msg: e.message);
      } else {
        // 🌟 替换为 Fluttertoast
        Fluttertoast.showToast(msg: '无法连接发货验证网关: $e');
      }
    }
  }

  void _showPurchaseSheet(Map<String, dynamic> item) {
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
                            color: primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: HugeIcon(
                            icon: _getCategoryIcon(item['category']?.toString()),
                            color: primaryColor,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item['title'].toString(),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item['desc'].toString(),
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
                            color: selectedPayType == 'alipay' ? primaryColor : Colors.grey.shade200,
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          color: selectedPayType == 'alipay' ? primaryColor.withOpacity(0.02) : Colors.transparent,
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
                              Icon(Icons.check_circle, color: primaryColor, size: 20)
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
                            color: selectedPayType == 'wxpay' ? primaryColor : Colors.grey.shade200,
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          color: selectedPayType == 'wxpay' ? primaryColor.withOpacity(0.02) : Colors.transparent,
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
                              Icon(Icons.check_circle, color: primaryColor, size: 20)
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
                              '¥${double.tryParse(item['price'].toString())?.toStringAsFixed(2) ?? '0.00'}',
                              style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 22),
                            ),
                          ],
                        ),
                        SizedBox(
                          width: 160,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              _executePaymentWorkflow(item, selectedPayType);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
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
        }
    );
  }

  List<List<dynamic>> _getCategoryIcon(String? category) {
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
    required List<dynamic> goods,
    required bool isLoading,
    required ScrollController scrollController,
    required bool hasMore,
    required bool isLoadingMore,
    required String categoryCode,
  }) {
    if (isLoading) {
      return Center(
        child: CircularProgressIndicator(color: primaryColor, strokeWidth: 2),
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
      onRefresh: _loadAllShopData,
      color: primaryColor,
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
          final price = double.tryParse(item['price']?.toString() ?? '0') ?? 0.0;
          final category = item['category']?.toString() ?? 'virtual';

          // 🌟 读取后端同步重组装回来的帖子封面/商品大图 URL
          final imageUrl = item['image_url']?.toString() ?? '';

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
                      color: primaryColor.withOpacity(0.04),
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
                        fit: StackFit.expand, // 使大图完美平铺铺满卡片顶部
                        children: [
                          // 🌟 核心美化升级：若该付费帖子或常规商品在云端含有真实大图封面，优先渲染封面，实现小红书/美学商店级别的高级质感；无图则无缝降级展示大类默认小图标
                          if (imageUrl.isNotEmpty)
                            Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (c, e, s) => Center(
                                child: HugeIcon(
                                  icon: _getCategoryIcon(category),
                                  color: primaryColor.withOpacity(0.8),
                                  size: 48,
                                ),
                              ),
                            )
                          else
                            Center(
                              child: HugeIcon(
                                icon: _getCategoryIcon(category),
                                color: primaryColor.withOpacity(0.8),
                                size: 48,
                              ),
                            ),
                          Positioned(
                            left: 12,
                            top: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: primaryColor.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                item['tag']?.toString() ?? '热卖',
                                style: TextStyle(color: primaryColor, fontSize: 9, fontWeight: FontWeight.bold),
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
                        item['title']?.toString() ?? '商品',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item['desc']?.toString() ?? '无详细描述',
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 10),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '¥${price.toStringAsFixed(2)}',
                            style: TextStyle(color: primaryColor, fontWeight: FontWeight.w900, fontSize: 15),
                          ),
                          InkWell(
                            onTap: () => _showPurchaseSheet(item),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: primaryColor,
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
          child: CircularProgressIndicator(color: primaryColor, strokeWidth: 2),
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
        title: const Text('美学生活商店', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.black)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: primaryColor,
          labelColor: primaryColor,
          unselectedLabelColor: Colors.grey,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          tabs: const [
            Tab(text: '全部'),
            Tab(text: '付费帖子'),
            Tab(text: '付费社群'),
            Tab(text: '代币充值'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildProductGrid(
            goods: _allGoods,
            isLoading: _isLoadingAll,
            scrollController: _allScrollController,
            hasMore: _hasMoreAll,
            isLoadingMore: _isLoadingMoreAll,
            categoryCode: 'all',
          ),
          _buildProductGrid(
            goods: _postGoods,
            isLoading: _isLoadingPost,
            scrollController: _postScrollController,
            hasMore: _hasMorePost,
            isLoadingMore: _isLoadingMorePost,
            categoryCode: 'post',
          ),
          _buildProductGrid(
            goods: _groupGoods,
            isLoading: _isLoadingGroup,
            scrollController: _groupScrollController,
            hasMore: _hasMoreGroup,
            isLoadingMore: _isLoadingMoreGroup,
            categoryCode: 'group',
          ),
          _buildProductGrid(
            goods: _tokenGoods,
            isLoading: _isLoadingToken,
            scrollController: _tokenScrollController,
            hasMore: _hasMoreToken,
            isLoadingMore: _isLoadingMoreToken,
            categoryCode: 'token',
          ),
        ],
      ),
    );
  }
}