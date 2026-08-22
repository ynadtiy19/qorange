// lib/views/search/search_view.dart
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qorange/theme.dart';

import '../../network/api_exception.dart';
import '../../network/http_client.dart';
import '../../user_controller.dart';
import '../post_detail/post_detail_view.dart';
import '../profile/profile_view.dart';

class SearchView extends StatefulWidget {
  const SearchView({super.key});

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  late TabController _tabController;

  // 帖子搜索状态与分页
  final List<dynamic> _postResults = [];
  int _postPage = 1;
  final int _postPageSize = 15;
  bool _hasMorePosts = true;
  bool _isLoadingPosts = false;
  bool _isLoadingMorePosts = false;

  // 用户搜索状态与分页
  final List<dynamic> _userResults = [];
  int _userPage = 1;
  final int _userPageSize = 15;
  bool _hasMoreUsers = true;
  bool _isLoadingUsers = false;
  bool _isLoadingMoreUsers = false;

  List<String> _searchHistory = [];
  final List<String> _trendingTags = [];

  List<String> get _defaultSearchHistory => [
    'default_search_1'.tr,
    'default_search_2'.tr,
    'default_search_3'.tr,
    'default_search_4'.tr,
    'default_search_5'.tr,
  ];

  bool _hasSearched = false;
  String _currentKeyword = '';

  Color get _primaryColor => AppColors.primary;

