import 'dart:convert';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 表情数据模型
class EmojiItem {
  final String emoji;
  final String name;
  final String slug;

  EmojiItem({required this.emoji, required this.name, required this.slug});

  factory EmojiItem.fromJson(Map<String, dynamic> json) {
    return EmojiItem(
      emoji: json['emoji'] ?? '',
      name: json['name'] ?? '',
      slug: json['slug'] ?? '',
    );
  }
}

class EmojiCategory {
  final String name;
  final String slug;
  final List<EmojiItem> emojis;

  EmojiCategory({required this.name, required this.slug, required this.emojis});

  factory EmojiCategory.fromJson(Map<String, dynamic> json) {
    var list = json['emojis'] as List? ?? [];
    List<EmojiItem> emojiList = list.map((e) => EmojiItem.fromJson(e)).toList();
    return EmojiCategory(
      name: json['name'] ?? '',
      slug: json['slug'] ?? '',
      emojis: emojiList,
    );
  }
}

/// 高颜值交互表情选择器
class ModernEmojiPicker extends StatefulWidget {
  final Function(String emoji) onEmojiSelected;

  const ModernEmojiPicker({super.key, required this.onEmojiSelected});

  @override
  State<ModernEmojiPicker> createState() => _ModernEmojiPickerState();
}

class _ModernEmojiPickerState extends State<ModernEmojiPicker> with SingleTickerProviderStateMixin {
  List<EmojiCategory> _categories = [];
  Map<String, dynamic> _keywordsMap = {};
  List<String> _recentEmojis = [];
  bool _isLoading = true;

  // 搜索与分类控制
  late PageController _pageController;
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<EmojiItem> _searchResults = [];
  bool _isSearching = false;

