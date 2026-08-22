// lib/widgets/modern_emoji_picker.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qorange/theme.dart';

/// 表情数据模型
class EmojiItem {
  final String emoji;
  final String name;
  final String slug;

  EmojiItem({required this.emoji, required this.name, required this.slug});

  factory EmojiItem.fromJson(Map<String, dynamic> json) {
    return EmojiItem(
      emoji: json['emoji']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      slug: json['slug']?.toString() ?? '',
    );
  }
}

class EmojiCategory {
  final String name;
  final String slug;
  final List<EmojiItem> emojis;

  EmojiCategory({required this.name, required this.slug, required this.emojis});

  factory EmojiCategory.fromJson(Map<String, dynamic> json) {
    final list = json['emojis'] as List? ?? [];
    final List<EmojiItem> emojiList =
    list.map((e) => EmojiItem.fromJson(e as Map<String, dynamic>)).toList();
    return EmojiCategory(
      name: json['name']?.toString() ?? '',
      slug: json['slug']?.toString() ?? '',
      emojis: emojiList,
    );
  }
}

/// 高颜值交互表情选择器（支持搜索时自适应横向两排流式候选与全屏浏览）
class ModernEmojiPicker extends StatefulWidget {
  final Function(String emoji) onEmojiSelected;
  final VoidCallback? onBackspacePressed;

  const ModernEmojiPicker({
    super.key,
    required this.onEmojiSelected,
    this.onBackspacePressed,
  });

  @override
  State<ModernEmojiPicker> createState() => _ModernEmojiPickerState();
}

