// lib/views/home/home_view.dart (全能 50 字快照与多维高阶卡片流集成版)
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:qorange/theme.dart';
import '../../network/http_client.dart';
import '../../user_controller.dart';
import '../post_detail/post_detail_view.dart';
import '../publish/publish_view.dart';
import '../search/search_view.dart';
import '../voice/voice_chat_view.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  final ScrollController _forYouScrollController = ScrollController();
  final ScrollController _featuredScrollController = ScrollController();

  List<dynamic> _forYouPosts = [];
  List<dynamic> _featuredPosts = [];
  List<dynamic> _recommendedTags = [];

  bool _isLoadingForYou = true;
  bool _isLoadingFeatured = true;

  int _forYouPage = 1;
  int _featuredPage = 1;
  final int _pageSize = 10;

  bool _hasMoreForYou = true;
  bool _hasMoreFeatured = true;

  bool _isLoadingMoreForYou = false;
  bool _isLoadingMoreFeatured = false;

  String? _selectedTag;
  String? _selectedCategory;

  Worker? _userStateWorker;
  Worker? _globalSyncWorker;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    _forYouScrollController.addListener(_onForYouScroll);
    _featuredScrollController.addListener(_onFeaturedScroll);

    // 🌟 1. 监听用户状态变动
    _userStateWorker = ever(UserController.to.user, (_) {
      if (mounted) {
        _clearActiveFilters();
      }
    });

    // 🌟 2. 监听全局数据一致性同步信号（跨页购买、点赞后首页 Tab 0 即时静默刷新）
    _globalSyncWorker = ever(globalDataSyncSignal, (_) {
      if (mounted) {
        _fetchForYou(isRefresh: true);
        _fetchFeatured(isRefresh: true);
      }
    });

    _loadFeeds();
  }

  @override
  void dispose() {
    _userStateWorker?.dispose();
    _globalSyncWorker?.dispose();
    _tabController.dispose();
    _searchController.dispose();
    _forYouScrollController.dispose();
    _featuredScrollController.dispose();
    super.dispose();
  }

  void _onForYouScroll() {
    if (_forYouScrollController.position.pixels >=
        _forYouScrollController.position.maxScrollExtent - 200) {
      _fetchMoreForYou();
    }
  }

  void _onFeaturedScroll() {
    if (_featuredScrollController.position.pixels >=
        _featuredScrollController.position.maxScrollExtent - 200) {
      _fetchMoreFeatured();
    }
  }

  Future<void> _loadFeeds() async {
    if (!mounted) return;
    setState(() {
      _isLoadingForYou = true;
      _isLoadingFeatured = true;
    });
    await Future.wait([
      _fetchForYou(isRefresh: true),
      _fetchFeatured(isRefresh: true),
    ]);
  }

  Future<void> _fetchForYou({bool isRefresh = false}) async {
    if (isRefresh) {
      _forYouPage = 1;
      _hasMoreForYou = true;
    }
    try {
      final Map<String, dynamic> queryParams = {
        'feed_type': 'for_you',
        'page': _forYouPage,
        'pageSize': _pageSize,
      };

      if (_selectedTag != null && _selectedTag!.isNotEmpty) {
        queryParams['tag'] = _selectedTag;
      }
      if (_selectedCategory != null && _selectedCategory!.isNotEmpty) {
        queryParams['category'] = _selectedCategory;
      }

      final res = await HttpClient.instance.get<Map<String, dynamic>>(
        '/api-posts',
        queryParameters: queryParams,
      );
      if (res.datas != null) {
        final List<dynamic> newPosts = res.datas!['posts'] as List? ?? [];
        final List<dynamic> tags = res.datas!['recommended_tags'] as List? ?? [];

        if (!mounted) return;
        setState(() {
          if (isRefresh) {
            _forYouPosts = newPosts;
          } else {
            _forYouPosts.addAll(newPosts);
          }
          _recommendedTags = tags;
          _isLoadingForYou = false;
          _isLoadingMoreForYou = false;
          if (newPosts.length < _pageSize) {
            _hasMoreForYou = false;
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingForYou = false;
        _isLoadingMoreForYou = false;
      });
    }
  }

  Future<void> _fetchMoreForYou() async {
    if (_isLoadingMoreForYou || !_hasMoreForYou || _isLoadingForYou) return;
    if (!mounted) return;
    setState(() {
      _isLoadingMoreForYou = true;
    });
    _forYouPage++;
    await _fetchForYou(isRefresh: false);
  }

  Future<void> _fetchFeatured({bool isRefresh = false}) async {
    if (isRefresh) {
      _featuredPage = 1;
      _hasMoreFeatured = true;
    }
    try {
      final Map<String, dynamic> queryParams = {
        'feed_type': 'featured',
        'page': _featuredPage,
        'pageSize': _pageSize,
      };

      if (_selectedTag != null && _selectedTag!.isNotEmpty) {
        queryParams['tag'] = _selectedTag;
      }
      if (_selectedCategory != null && _selectedCategory!.isNotEmpty) {
        queryParams['category'] = _selectedCategory;
      }

      final res = await HttpClient.instance.get<Map<String, dynamic>>(
        '/api-posts',
        queryParameters: queryParams,
      );
      if (res.datas != null) {
        final List<dynamic> newPosts = res.datas!['posts'] as List? ?? [];

        if (!mounted) return;
        setState(() {
          if (isRefresh) {
            _featuredPosts = newPosts;
          } else {
            _featuredPosts.addAll(newPosts);
          }
          _isLoadingFeatured = false;
          _isLoadingMoreFeatured = false;
          if (newPosts.length < _pageSize) {
            _hasMoreFeatured = false;
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingFeatured = false;
        _isLoadingMoreFeatured = false;
      });
    }
  }

  Future<void> _fetchMoreFeatured() async {
    if (_isLoadingMoreFeatured || !_hasMoreFeatured || _isLoadingFeatured) return;
    if (!mounted) return;
    setState(() {
      _isLoadingMoreFeatured = true;
    });
    _featuredPage++;
    await _fetchFeatured(isRefresh: false);
  }

  void _clearActiveFilters() {
    if (!mounted) return;
    setState(() {
      _selectedTag = null;
      _selectedCategory = null;
      _isLoadingForYou = true;
      _isLoadingFeatured = true;
    });
    _loadFeeds();
  }

  void _onTagSelected(String tag) {
    if (!mounted) return;
    setState(() {
      _selectedTag = tag;
      _selectedCategory = null;
      _isLoadingForYou = true;
      _isLoadingFeatured = true;
    });
    _loadFeeds();
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = AppColors.primary;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        centerTitle: false,
        title: Text(
          'app_name'.tr,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: AppColors.primary,
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () => Get.to(() => const SearchView()),
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedSearch01,
              color: AppColors.primary,
            ),
          ),
          Obx(() {
            if (!UserController.to.isLoggedIn) {
              return const SizedBox.shrink();
            }

            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: () => Get.to(
                        () => const VoiceChatView(),
                    transition: Transition.cupertino,
                    duration: const Duration(milliseconds: 300),
                  ),
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedAiGame,
                    color: AppColors.primary,
                  ),
                ),
                IconButton(
                  onPressed: () => Get.to(() => const PublishView())?.then((_) {
                    triggerGlobalDataSync();
                  }),
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedQuillWrite02,
                    color: AppColors.primary,
                  ),
                ),
              ],
            );
          }),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: Colors.black,
              unselectedLabelColor: AppColors.textHint,
              indicatorColor: themeColor,
              indicatorWeight: 3,
              indicatorSize: TabBarIndicatorSize.label,
              labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              tabs: [
                Tab(text: 'for_you'.tr),
                Tab(text: 'featured'.tr),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          AnimatedCrossFade(
            firstChild: _buildActiveFilterBanner(),
            secondChild: const SizedBox.shrink(),
            crossFadeState: (_selectedTag != null || _selectedCategory != null)
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            duration: const Duration(milliseconds: 300),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildPostList(
                  posts: _forYouPosts,
                  isLoading: _isLoadingForYou,
                  isForYou: true,
                  scrollController: _forYouScrollController,
                  hasMore: _hasMoreForYou,
                  isLoadingMore: _isLoadingMoreForYou,
                ),
                _buildPostList(
                  posts: _featuredPosts,
                  isLoading: _isLoadingFeatured,
                  isForYou: false,
                  scrollController: _featuredScrollController,
                  hasMore: _hasMoreFeatured,
                  isLoadingMore: _isLoadingMoreFeatured,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveFilterBanner() {
    final themeColor = AppColors.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: themeColor.withOpacity(0.06),
      child: Row(
        children: [
          Icon(Icons.filter_alt_outlined, size: 16, color: themeColor),
          const SizedBox(width: 8),
          Text(
            _selectedTag != null ? '${'current_filter_tag'.tr}$_selectedTag' : '${'current_filter_category'.tr}$_selectedCategory',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: themeColor),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _clearActiveFilters,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: themeColor.withOpacity(0.3), width: 0.8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('clear'.tr, style: TextStyle(fontSize: 10, color: themeColor, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 2),
                  Icon(Icons.close, size: 10, color: themeColor),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostList({
    required List<dynamic> posts,
    required bool isLoading,
    required bool isForYou,
    required ScrollController scrollController,
    required bool hasMore,
    required bool isLoadingMore,
  }) {
    if (isLoading) {
      return Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
          strokeWidth: 2,
        ),
      );
    }
    if (posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.article_outlined, size: 48, color: AppColors.border),
            const SizedBox(height: 12),
            Text('no_content_try_tag'.tr, style: TextStyle(color: AppColors.textHint)),
          ],
        ),
      );
    }

    final hasTags = isForYou && _recommendedTags.isNotEmpty;
    final extraItemCount = (hasTags ? 1 : 0) + 1;

    return RefreshIndicator(
      onRefresh: _loadFeeds,
      color: AppColors.primary,
      child: ListView.separated(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: posts.length + extraItemCount,
        separatorBuilder: (context, index) {
          if (hasTags && index == 0) return const SizedBox.shrink();
          if (index >= posts.length + (hasTags ? 1 : 0)) return const SizedBox.shrink();
          return const SizedBox(height: 4);
        },
        itemBuilder: (context, index) {
          if (hasTags && index == 0) {
            return _buildTagsSection();
          }

          final postIndex = hasTags ? index - 1 : index;

          if (postIndex == posts.length) {
            return _buildBottomIndicator(isLoadingMore, hasMore);
          }

          final post = posts[postIndex];
          return _buildAestheticPostItem(post);
        },
      ),
    );
  }

  Widget _buildBottomIndicator(bool isLoadingMore, bool hasMore) {
    if (isLoadingMore) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 2,
            ),
          ),
        ),
      );
    }
    if (!hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text(
            'no_more_data'.tr,
            style: TextStyle(fontSize: 12, color: AppColors.textHint),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildTagsSection() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _recommendedTags.length,
        itemBuilder: (context, index) {
          final tag = _recommendedTags[index];
          final isSelected = _selectedTag == tag;
          final themeColor = AppColors.primary;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              onPressed: () => _onTagSelected(tag),
              label: Text(
                "#$tag",
                style: TextStyle(
                  fontSize: 12,
                  color: isSelected ? Colors.white : themeColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              backgroundColor: isSelected ? themeColor : themeColor.withOpacity(0.05),
              elevation: 0,
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAestheticPostItem(dynamic post) {
    final themeColor = AppColors.primary;
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
            onTap: () => Get.to(() => PostDetailView(postId: post['id'] ?? ''))?.then((_) {
              // 从详情页返回时静默同步点赞与购买变化
              _fetchForYou(isRefresh: true);
            }),
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
                        backgroundColor: AppColors.divider,
                        child: authorAvatar.isEmpty ? const Icon(Icons.person, size: 12, color: Colors.grey) : null,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        authorNickname,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () {
                          if (!mounted) return;
                          setState(() {
                            _selectedCategory = category;
                            _selectedTag = null;
                            _isLoadingForYou = true;
                            _isLoadingFeatured = true;
                          });
                          _loadFeeds();
                        },
                        child: Container(
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
                        style: TextStyle(fontSize: 10, color: AppColors.textHint),
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
                        style: TextStyle(fontSize: 10, color: AppColors.textHint, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 14),
                      HugeIcon(
                        icon: isLiked ? HugeIcons.strokeRoundedFavourite : HugeIcons.strokeRoundedFavourite,
                        color: isLiked ? Colors.redAccent : AppColors.textHint,
                        size: 13,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$likesCount',
                        style: TextStyle(
                          fontSize: 10,
                          color: isLiked ? Colors.redAccent : AppColors.textHint,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 14),
                      HugeIcon(
                        icon: isCollected ? HugeIcons.strokeRoundedBookmark01 : HugeIcons.strokeRoundedBookmark01,
                        color: isCollected ? Colors.orangeAccent : AppColors.textHint,
                        size: 13,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$collectsCount',
                        style: TextStyle(
                          fontSize: 10,
                          color: isCollected ? Colors.orangeAccent : AppColors.textHint,
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
                        style: TextStyle(fontSize: 10, color: AppColors.textHint, fontWeight: FontWeight.bold),
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