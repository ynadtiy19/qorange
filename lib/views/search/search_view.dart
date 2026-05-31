// lib/views/search/search_view.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../network/http_client.dart';
import '../post_detail/post_detail_view.dart';

class SearchView extends StatefulWidget {
  const SearchView({super.key});

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  List<dynamic> _searchResults = [];
  List<String> _searchHistory = ["学术", "说说", "投票", "设计", "青橙"];
  final List<String> _trendingTags = ["news", "general", "aviation", "technology", "business"];

  bool _isSearching = false;
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
    // 自动聚焦搜索框以提供更舒适的入场微动作
    Future.delayed(const Duration(milliseconds: 200), () {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // 🌟 执行搜索并与后端对齐强检索约束逻辑
  Future<void> _performSearch(String keyword) async {
    if (keyword.trim().isEmpty) return;

    _searchController.text = keyword;
    _focusNode.unfocus();

    setState(() {
      _isSearching = true;
      _hasSearched = true;
    });

    // 记录到历史搜索记录
    if (!_searchHistory.contains(keyword)) {
      setState(() {
        _searchHistory.insert(0, keyword);
        if (_searchHistory.length > 8) {
          _searchHistory.removeLast();
        }
      });
    }

    try {
      final res = await HttpClient.instance.get<Map<String, dynamic>>(
        '/api-posts',
        queryParameters: {
          'keyword': keyword,
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
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey.shade100, width: 0.8),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      Icon(Icons.search, size: 18, color: Colors.grey.shade400),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          focusNode: _focusNode,
                          onSubmitted: _performSearch,
                          textInputAction: TextInputAction.search,
                          style: const TextStyle(fontSize: 14, color: Colors.black87),
                          decoration: InputDecoration(
                            hintText: "搜索你感兴趣的内容...",
                            hintStyle: TextStyle(fontSize: 14, color: Colors.grey.shade400),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                      if (_searchController.text.isNotEmpty)
                        GestureDetector(
                          onTap: _clearSearch,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Icon(Icons.cancel, size: 16, color: Colors.grey.shade400),
                          ),
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
              Icon(Icons.search_off_outlined, size: 56, color: Colors.grey.shade200),
              const SizedBox(height: 12),
              Text(
                "没有搜到匹配的结果，换个词试试吧",
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

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 搜索历史
          if (_searchHistory.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "搜索历史",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _searchHistory.clear();
                    });
                  },
                  child: Text(
                    "清除历史",
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _searchHistory.map((history) {
                return GestureDetector(
                  onTap: () => _performSearch(history),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.grey.shade100, width: 0.8),
                    ),
                    child: Text(
                      history,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 28),
          ],

          // 热门探索
          const Text(
            "热门推荐分类",
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _trendingTags.map((tag) {
              return ActionChip(
                onPressed: () => _performSearch(tag),
                label: Text(
                  tag.toUpperCase(),
                  style: TextStyle(fontSize: 11, color: themeColor, fontWeight: FontWeight.bold),
                ),
                backgroundColor: themeColor.withOpacity(0.06),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // 🌟 与主页视觉高度统一的学术卡片组件
  Widget _buildAestheticPostItem(dynamic post) {
    final themeColor = const Color.fromRGBO(44, 123, 109, 1.0);
    if (post == null || post['id'] == null) return const SizedBox.shrink();

    final author = post['author'] ?? {};
    final authorAvatar = author['avatar'] ?? '';
    final authorNickname = author['nickname'] ?? '用户';

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