  // 配色定义 (经典森系复古绿美学)
  final Color _primaryColor = const Color(0xFF2D6A4F); // 经典桉树深绿
  final Color _accentColor = const Color(0xFF74C69D); // 柔和鼠尾草浅绿
  final Color _backgroundColor = const Color(0xFFF4F9F5); // 极淡暖绿白底色
  final Color _slateGrey = const Color(0xFF64748B); // 温暖石板灰字色
  final Color _lightSlateGrey = const Color(0xFF94A3B8); // 辅助浅字色
  final Color _emptyStateIconColor = const Color(0xFFCBD5E1); // 空状态图标灰色

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadData();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _tabController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// 异步加载资产文件与最近常用
  Future<void> _loadData() async {
    try {
      // 1. 加载分类文件
      String categoriesStr = await rootBundle.loadString('assets/emojis-by-group.json');
      List<dynamic> categoriesJson = jsonDecode(categoriesStr);
      List<EmojiCategory> loadedCategories = categoriesJson.map((e) => EmojiCategory.fromJson(e)).toList();

      // 2. 加载搜索关键词文件
      String keywordsStr = await rootBundle.loadString('assets/emoji-keywords.json');
      _keywordsMap = jsonDecode(keywordsStr);

      // 3. 读取最近使用的表情
      final prefs = await SharedPreferences.getInstance();
      _recentEmojis = prefs.getStringList('recent_emojis') ?? [];

      setState(() {
        _categories = loadedCategories;
        // 初始化 TabController (分类数 + 1个最近常用)
        _tabController = TabController(length: _categories.length + 1, vsync: this);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("加载表情数据失败: $e");
    }
  }

  /// 保存常用表情逻辑
  Future<void> _saveRecentEmoji(String emoji) async {
    if (_recentEmojis.contains(emoji)) {
      _recentEmojis.remove(emoji);
    }
    _recentEmojis.insert(0, emoji);
    if (_recentEmojis.length > 28) {
      _recentEmojis = _recentEmojis.sublist(0, 28); // 最多保留28个（大约4行）
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('recent_emojis', _recentEmojis);
    setState(() {});
  }

  /// 搜索本地过滤
  void _onSearchChanged(String query) {
    if (query.trim().isEmpty) {
      setState(() {
        _isSearching = false;
        _searchResults = [];
      });
      return;
    }

    List<EmojiItem> results = [];
    String lowerQuery = query.toLowerCase();

    // 结合名字、slug 以及本地关联的关键字进行搜索
    for (var category in _categories) {
      for (var emojiItem in category.emojis) {
        bool matchesName = emojiItem.name.toLowerCase().contains(lowerQuery);
        bool matchesSlug = emojiItem.slug.toLowerCase().contains(lowerQuery);

        // 匹配关联关键字
        bool matchesKeywords = false;
        List<dynamic>? keywords = _keywordsMap[emojiItem.emoji];
        if (keywords != null) {
          matchesKeywords = keywords.any((kw) => kw.toString().toLowerCase().contains(lowerQuery));
        }

        if (matchesName || matchesSlug || matchesKeywords) {
          if (!results.any((element) => element.emoji == emojiItem.emoji)) {
            results.add(emojiItem);
          }
        }
      }
    }

    setState(() {
      _isSearching = true;
      _searchResults = results;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: 380,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Center(child: CircularProgressIndicator(color: _primaryColor)),
      );
    }

    // 获取当前软键盘的高度
    final double keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedPadding(
      padding: EdgeInsets.only(bottom: keyboardHeight),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutQuad,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15), // 增强的高级毛玻璃模糊度
        child: Container(
          height: 410,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.90), // 微透乳绿暖白
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: Colors.white.withOpacity(0.5), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: _primaryColor.withOpacity(0.04),
                blurRadius: 20,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                // 1. 顶部精致拖拽把手
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 36,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: _primaryColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(2.25),
                  ),
                ),

                // 2. 交互式现代搜索框设计
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                  child: Container(
                    height: 42,
                    decoration: BoxDecoration(
                      color: _searchFocusNode.hasFocus
                          ? Colors.white
                          : _primaryColor.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _searchFocusNode.hasFocus
                            ? _accentColor.withOpacity(0.7)
                            : Colors.transparent,
                        width: 1.5,
                      ),
                      boxShadow: _searchFocusNode.hasFocus
                          ? [
                        BoxShadow(
                          color: _primaryColor.withOpacity(0.06),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        )
                      ]
                          : [],
                    ),
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      onChanged: _onSearchChanged,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: _slateGrey),
                      decoration: InputDecoration(
                        hintText: "搜索你想要的表情...",
                        hintStyle: TextStyle(
                          color: _lightSlateGrey.withOpacity(0.8),
                          fontSize: 13,
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: _searchFocusNode.hasFocus ? _primaryColor : _lightSlateGrey,
                          size: 20,
                        ),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            _onSearchChanged("");
                          },
                          child: Icon(
                            Icons.cancel_rounded,
                            color: _lightSlateGrey,
                            size: 18,
                          ),
                        )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 10),
                const Divider(height: 1, color: Color(0xFFE6F0EA)),

                // 3. 主体内容展示区域
                Expanded(
                  child: Container(
                    color: _backgroundColor,
                    child: _isSearching
                        ? (_searchResults.isEmpty ? _buildEmptySearchState() : _buildGrid(_searchResults))
                        : _buildPageView(),
                  ),
                ),

                // 4. 底部联动胶囊导航栏
                if (!_isSearching) ...[
                  const Divider(height: 1, color: Color(0xFFE6F0EA)),
                  Container(
                    color: Colors.white,
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      physics: const BouncingScrollPhysics(),
                      // 胶囊式背景指示器
                      indicator: BoxDecoration(
                        color: _primaryColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      labelColor: _primaryColor,
                      unselectedLabelColor: _lightSlateGrey,
                      onTap: (index) {
                        _pageController.animateToPage(
                          index,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOutCubic,
                        );
                      },
                      tabs: [
                        const Tab(
                          height: 36,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8.0),
                            child: Icon(Icons.history_rounded, size: 20),
                          ),
                        ), // 最近常用
                        ..._categories.map((cat) => Tab(
                          height: 36,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10.0),
                            child: Text(
                              _getCategoryEmoji(cat.slug),
                              style: const TextStyle(fontSize: 18, fontFamily: 'Apple Color Emoji'),
                            ),
                          ),
                        )),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 页面左右滑动承载器
  Widget _buildPageView() {
    return PageView.builder(
      controller: _pageController,
      onPageChanged: (index) {
        _tabController.animateTo(index);
      },
      itemCount: _categories.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          // 最近常用虚拟页
          if (_recentEmojis.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_rounded, size: 40, color: _emptyStateIconColor),
                  const SizedBox(height: 8),
                  Text(
                    "暂无最近使用的表情",
                    style: TextStyle(color: _lightSlateGrey, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            );
          }
          return _buildGrid(_recentEmojis.map((e) => EmojiItem(emoji: e, name: '', slug: '')).toList());
        } else {
          // 常规分类页
          var category = _categories[index - 1];
          return _buildGrid(category.emojis);
        }
      },
    );
  }

  /// 统一的表情网格布局
  Widget _buildGrid(List<EmojiItem> emojis) {
    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7, // 每行7个表情，黄金间距
        crossAxisSpacing: 8,
        mainAxisSpacing: 10,
        childAspectRatio: 1.0,
      ),
      itemCount: emojis.length,
      itemBuilder: (context, index) {
        return _EmojiButton(
          emojiItem: emojis[index],
          onTap: (emoji) {
            HapticFeedback.lightImpact(); // 轻微震动交互回馈
            widget.onEmojiSelected(emoji);
            _saveRecentEmoji(emoji);
          },
        );
      },
    );
  }

  /// 搜索无结果时的空状态设计
  Widget _buildEmptySearchState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 48, color: _emptyStateIconColor),
          const SizedBox(height: 8),
          Text(
            "未找到相关表情",
            style: TextStyle(
              color: _slateGrey,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "试着换个词搜搜看吧",
            style: TextStyle(
              color: _lightSlateGrey,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  /// 依据大类 slug 匹配直观的展示表情符号
  String _getCategoryEmoji(String slug) {
    switch (slug) {
      case 'smileys_people':
        return '😀';
      case 'animals_nature':
        return '🦊';
      case 'food_drink':
        return '🍔';
      case 'travel_places':
        return '✈️';
      case 'activities':
        return '🎈';
      case 'objects':
        return '💡';
      case 'symbols':
        return '🔣';
      case 'flags':
        return '🏳️';
      default:
        return '✨';
    }
  }
}

/// 单个表情弹性缩放动画微交互按钮
class _EmojiButton extends StatefulWidget {
  final EmojiItem emojiItem;
  final Function(String emoji) onTap;

  const _EmojiButton({required this.emojiItem, required this.onTap});

  @override
  State<_EmojiButton> createState() => _EmojiButtonState();
}

class _EmojiButtonState extends State<_EmojiButton> with SingleTickerProviderStateMixin {
  double _scale = 1.0;
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
      lowerBound: 0.0,
      upperBound: 0.16, // 轻微缩放增强打击感
    )..addListener(() {
      setState(() {
        _scale = 1.0 - _controller.value;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap(widget.emojiItem.emoji);
      },
      onTapCancel: () => _controller.reverse(),
      child: Transform.scale(
        scale: _scale,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            widget.emojiItem.emoji,
            style: const TextStyle(
              fontSize: 28, // 放大字号更易看清
              fontFamily: 'Apple Color Emoji',
            ),
          ),
        ),
      ),
    );
  }
}