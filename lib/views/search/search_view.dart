// lib/views/search/search_view.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 🌟 引入共享首选项用于本地游客数据持久化
import '../../network/http_client.dart';
import '../../user_controller.dart'; // 🌟 引入用户状态管理器
import '../post_detail/post_detail_view.dart';

class SearchView extends StatefulWidget {
  const SearchView({super.key});

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  // 动画控制器，用于舒适的页面初始化入场动效
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  List<dynamic> _searchResults = [];
  List<String> _searchHistory = [];
  final List<String> _trendingTags = [];

  // 游客/首次进入时的示例搜索词，跟随当前语言实时取值
  List<String> get _defaultSearchHistory => [
        'default_search_1'.tr,
        'default_search_2'.tr,
        'default_search_3'.tr,
        'default_search_4'.tr,
        'default_search_5'.tr,
      ];

  bool _isSearching = false;
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();

    // 初始化入场精细物理微动作动画
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutQuart,
    ));
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );

    // 监听输入框焦点变动，实时驱动微动效边框与柔和微光阴影
    _focusNode.addListener(() {
      setState(() {});
    });

    _loadSearchTrends();

    // 自动聚焦搜索框以提供更舒适的入场微动作
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });

    // 启动动画入场
    _animationController.forward();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _animationController.dispose();
    super.dispose();
  }

  // 自适应加载历史搜索：用户走网络云同步，游客走本地磁盘持久化
  Future<void> _loadSearchTrends() async {
    final bool isLoggedIn = UserController.to.isLoggedIn;

    if (isLoggedIn) {
      try {
        final res = await HttpClient.instance.get<Map<String, dynamic>>(
          '/api-posts/search-trends',
        );
        if (res.datas != null) {
          final List<dynamic> history = res.datas!['search_history'] as List? ?? [];
          final List<dynamic> trends = res.datas!['trending_tags'] as List? ?? [];
          setState(() {
            _searchHistory = history.cast<String>();
            _trendingTags.clear();
            _trendingTags.addAll(trends.cast<String>());
          });
          return;
        }
      } catch (e) {
        // 网络请求故障，安全降级到本地加载
      }
    }

    // 游客模式或网络故障：读取本地设备磁盘数据
    await _loadLocalHistory();
  }

  // 游客模式加载设备本地历史记录
  Future<void> _loadLocalHistory() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String>? localHistory = prefs.getStringList('guest_search_history');
      setState(() {
        _searchHistory = localHistory ?? _defaultSearchHistory;
      });
    } catch (_) {
      setState(() {
        _searchHistory = _defaultSearchHistory;
      });
    }
  }

  // 游客模式写入/重排本地历史数据
  Future<void> _saveLocalHistory(String keyword) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      // 先移出已有重合，重新压入首部实现 LRU 时效重拍
      _searchHistory.remove(keyword);
      _searchHistory.insert(0, keyword);
      if (_searchHistory.length > 8) {
        _searchHistory.removeLast();
      }

      await prefs.setStringList('guest_search_history', _searchHistory);
      setState(() {});
    } catch (_) {}
  }

  // 🌟 清空搜索历史（自适应处理）
  Future<void> _clearHistory() async {
    setState(() {
      _searchHistory.clear();
    });

    final bool isLoggedIn = UserController.to.isLoggedIn;
    if (!isLoggedIn) {
      try {
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.remove('guest_search_history');
      } catch (_) {}
    } else {
      // 🌟 登录用户：发起 DELETE 请求，清除云端的搜索历史记录
      try {
        await HttpClient.instance.delete(
          '/api-posts/search-trends',
        );
      } catch (_) {
        // 容错捕获
      }
    }
  }

  // 执行搜索并与后端对齐强检索约束逻辑
  Future<void> _performSearch(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return;

    _searchController.text = trimmed;
    _focusNode.unfocus();

    setState(() {
      _isSearching = true;
      _hasSearched = true;
    });

    final bool isLoggedIn = UserController.to.isLoggedIn;
    if (isLoggedIn) {
      // 登录用户：更新内存历史（后端会在请求 api-posts 自动完成云同步记录）
      if (!_searchHistory.contains(trimmed)) {
        setState(() {
          _searchHistory.insert(0, trimmed);
          if (_searchHistory.length > 8) {
            _searchHistory.removeLast();
          }
        });
      }
    } else {
      // 游客用户：调用 SharedPreferences 本地落盘
      await _saveLocalHistory(trimmed);
    }

    try {
      final res = await HttpClient.instance.get<Map<String, dynamic>>(
        '/api-posts',
        queryParameters: {
          'keyword': trimmed,
          'page': 1,
          'pageSize': 50, // 约束搜集下尽可能全量拉取
        },
      );
      if (res.datas != null) {
        final List<dynamic> posts = res.datas!['posts'] as List? ?? [];
        setState(() {
          _searchResults = posts;
          _isSearching = false;
        });
      } else {
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
      }
    } catch (e) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
    }
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchResults = [];
      _hasSearched = false;
    });
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = const Color.fromRGBO(44, 123, 109, 1.0);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(left: 8.0, right: 16.0),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Get.back(),
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedArrowLeft01,
                  color: Colors.black87,
                ),
              ),
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 46, // 稍微拉高高度，视觉上更显宽松舒适
                  decoration: BoxDecoration(
                    color: _focusNode.hasFocus ? Colors.white : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(23), // 完美的圆角胶囊造型
                    border: Border.all(
                      color: _focusNode.hasFocus ? themeColor : Colors.grey.shade200,
                      width: _focusNode.hasFocus ? 1.5 : 1.0,
                    ),
                    boxShadow: [
                      if (_focusNode.hasFocus)
                        BoxShadow(
                          color: themeColor.withOpacity(0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        )
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 左侧搜索图标
                      const SizedBox(width: 14),
                      HugeIcon(
                        icon: HugeIcons.strokeRoundedSearch01, // 与返回按钮风格统一的线性图标
                        color: _focusNode.hasFocus ? themeColor : Colors.grey.shade400,
                        size: 18,
                      ),
                      const SizedBox(width: 10),

                      // 中间输入框区域
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          focusNode: _focusNode,
                          onSubmitted: _performSearch,
                          textInputAction: TextInputAction.search,
                          textAlign: TextAlign.start, // 🌟 完美对齐：确保输入文本、Hint 及光标指示全靠左对齐 [1]
                          style: const TextStyle(fontSize: 14, color: Colors.black87),
                          decoration: InputDecoration(
                            hintText: 'search_hint'.tr,
                            hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),

                      // 右侧清空按钮 (同样固定占宽 42，与左侧对称，确保 TextField 始终处于精确几何中心)
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _searchController,
                        builder: (context, value, child) {
                          final hasText = value.text.isNotEmpty;
                          return SizedBox(
                            width: 42,
                            child: Center(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 150),
                                transitionBuilder: (child, animation) {
                                  return ScaleTransition(scale: animation, child: child);
                                },
                                child: hasText
                                    ? GestureDetector(
                                  key: const ValueKey('clearButton'),
                                  onTap: _clearSearch,
                                  behavior: HitTestBehavior.opaque,
                                  child: Container(
                                    padding: const EdgeInsets.all(5),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.close_rounded,
                                      size: 13,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                )
                                    : const SizedBox.shrink(key: ValueKey('emptyPlaceholder')),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _buildSearchBody(themeColor),
      ),
    );
  }

  Widget _buildSearchBody(Color themeColor) {
    if (_isSearching) {
      return Center(
        child: CircularProgressIndicator(
          color: themeColor,
          strokeWidth: 2,
        ),
      );
    }

    if (_hasSearched) {
      if (_searchResults.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_off_rounded, size: 64, color: Colors.grey.shade200),
              const SizedBox(height: 14),
              Text(
                'no_search_results'.tr,
                style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              ),
            ],
          ),
        );
      }

      return ListView.separated(
        padding: const EdgeInsets.only(top: 8, bottom: 20),
        itemCount: _searchResults.length,
        separatorBuilder: (context, index) => const SizedBox(height: 4),
        itemBuilder: (context, index) {
          final post = _searchResults[index];
          return _buildAestheticPostItem(post);
        },
      );
    }

    // 🌟 采用呼吸感淡入与缓升（Slide & Fade）效果进行舒适入场包装
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 搜索历史
              if (_searchHistory.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'recent_searches'.tr,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    GestureDetector(
                      onTap: _clearHistory,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Text(
                          'clear_all'.tr,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade400, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _searchHistory.map((history) {
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _performSearch(history),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade100, width: 0.8),
                          ),
                          child: Text(
                            history,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 32),
              ],

              // 热门探索
              Text(
                'trending_categories'.tr,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _trendingTags.map((tag) {
                  return ActionChip(
                    onPressed: () => _performSearch(tag),
                    label: Text(
                      tag.toUpperCase(),
                      style: TextStyle(fontSize: 11, color: themeColor, fontWeight: FontWeight.bold),
                    ),
                    backgroundColor: themeColor.withOpacity(0.06),
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    pressElevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 🌟 与主页视觉高度统一的学术卡片组件
  Widget _buildAestheticPostItem(dynamic post) {
    final themeColor = const Color.fromRGBO(44, 123, 109, 1.0);
    if (post == null || post['id'] == null) return const SizedBox.shrink();

    final author = post['author'] ?? {};
    final authorAvatar = author['avatar'] ?? '';
    final authorNickname = author['nickname'] ?? 'user'.tr;

    final title = post['title'] ?? '';
    final contentMin = post['content_min'] ?? '';

    final likesCount = (post['likes'] as List?)?.length ?? 0;
    final viewsCount = post['views_count'] ?? 0;
    final collectsCount = (post['collects'] as List?)?.length ?? 0;
    final repostsCount = (post['reposts'] as List?)?.length ?? 0;

    final timestamp = post['created_at'] != null
        ? post['created_at'].toString().substring(0, 10)
        : '';
    final thumbnail = post['thumbnail'] ?? '';
    final category = post['category'] ?? 'general';
    final isLiked = post['is_liked'] ?? false;
    final isCollected = post['is_collected'] ?? false;

    final mainHeading = title.isNotEmpty ? title : contentMin;
    final hasSubtitle = title.isNotEmpty && contentMin.isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.015),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Get.to(() => PostDetailView(postId: post['id'] ?? '')),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundImage: authorAvatar.isNotEmpty ? NetworkImage(authorAvatar) : null,
                        backgroundColor: Colors.grey.shade100,
                        child: authorAvatar.isEmpty ? const Icon(Icons.person, size: 12, color: Colors.grey) : null,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        authorNickname,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: themeColor.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          category.toUpperCase(),
                          style: TextStyle(
                            fontSize: 9,
                            color: themeColor,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              mainHeading,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Colors.black,
                                height: 1.35,
                              ),
                            ),
                            if (hasSubtitle) ...[
                              const SizedBox(height: 6),
                              Text(
                                contentMin,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (thumbnail.isNotEmpty) ...[
                        const SizedBox(width: 16),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            thumbnail,
                            width: 70,
                            height: 70,
                            fit: BoxFit.cover,
                            errorBuilder: (c, e, s) => const SizedBox.shrink(),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const HugeIcon(
                        icon: HugeIcons.strokeRoundedCalendar01,
                        color: Colors.grey,
                        size: 13,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        timestamp,
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
                      ),
                      const Spacer(),
                      const HugeIcon(
                        icon: HugeIcons.strokeRoundedView,
                        color: Colors.grey,
                        size: 13,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$viewsCount',
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade400, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 14),
                      HugeIcon(
                        icon: HugeIcons.strokeRoundedFavourite,
                        color: isLiked ? Colors.redAccent : Colors.grey.shade400,
                        size: 13,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$likesCount',
                        style: TextStyle(
                          fontSize: 10,
                          color: isLiked ? Colors.redAccent : Colors.grey.shade400,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 14),
                      HugeIcon(
                        icon: HugeIcons.strokeRoundedBookmark01,
                        color: isCollected ? Colors.orangeAccent : Colors.grey.shade400,
                        size: 13,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$collectsCount',
                        style: TextStyle(
                          fontSize: 10,
                          color: isCollected ? Colors.orangeAccent : Colors.grey.shade400,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const HugeIcon(
                        icon: HugeIcons.strokeRoundedShare01,
                        color: Colors.grey,
                        size: 13,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$repostsCount',
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade400, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}