class _ModernEmojiPickerState extends State<ModernEmojiPicker>
    with SingleTickerProviderStateMixin {
  List<EmojiCategory> _categories = [];
  Map<String, dynamic> _keywordsMap = {};
  List<String> _recentEmojis = [];
  bool _isLoading = true;

  late PageController _pageController;
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<EmojiItem> _searchResults = [];
  bool _isSearching = false;

  Color get _primaryColor => AppColors.primary;
  Color get _backgroundColor => AppColors.background;
  Color get _slateGrey => AppColors.textPrimary;
  Color get _lightSlateGrey => AppColors.textHint;

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

  Future<void> _loadData() async {
    try {
      final String categoriesStr =
      await rootBundle.loadString('assets/emojis-by-group.json');
      final List<dynamic> categoriesJson = jsonDecode(categoriesStr);
      final List<EmojiCategory> loadedCategories = categoriesJson
          .map((e) => EmojiCategory.fromJson(e as Map<String, dynamic>))
          .toList();

      final String keywordsStr =
      await rootBundle.loadString('assets/emoji-keywords.json');
      _keywordsMap = jsonDecode(keywordsStr) as Map<String, dynamic>;

      final prefs = await SharedPreferences.getInstance();
      _recentEmojis = prefs.getStringList('recent_emojis') ?? [];

      if (mounted) {
        setState(() {
          _categories = loadedCategories;
          _tabController =
              TabController(length: _categories.length + 1, vsync: this);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('加载表情数据失败: $e');
    }
  }

  Future<void> _saveRecentEmoji(String emoji) async {
    if (_recentEmojis.contains(emoji)) {
      _recentEmojis.remove(emoji);
    }
    _recentEmojis.insert(0, emoji);
    if (_recentEmojis.length > 28) {
      _recentEmojis = _recentEmojis.sublist(0, 28);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('recent_emojis', _recentEmojis);
    if (mounted) {
      setState(() {});
    }
  }

  void _onSearchChanged(String query) {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) {
      if (mounted) {
        setState(() {
          _isSearching = false;
          _searchResults = [];
        });
      }
      return;
    }

    final List<EmojiItem> results = [];

    for (final category in _categories) {
      for (final emojiItem in category.emojis) {
        final nameLower = emojiItem.name.toLowerCase();
        final slugLower = emojiItem.slug.toLowerCase();
        bool matches =
            nameLower.contains(cleanQuery) || slugLower.contains(cleanQuery);

        if (!matches && _keywordsMap.containsKey(emojiItem.emoji)) {
          final dynamic kw = _keywordsMap[emojiItem.emoji];
          if (kw is List) {
            matches = kw.any((k) =>
                k.toString().toLowerCase().contains(cleanQuery));
          } else if (kw is String) {
            matches = kw.toLowerCase().contains(cleanQuery);
          }
        }

        if (matches && !results.any((e) => e.emoji == emojiItem.emoji)) {
          results.add(emojiItem);
        }
      }
    }

    if (mounted) {
      setState(() {
        _isSearching = true;
        _searchResults = results;
      });
    }
  }

  /// 🌟 搜索状态下：横向单行平滑滚动的表情候选栏
  Widget _buildHorizontalSearchResults() {
    if (_searchResults.isEmpty) {
      return Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Icon(Icons.sentiment_dissatisfied_rounded,
                size: 18, color: _lightSlateGrey),
            const SizedBox(width: 8),
            Text(
              'no_emoji_found'.tr,
              style: TextStyle(color: _lightSlateGrey, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Container(
      height: 54,
      color: _backgroundColor,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: _searchResults.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final item = _searchResults[index];
          return Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.divider),
            ),
            child: _EmojiButton(
              emojiItem: item,
              onTap: (emoji) {
                HapticFeedback.selectionClick();
                widget.onEmojiSelected(emoji);
                _saveRecentEmoji(emoji);
              },
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        color: _backgroundColor,
        child: Center(
          child: CircularProgressIndicator(
            color: _primaryColor,
            strokeWidth: 2.5,
          ),
        ),
      );
    }

    final double keyboardInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(color: AppColors.surface,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 第一排：搜索框与退格键组合条
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _searchFocusNode.hasFocus
                            ? _primaryColor.withOpacity(0.5)
                            : AppColors.divider,
                        width: 1.0,
                      ),
                    ),
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      textAlignVertical: TextAlignVertical.center,
                      onChanged: _onSearchChanged,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: _slateGrey,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'search_emoji_hint'.tr,
                        hintStyle: TextStyle(
                          color: _lightSlateGrey.withOpacity(0.8),
                          fontSize: 12,
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: _searchFocusNode.hasFocus
                              ? _primaryColor
                              : _lightSlateGrey,
                          size: 18,
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            _searchController.clear();
                            _onSearchChanged('');
                          },
                          child: Icon(
                            Icons.cancel_rounded,
                            color: _lightSlateGrey,
                            size: 16,
                          ),
                        )
                            : null,
                        suffixIconConstraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ),
                if (widget.onBackspacePressed != null) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      widget.onBackspacePressed!();
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 42,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Icon(
                        Icons.backspace_outlined,
                        color: _slateGrey,
                        size: 17,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.surfaceAlt),

          // 🌟 核心切换：搜索状态下仅展示两排（横向候选条）；非搜索状态展示完整多分类网格
          if (_isSearching)
            _buildHorizontalSearchResults()
          else ...[
            Expanded(
              child: Container(
                color: _backgroundColor,
                child: _buildPageView(),
              ),
            ),
            Divider(height: 1, color: AppColors.surfaceAlt),
            Container(color: AppColors.surface,
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                physics: const BouncingScrollPhysics(),
                tabAlignment: TabAlignment.start,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: _primaryColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                labelColor: _primaryColor,
                unselectedLabelColor: _lightSlateGrey,
                dividerColor: Colors.transparent,
                labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                onTap: (index) {
                  _pageController.animateToPage(
                    index,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOutCubic,
                  );
                },
                tabs: [
                  const Tab(
                    height: 32,
                    child: Icon(Icons.history_rounded, size: 18),
                  ),
                  ..._categories.map((cat) => Tab(
                    height: 32,
                    child: Text(
                      _getCategoryEmoji(cat.slug),
                      style: const TextStyle(
                        fontSize: 16,
                        fontFamily: 'Apple Color Emoji',
                      ),
                    ),
                  )),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPageView() {
    return PageView.builder(
      controller: _pageController,
      onPageChanged: (index) {
        _tabController.animateTo(index);
      },
      itemCount: _categories.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          if (_recentEmojis.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_rounded, size: 36, color: _lightSlateGrey),
                  const SizedBox(height: 6),
                  Text(
                    'no_recent_emoji'.tr,
                    style: TextStyle(
                      color: _lightSlateGrey,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            );
          }
          return _buildGrid(
            _recentEmojis
                .map((e) => EmojiItem(emoji: e, name: '', slug: ''))
                .toList(),
          );
        } else {
          final category = _categories[index - 1];
          return _buildGrid(category.emojis);
        }
      },
    );
  }

  Widget _buildGrid(List<EmojiItem> emojis) {
    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 1.0,
      ),
      itemCount: emojis.length,
      itemBuilder: (context, index) {
        return _EmojiButton(
          emojiItem: emojis[index],
          onTap: (emoji) {
            HapticFeedback.selectionClick();
            widget.onEmojiSelected(emoji);
            _saveRecentEmoji(emoji);
          },
        );
      },
    );
  }

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

class _EmojiButton extends StatefulWidget {
  final EmojiItem emojiItem;
  final Function(String emoji) onTap;

  const _EmojiButton({required this.emojiItem, required this.onTap});

  @override
  State<_EmojiButton> createState() => _EmojiButtonState();
}

class _EmojiButtonState extends State<_EmojiButton>
    with SingleTickerProviderStateMixin {
  double _scale = 1.0;
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 70),
      lowerBound: 0.0,
      upperBound: 0.18,
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
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            widget.emojiItem.emoji,
            style: const TextStyle(
              fontSize: 26,
              fontFamily: 'Apple Color Emoji',
            ),
          ),
        ),
      ),
    );
  }
}