  @override
  void initState() {
    super.initState();

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

    _tabController = TabController(length: 2, vsync: this);

    _focusNode.addListener(() {
      setState(() {});
    });

    _loadSearchTrends();

    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });

    _animationController.forward();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _animationController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSearchTrends() async {
    final bool isLoggedIn = UserController.to.isLoggedIn;

    if (isLoggedIn) {
      try {
        final res = await HttpClient.instance.get<Map<String, dynamic>>(
          '/api-posts/search-trends',
        );
        if (res.datas != null) {
          final List<dynamic> history =
              res.datas!['search_history'] as List? ?? [];
          final List<dynamic> trends =
              res.datas!['trending_tags'] as List? ?? [];
          setState(() {
            _searchHistory = history.cast<String>();
            _trendingTags.clear();
            _trendingTags.addAll(trends.cast<String>());
          });
          return;
        }
      } catch (_) {}
    }

    await _loadLocalHistory();
  }

  Future<void> _loadLocalHistory() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String>? localHistory =
      prefs.getStringList('guest_search_history');
      setState(() {
        _searchHistory = localHistory ?? _defaultSearchHistory;
      });
    } catch (_) {
      setState(() {
        _searchHistory = _defaultSearchHistory;
      });
    }
  }

  Future<void> _saveLocalHistory(String keyword) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _searchHistory.remove(keyword);
      _searchHistory.insert(0, keyword);
      if (_searchHistory.length > 8) {
        _searchHistory.removeLast();
      }
      await prefs.setStringList('guest_search_history', _searchHistory);
      setState(() {});
    } catch (_) {}
  }

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
      try {
        await HttpClient.instance.delete('/api-posts/search-trends');
      } catch (_) {}
    }
  }

  // 🌟 统一触发搜索：并发开启帖子与用户的第 1 页拉取
  Future<void> _performSearch(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return;

    _searchController.text = trimmed;
    _currentKeyword = trimmed;
    _focusNode.unfocus();

    setState(() {
      _hasSearched = true;
      _postPage = 1;
      _userPage = 1;
      _hasMorePosts = true;
      _hasMoreUsers = true;
      _postResults.clear();
      _userResults.clear();
      _isLoadingPosts = true;
      _isLoadingUsers = true;
    });

    final bool isLoggedIn = UserController.to.isLoggedIn;
    if (isLoggedIn) {
      if (!_searchHistory.contains(trimmed)) {
        setState(() {
          _searchHistory.insert(0, trimmed);
          if (_searchHistory.length > 8) {
            _searchHistory.removeLast();
          }
        });
      }
    } else {
      await _saveLocalHistory(trimmed);
    }

    await Future.wait([
      _fetchPosts(isRefresh: true),
      _fetchUsers(isRefresh: true),
    ]);
  }

  // 🌟 帖子分页加载
  Future<void> _fetchPosts({bool isRefresh = false}) async {
    if (_currentKeyword.isEmpty) return;
    if (!isRefresh && (!_hasMorePosts || _isLoadingMorePosts)) return;

    if (isRefresh) {
      _postPage = 1;
      _hasMorePosts = true;
      setState(() => _isLoadingPosts = true);
    } else {
      setState(() => _isLoadingMorePosts = true);
    }

    try {
      final res = await HttpClient.instance.get<Map<String, dynamic>>(
        '/api-posts',
        queryParameters: {
          'keyword': _currentKeyword,
          'page': _postPage,
          'pageSize': _postPageSize,
        },
      );

      if (res.datas != null) {
        final List<dynamic> posts = res.datas!['posts'] as List? ?? [];
        setState(() {
          if (isRefresh) {
            _postResults.assignAll(posts);
          } else {
            _postResults.addAll(posts);
          }
          _hasMorePosts = posts.length >= _postPageSize;
          if (_hasMorePosts) _postPage++;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingPosts = false;
          _isLoadingMorePosts = false;
        });
      }
    }
  }

  // 🌟 用户分页加载
  Future<void> _fetchUsers({bool isRefresh = false}) async {
    if (_currentKeyword.isEmpty) return;
    if (!isRefresh && (!_hasMoreUsers || _isLoadingMoreUsers)) return;

    if (isRefresh) {
      _userPage = 1;
      _hasMoreUsers = true;
      setState(() => _isLoadingUsers = true);
    } else {
      setState(() => _isLoadingMoreUsers = true);
    }

    try {
      final res = await HttpClient.instance.get<Map<String, dynamic>>(
        '/api-users/search',
        queryParameters: {
          'keyword': _currentKeyword,
          'page': _userPage,
          'limit': _userPageSize,
        },
      );

      if (res.datas != null) {
        final List<dynamic> users = res.datas!['users'] as List? ?? [];
        final bool hasMoreFromServer =
            res.datas!['has_more'] as bool? ?? (users.length >= _userPageSize);

        setState(() {
          if (isRefresh) {
            _userResults.assignAll(users);
          } else {
            _userResults.addAll(users);
          }
          _hasMoreUsers = hasMoreFromServer;
          if (_hasMoreUsers) _userPage++;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingUsers = false;
          _isLoadingMoreUsers = false;
        });
      }
    }
  }

  // 🌟 关注/取关实时交互处理
  Future<void> _toggleFollowUser(Map<String, dynamic> user, int index) async {
    if (!UserController.to.isLoggedIn) {
      Fluttertoast.showToast(msg: 'search_login_to_follow'.tr);
      return;
    }

    final String targetUserId = user['id']?.toString() ?? '';
    if (targetUserId.isEmpty) return;

    final bool currentFollowStatus = user['is_following'] == true;

    // 先做本地乐观更新
    setState(() {
      user['is_following'] = !currentFollowStatus;
      final int followers = user['followers_count'] as int? ?? 0;
      user['followers_count'] =
      currentFollowStatus ? (followers - 1).clamp(0, 999999) : followers + 1;
    });

    try {
      final res = await HttpClient.instance.post<Map<String, dynamic>>(
        '/api-users/follow',
        data: {'target_user_id': targetUserId},
      );
      if (res.respCode != 0) {
        // 接口失败回滚
        setState(() {
          user['is_following'] = currentFollowStatus;
        });
      }
    } catch (e) {
      setState(() {
        user['is_following'] = currentFollowStatus;
      });
      if (e is ApiException) {
        Fluttertoast.showToast(msg: e.message);
      }
    }
  }

  void _clearSearch() {
    _searchController.clear();
    _currentKeyword = '';
    setState(() {
      _postResults.clear();
      _userResults.clear();
      _hasSearched = false;
    });
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(left: 8.0, right: 16.0),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Get.back(),
                icon: HugeIcon(
                  icon: HugeIcons.strokeRoundedArrowLeft01,
                  color: AppColors.textPrimary,
                ),
              ),
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 46,
                  decoration: BoxDecoration(
                    color: _focusNode.hasFocus
                        ? Colors.white
                        : AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(23),
                    border: Border.all(
                      color: _focusNode.hasFocus
                          ? _primaryColor
                          : AppColors.divider,
                      width: _focusNode.hasFocus ? 1.5 : 1.0,
                    ),
                    boxShadow: [
                      if (_focusNode.hasFocus)
                        BoxShadow(
                          color: _primaryColor.withOpacity(0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        )
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(width: 14),
                      HugeIcon(
                        icon: HugeIcons.strokeRoundedSearch01,
                        color: _focusNode.hasFocus
                            ? _primaryColor
                            : AppColors.textHint,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          focusNode: _focusNode,
                          onSubmitted: _performSearch,
                          textInputAction: TextInputAction.search,
                          textAlign: TextAlign.start,
                          style: TextStyle(
                              fontSize: 14, color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            hintText: 'search_hint'.tr,
                            hintStyle: TextStyle(
                                fontSize: 13, color: AppColors.textHint),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
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
                                  return ScaleTransition(
                                      scale: animation, child: child);
                                },
                                child: hasText
                                    ? GestureDetector(
                                  key: const ValueKey('clearButton'),
                                  onTap: _clearSearch,
                                  behavior: HitTestBehavior.opaque,
                                  child: Container(
                                    padding: const EdgeInsets.all(5),
                                    decoration: BoxDecoration(
                                      color: AppColors.divider,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.close_rounded,
                                      size: 13,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                )
                                    : const SizedBox.shrink(
                                    key: ValueKey('emptyPlaceholder')),
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
        bottom: _hasSearched
            ? PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Container(color: AppColors.surface,
            alignment: Alignment.centerLeft,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: _primaryColor,
              indicatorWeight: 3,
              indicatorSize: TabBarIndicatorSize.label,
              labelColor: _primaryColor,
              unselectedLabelColor: AppColors.textHint,
              labelStyle: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13),
              unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13),
              tabs: [
                Tab(text: 'tab_posts'.tr),
                Tab(text: 'tab_users'.tr),
              ],
            ),
          ),
        )
            : null,
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _hasSearched ? _buildSearchResultsBody() : _buildHistoryAndTrendsBody(),
      ),
    );
  }

  // 🌟 搜索结果展示区（支持帖子与用户各自的分页滚动监听）
  Widget _buildSearchResultsBody() {
    return TabBarView(
      controller: _tabController,
      children: [
        // Tab 1: 帖子搜索结果流
        _buildPostsSearchResultTab(),
        // Tab 2: 用户搜索结果流
        _buildUsersSearchResultTab(),
      ],
    );
  }

  Widget _buildPostsSearchResultTab() {
    if (_isLoadingPosts) {
      return Center(
        child: CircularProgressIndicator(color: _primaryColor, strokeWidth: 2.5),
      );
    }

    if (_postResults.isEmpty) {
      return _buildEmptyStateView('search_no_articles'.tr);
    }

    return RefreshIndicator(
      color: _primaryColor,
      onRefresh: () => _fetchPosts(isRefresh: true),
      child: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification scrollInfo) {
          if (scrollInfo.metrics.pixels >=
              scrollInfo.metrics.maxScrollExtent - 200) {
            _fetchPosts(isRefresh: false);
          }
          return false;
        },
        child: ListView.separated(
          padding: const EdgeInsets.only(top: 8, bottom: 20),
          itemCount: _postResults.length + 1,
          separatorBuilder: (context, index) => const SizedBox(height: 4),
          itemBuilder: (context, index) {
            if (index == _postResults.length) {
              return _buildPaginationLoader(_isLoadingMorePosts, _hasMorePosts);
            }
            final post = _postResults[index];
            return _buildAestheticPostItem(post);
          },
        ),
      ),
    );
  }

  Widget _buildUsersSearchResultTab() {
    if (_isLoadingUsers) {
      return Center(
        child: CircularProgressIndicator(color: _primaryColor, strokeWidth: 2.5),
      );
    }

    if (_userResults.isEmpty) {
      return _buildEmptyStateView('search_no_users'.tr);
    }

    return RefreshIndicator(
      color: _primaryColor,
      onRefresh: () => _fetchUsers(isRefresh: true),
      child: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification scrollInfo) {
          if (scrollInfo.metrics.pixels >=
              scrollInfo.metrics.maxScrollExtent - 200) {
            _fetchUsers(isRefresh: false);
          }
          return false;
        },
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: _userResults.length + 1,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            if (index == _userResults.length) {
              return _buildPaginationLoader(_isLoadingMoreUsers, _hasMoreUsers);
            }
            final user = _userResults[index];
            return _buildUserSearchCard(user, index);
          },
        ),
      ),
    );
  }

  Widget _buildPaginationLoader(bool isLoadingMore, bool hasMore) {
    if (isLoadingMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(color: _primaryColor, strokeWidth: 2),
          ),
        ),
      );
    }
    if (!hasMore) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            'search_loaded_all'.tr,
            style: TextStyle(fontSize: 11, color: AppColors.textHint),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildEmptyStateView(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 64, color: AppColors.divider),
          const SizedBox(height: 14),
          Text(
            message,
            style: TextStyle(color: AppColors.textHint, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // 🌟 高质感用户卡片（包含头像、个性账号、Bio与实时关注操作按钮）
  Widget _buildUserSearchCard(Map<String, dynamic> user, int index) {
    final String userId = user['id']?.toString() ?? '';
    final String nickname = user['nickname']?.toString() ?? 'user'.tr;
    final String username = user['username']?.toString() ?? '';
    final String avatar = user['avatar']?.toString() ?? '';
    final String bio = user['bio']?.toString().trim() ?? '';
    final bool isFollowing = user['is_following'] == true;
    final bool isMe = user['is_me'] == true;
    final int followersCount = user['followers_count'] as int? ?? 0;
    final List<dynamic> topics = user['topics'] as List? ?? [];

    return Container(
      decoration: BoxDecoration(color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.015),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            if (userId.isNotEmpty) {
              Get.to(() => ProfileView(profileId: userId));
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.network(
                    avatar.isNotEmpty
                        ? avatar
                        : 'https://api.dicebear.com/7.x/micah/png?seed=${userId.hashCode}',
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 48,
                      height: 48,
                      color: AppColors.divider,
                      child: HugeIcon(
                        icon: HugeIcons.strokeRoundedUser,
                        size: 24,
                        color: AppColors.textHint,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              nickname,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (username.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            Text(
                              '@$username',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textHint,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (bio.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          bio,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            height: 1.35,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            'search_followers_count'.trParams({'count': followersCount.toString()}),
                            style: TextStyle(
                              fontSize: 10.5,
                              color: AppColors.textHint,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (topics.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: _primaryColor.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                topics.first.toString().toUpperCase(),
                                style: TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w800,
                                  color: _primaryColor,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (!isMe) ...[
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: () => _toggleFollowUser(user, index),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isFollowing
                          ? AppColors.surfaceAlt
                          : _primaryColor,
                      foregroundColor: isFollowing
                          ? AppColors.textSecondary
                          : Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      minimumSize: const Size(60, 32),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      isFollowing ? 'following_state'.tr : 'follow'.tr,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                      ),
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

  // 历史记录与热门推荐视图
  Widget _buildHistoryAndTrendsBody() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_searchHistory.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'recent_searches'.tr,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    GestureDetector(
                      onTap: _clearHistory,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: Text(
                          'clear_all'.tr,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textHint,
                            fontWeight: FontWeight.w600,
                          ),
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceAlt,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: AppColors.divider, width: 0.8),
                          ),
                          child: Text(
                            history,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 32),
              ],
              Text(
                'trending_categories'.tr,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
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
                      style: TextStyle(
                        fontSize: 11,
                        color: _primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    backgroundColor: _primaryColor.withOpacity(0.06),
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    pressElevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAestheticPostItem(dynamic post) {
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
      decoration: BoxDecoration(color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider, width: 0.8),
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
                        backgroundImage: authorAvatar.isNotEmpty
                            ? NetworkImage(authorAvatar)
                            : null,
                        backgroundColor: AppColors.divider,
                        child: authorAvatar.isEmpty
                            ? const Icon(Icons.person,
                            size: 12, color: Colors.grey)
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        authorNickname,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _primaryColor.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          category.toUpperCase(),
                          style: TextStyle(
                            fontSize: 9,
                            color: _primaryColor,
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
                                  color: AppColors.textSecondary,
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
                        style: TextStyle(
                            fontSize: 10, color: AppColors.textHint),
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
                        style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textHint,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 14),
                      HugeIcon(
                        icon: HugeIcons.strokeRoundedFavourite,
                        color:
                        isLiked ? Colors.redAccent : AppColors.textHint,
                        size: 13,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$likesCount',
                        style: TextStyle(
                          fontSize: 10,
                          color: isLiked
                              ? Colors.redAccent
                              : AppColors.textHint,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 14),
                      HugeIcon(
                        icon: HugeIcons.strokeRoundedBookmark01,
                        color: isCollected
                            ? Colors.orangeAccent
                            : AppColors.textHint,
                        size: 13,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$collectsCount',
                        style: TextStyle(
                          fontSize: 10,
                          color: isCollected
                              ? Colors.orangeAccent
                              : AppColors.textHint,
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
                        style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textHint,
                            fontWeight: FontWeight.bold),
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