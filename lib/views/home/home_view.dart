// lib/views/home/home_view.dart (全能 50 字快照与多维高阶卡片流集成版)
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../network/http_client.dart';
import '../post_detail/post_detail_view.dart';
import '../publish/publish_view.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  // 滚动控制器
  final ScrollController _forYouScrollController = ScrollController();
  final ScrollController _featuredScrollController = ScrollController();

  List<dynamic> _forYouPosts = [];
  List<dynamic> _featuredPosts = [];
  List<dynamic> _recommendedTags = [];

  // 首屏加载状态
  bool _isLoadingForYou = true;
  bool _isLoadingFeatured = true;

  // 分页状态
  int _forYouPage = 1;
  int _featuredPage = 1;
  final int _pageSize = 10;

  bool _hasMoreForYou = true;
  bool _hasMoreFeatured = true;

  bool _isLoadingMoreForYou = false;
  bool _isLoadingMoreFeatured = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // 监听列表滑动
    _forYouScrollController.addListener(_onForYouScroll);
    _featuredScrollController.addListener(_onFeaturedScroll);

    _loadFeeds();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _forYouScrollController.dispose();
    _featuredScrollController.dispose();
    super.dispose();
  }

  // 监听“为你推荐”滚动
  void _onForYouScroll() {
    if (_forYouScrollController.position.pixels >=
        _forYouScrollController.position.maxScrollExtent - 200) {
      _fetchMoreForYou();
    }
  }

  // 监听“精选高赞”滚动
  void _onFeaturedScroll() {
    if (_featuredScrollController.position.pixels >=
        _featuredScrollController.position.maxScrollExtent - 200) {
      _fetchMoreFeatured();
    }
  }

  // 下拉刷新或初始化加载
  Future<void> _loadFeeds() async {
    setState(() {
      _isLoadingForYou = true;
      _isLoadingFeatured = true;
    });
    await Future.wait([
      _fetchForYou(isRefresh: true),
      _fetchFeatured(isRefresh: true),
    ]);
  }

  // 获取/刷新 “为你推荐”
  Future<void> _fetchForYou({bool isRefresh = false}) async {
    if (isRefresh) {
      _forYouPage = 1;
      _hasMoreForYou = true;
    }
    try {
      final res = await HttpClient.instance.get<Map<String, dynamic>>(
        '/api-posts',
        queryParameters: {
          'feed_type': 'for_you',
          'page': _forYouPage,
          'pageSize': _pageSize,
        },
      );
      if (res.datas != null) {
        final List<dynamic> newPosts = res.datas!['posts'] as List? ?? [];
        final List<dynamic> tags = res.datas!['recommended_tags'] as List? ?? [];

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
      setState(() {
        _isLoadingForYou = false;
        _isLoadingMoreForYou = false;
      });
    }
  }

  // 加载更多 “为你推荐”
  Future<void> _fetchMoreForYou() async {
    if (_isLoadingMoreForYou || !_hasMoreForYou || _isLoadingForYou) return;
    setState(() {
      _isLoadingMoreForYou = true;
    });
    _forYouPage++;
    await _fetchForYou(isRefresh: false);
  }

  // 获取/刷新 “精选高赞”
  Future<void> _fetchFeatured({bool isRefresh = false}) async {
    if (isRefresh) {
      _featuredPage = 1;
      _hasMoreFeatured = true;
    }
    try {
      final res = await HttpClient.instance.get<Map<String, dynamic>>(
        '/api-posts',
        queryParameters: {
          'feed_type': 'featured',
          'page': _featuredPage,
          'pageSize': _pageSize,
        },
      );
      if (res.datas != null) {
        final List<dynamic> newPosts = res.datas!['posts'] as List? ?? [];
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
      setState(() {
        _isLoadingFeatured = false;
        _isLoadingMoreFeatured = false;
      });
    }
  }

  // 加载更多 “精选高赞”
  Future<void> _fetchMoreFeatured() async {
    if (_isLoadingMoreFeatured || !_hasMoreFeatured || _isLoadingFeatured) return;
    setState(() {
      _isLoadingMoreFeatured = true;
    });
    _featuredPage++;
    await _fetchFeatured(isRefresh: false);
  }

  // 搜索处理
  void _onSearch(String keyword) async {
    if (keyword.isEmpty) {
      _loadFeeds();
      return;
    }
    setState(() {
      _isLoadingForYou = true;
      _isLoadingFeatured = true;
      _hasMoreForYou = false;
      _hasMoreFeatured = false;
    });
    try {
      final res = await HttpClient.instance.get<Map<String, dynamic>>(
        '/api-posts',
        queryParameters: {'keyword': keyword, 'page': 1, 'pageSize': 50},
      );
      if (res.datas != null) {
        final searchPosts = res.datas!['posts'] as List? ?? [];
        setState(() {
          _forYouPosts = List.from(searchPosts);
          _featuredPosts = List.from(searchPosts);
          _isLoadingForYou = false;
          _isLoadingFeatured = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoadingForYou = false;
        _isLoadingFeatured = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = const Color.fromRGBO(44, 123, 109, 1.0);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        title: const Text(
          "青橙",
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: Color.fromRGBO(44, 123, 109, 1.0),
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () => Get.to(() => const PublishView()),
            icon: const HugeIcon(
              icon: HugeIcons.strokeRoundedQuillWrite02,
              color: Color.fromRGBO(44, 123, 109, 1.0),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: Colors.black,
              unselectedLabelColor: Colors.grey.shade400,
              indicatorColor: themeColor,
              indicatorWeight: 3,
              indicatorSize: TabBarIndicatorSize.label,
              labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              tabs: const [
                Tab(text: "为你推荐"),
                Tab(text: "精选高赞"),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
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
    );
  }

  // 统一构建列表
  Widget _buildPostList({
    required List<dynamic> posts,
    required bool isLoading,
    required bool isForYou,
    required ScrollController scrollController,
    required bool hasMore,
    required bool isLoadingMore,
  }) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color.fromRGBO(44, 123, 109, 1.0),
          strokeWidth: 2,
        ),
      );
    }
    if (posts.isEmpty) {
      return Center(
        child: Text("暂无内容，快去发布吧", style: TextStyle(color: Colors.grey.shade400)),
      );
    }

    final hasTags = isForYou && _recommendedTags.isNotEmpty;
    final extraItemCount = (hasTags ? 1 : 0) + 1;

    return RefreshIndicator(
      onRefresh: _loadFeeds,
      color: const Color.fromRGBO(44, 123, 109, 1.0),
      child: ListView.separated(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: posts.length + extraItemCount,
        separatorBuilder: (context, index) {
          if (hasTags && index == 0) return const SizedBox.shrink();
          if (index >= posts.length + (hasTags ? 1 : 0)) return const SizedBox.shrink();
          // 🌟 采用微型间距取代原本普通扁平线，让精致卡片自然呼吸呼吸
          return const SizedBox(height: 4);
        },
        itemBuilder: (context, index) {
          // 1. 顶部推荐标签栏 (仅“为你推荐”的第一项)
          if (hasTags && index == 0) {
            return _buildTagsSection();
          }

          // 计算当前 post 真实的索引位置
          final postIndex = hasTags ? index - 1 : index;

          // 2. 底部加载更多或无数据提示
          if (postIndex == posts.length) {
            return _buildBottomIndicator(isLoadingMore, hasMore);
          }

          // 3. 🌟 精致美化的学术芯片大卡片
          final post = posts[postIndex];
          return _buildAestheticPostItem(post);
        },
      ),
    );
  }

  // 底部加载状态/到底提示
  Widget _buildBottomIndicator(bool isLoadingMore, bool hasMore) {
    if (isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              color: Color.fromRGBO(44, 123, 109, 1.0),
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
            "没有更多内容了",
            style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
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
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              onPressed: () => _onSearch(tag),
              label: Text("#$tag", style: const TextStyle(fontSize: 12, color: Color.fromRGBO(44, 123, 109, 1.0), fontWeight: FontWeight.bold)),
              backgroundColor: const Color.fromRGBO(44, 123, 109, 0.05),
              elevation: 0,
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
          );
        },
      ),
    );
  }

  // 🌟 精重写：超高质感学术说说与精选高赞芯片大卡片（完美对接 content_min 快照） [1]
  Widget _buildAestheticPostItem(dynamic post) {
    final themeColor = const Color.fromRGBO(44, 123, 109, 1.0);
    if (post == null || post['id'] == null) return const SizedBox.shrink();

    final author = post['author'] ?? {};
    final authorAvatar = author['avatar'] ?? '';
    final authorNickname = author['nickname'] ?? '用户';

    final title = post['title'] ?? '';
    final type = post['post_type'] ?? 'quill';

    // 🌟 核心优化点 1：全面对接服务器端提取出的 50 字 content_min 正文快照，消灭重度首屏数据 [1]
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

    // 如果是说说等无大标题的，自动将 50 字极简正文作为主标题放大展示 [1]
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
                  // 1. 头衔行（用户头像、昵称、学科类别微芯片）
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

                      // 专业学科方向指示小标签
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

                  // 2. 主体区（标题、50字快照、高清裁剪略缩图） [1]
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
                                contentMin, // 🌟 渲染快照 [1]
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

                  // 3. 🌟 数据承接底栏（时间、阅读、点赞红色联动、收藏金色联动、分享）
                  Row(
                    children: [
                      // 1. 发布时间
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

                      // 2. 浏览量
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

                      // 3. 点赞指示器（如果已经点赞，自适应高亮为甜美粉红）
                      HugeIcon(
                        icon: isLiked ? HugeIcons.strokeRoundedFavourite : HugeIcons.strokeRoundedFavourite,
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

                      // 4. 收藏指示器（如果已经收藏，自适应高亮为暖金色）
                      HugeIcon(
                        icon: isCollected ? HugeIcons.strokeRoundedBookmark01 : HugeIcons.strokeRoundedBookmark01,
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

                      // 5. 转发分享数
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