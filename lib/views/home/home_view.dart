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

  List<dynamic> _forYouPosts = [];
  List<dynamic> _featuredPosts = [];
  List<dynamic> _recommendedTags = [];

  bool _isLoadingForYou = true;
  bool _isLoadingFeatured = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadFeeds();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFeeds() async {
    await Future.wait([
      _fetchForYou(),
      _fetchFeatured(),
    ]);
  }

  Future<void> _fetchForYou() async {
    try {
      final res = await HttpClient.instance.get<Map<String, dynamic>>(
        '/api-posts',
        queryParameters: {'feed_type': 'for_you', 'page': 1, 'pageSize': 20},
      );
      if (res.datas != null) {
        setState(() {
          _forYouPosts = res.datas!['posts'] as List? ?? [];
          _recommendedTags = res.datas!['recommended_tags'] as List? ?? [];
          _isLoadingForYou = false;
        });
      }
    } catch (e) {
      setState(() => _isLoadingForYou = false);
    }
  }

  Future<void> _fetchFeatured() async {
    try {
      final res = await HttpClient.instance.get<Map<String, dynamic>>(
        '/api-posts',
        queryParameters: {'feed_type': 'featured', 'page': 1, 'pageSize': 20},
      );
      if (res.datas != null) {
        setState(() {
          _featuredPosts = res.datas!['posts'] as List? ?? [];
          _isLoadingFeatured = false;
        });
      }
    } catch (e) {
      setState(() => _isLoadingFeatured = false);
    }
  }

  void _onSearch(String keyword) async {
    if (keyword.isEmpty) {
      _loadFeeds();
      return;
    }
    setState(() {
      _isLoadingForYou = true;
      _isLoadingFeatured = true;
    });
    try {
      final res = await HttpClient.instance.get<Map<String, dynamic>>(
        '/api-posts',
        queryParameters: {'keyword': keyword},
      );
      if (res.datas != null) {
        setState(() {
          _forYouPosts = res.datas!['posts'] as List? ?? [];
          _featuredPosts = res.datas!['posts'] as List? ?? [];
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
          preferredSize: const Size.fromHeight(100),
          child: Column(
            children: [
              // Padding(
              //   padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              //   child: Container(
              //     height: 40,
              //     decoration: BoxDecoration(
              //       color: Colors.grey.shade50,
              //       borderRadius: BorderRadius.circular(20),
              //     ),
              //     child: TextField(
              //       controller: _searchController,
              //       onSubmitted: _onSearch,
              //       decoration: InputDecoration(
              //         hintText: "搜索感兴趣的高能观点...",
              //         hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              //         prefixIcon: Icon(Icons.search, color: Colors.grey.shade400, size: 18),
              //         border: InputBorder.none,
              //         contentPadding: const EdgeInsets.symmetric(vertical: 11),
              //       ),
              //     ),
              //   ),
              // ),
              Align(
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
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPostList(_forYouPosts, _isLoadingForYou, true),
          _buildPostList(_featuredPosts, _isLoadingFeatured, false),
        ],
      ),
    );
  }

  Widget _buildPostList(List<dynamic> posts, bool isLoading, bool isForYou) {
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
    return RefreshIndicator(
      onRefresh: _loadFeeds,
      color: const Color.fromRGBO(44, 123, 109, 1.0),
      child: ListView.separated(
        itemCount: posts.length + (isForYou && _recommendedTags.isNotEmpty ? 1 : 0),
        separatorBuilder: (context, index) => Divider(color: Colors.grey.shade100, height: 1),
        itemBuilder: (context, index) {
          if (isForYou && _recommendedTags.isNotEmpty && index == 0) {
            return _buildTagsSection();
          }
          final post = posts[isForYou && _recommendedTags.isNotEmpty ? index - 1 : index];
          return _buildPostItem(post);
        },
      ),
    );
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

  Widget _buildPostItem(dynamic post) {
    final author = post['author'] ?? {};
    final title = post['title'] ?? '';
    final type = post['post_type'] ?? 'quill';
    final likesCount = (post['likes'] as List?)?.length ?? 0;
    final viewsCount = post['views_count'] ?? 0;
    final timestamp = post['created_at'] != null
        ? post['created_at'].toString().substring(0, 10)
        : '';
    final thumbnail = post['thumbnail'] ?? '';

    return Material(
      color: Colors.white,
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
                    backgroundImage: NetworkImage(author['avatar'] ?? ''),
                    backgroundColor: Colors.grey.shade100,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    author['nickname'] ?? '用户',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  const Spacer(),
                  if (type != 'quill')
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color.fromRGBO(44, 123, 109, 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        type == 'poll' ? "投票" : "短说说",
                        style: const TextStyle(fontSize: 10, color: Color.fromRGBO(44, 123, 109, 1.0), fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title.isEmpty ? (post['content'] ?? '') : title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black, height: 1.3),
                        ),
                        const SizedBox(height: 6),
                        if (type == 'quill' && title.isNotEmpty)
                          Text(
                            post['content'] != null ? post['content'].toString() : '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade500, height: 1.3),
                          ),
                      ],
                    ),
                  ),
                  if (thumbnail.isNotEmpty) ...[
                    const SizedBox(width: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        thumbnail,
                        width: 80,
                        height: 60,
                        fit: BoxFit.cover,
                        errorBuilder: (c, e, s) => const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(timestamp, style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                  const Spacer(),
                  Icon(Icons.remove_red_eye_outlined, size: 14, color: Colors.grey.shade400),
                  const SizedBox(width: 4),
                  Text('$viewsCount', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                  const SizedBox(width: 16),
                  Icon(Icons.thumb_up_outlined, size: 14, color: Colors.grey.shade400),
                  const SizedBox(width: 4),
                  Text('$likesCount', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}