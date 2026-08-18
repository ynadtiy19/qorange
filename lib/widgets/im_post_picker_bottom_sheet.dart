// lib/views/im/widgets/im_post_picker_bottom_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';

import '../../../network/http_client.dart';

class ImPostPickerBottomSheet extends StatefulWidget {
  final Function(Map<String, dynamic> postData) onPostSelected;

  const ImPostPickerBottomSheet({
    super.key,
    required this.onPostSelected,
  });

  @override
  State<ImPostPickerBottomSheet> createState() => _ImPostPickerBottomSheetState();
}

class _ImPostPickerBottomSheetState extends State<ImPostPickerBottomSheet> with SingleTickerProviderStateMixin {
  static const Color _primaryTeal = Color.fromRGBO(44, 123, 109, 1.0);
  late TabController _tabController;

  final List<Map<String, dynamic>> _myPosts = [];
  final List<Map<String, dynamic>> _myCollects = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  /// 🌟 极速并发加载轻量级分享数据
  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // 1. 调用轻量专用接口拉取我发布的文章
      final resMy = await HttpClient.instance.get<List<dynamic>>(
        '/api-im/share-posts',
        queryParameters: {'type': 'published', 'limit': '30'},
      );
      if (resMy.datas != null) {
        _myPosts.assignAll(resMy.datas!.map((e) => Map<String, dynamic>.from(e as Map)));
      }

      // 2. 调用轻量专用接口拉取我收藏的文章
      final resCollect = await HttpClient.instance.get<List<dynamic>>(
        '/api-im/share-posts',
        queryParameters: {'type': 'collects', 'limit': '30'},
      );
      if (resCollect.datas != null) {
        _myCollects.assignAll(resCollect.datas!.map((e) => Map<String, dynamic>.from(e as Map)));
      }
    } catch (e) {
      debugPrint("🔴 [PostPicker] 加载分享文章异常: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // 1. 顶部把手与标题
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _primaryTeal.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.auto_stories_rounded, color: _primaryTeal, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      '选择要分享的文章',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B), size: 22),
                  onPressed: () => Get.back(),
                ),
              ],
            ),
          ),

          // 2. 双 Tab 栏 (我发布的 / 我的收藏)
          TabBar(
            controller: _tabController,
            labelColor: _primaryTeal,
            unselectedLabelColor: Colors.grey.shade400,
            indicatorColor: _primaryTeal,
            indicatorSize: TabBarIndicatorSize.label,
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            unselectedLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            tabs: const [
              Tab(text: '我发布的'),
              Tab(text: '我的收藏'),
            ],
          ),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),

          // 3. 列表内容视图
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: _primaryTeal, strokeWidth: 2.5))
                : TabBarView(
              controller: _tabController,
              children: [
                _buildPostList(_myPosts),
                _buildPostList(_myCollects),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostList(List<Map<String, dynamic>> list) {
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.article_outlined, size: 40, color: Colors.grey.shade300),
            const SizedBox(height: 10),
            Text('暂无相关文章', style: TextStyle(color: Colors.grey.shade400, fontSize: 13, fontWeight: FontWeight.w500)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final post = list[index];
        final title = post['title']?.toString() ?? '';
        final snippet = post['content_min']?.toString() ?? '';
        final thumb = post['thumbnail']?.toString() ?? '';
        final category = (post['category']?.toString() ?? '专栏').toUpperCase();
        final postType = post['post_type']?.toString() ?? 'quill';
        final createdAtStr = post['created_at'] != null ? post['created_at'].toString().substring(0, 10) : '';

        final mainHeading = title.isNotEmpty ? title : snippet;
        final hasSubtitle = title.isNotEmpty && snippet.isNotEmpty;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              HapticFeedback.mediumImpact();
              Get.back();
              widget.onPostSelected(post);
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 封面缩略图
                  if (thumb.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        thumb,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _buildFallbackThumb(),
                      ),
                    )
                  else
                    _buildFallbackThumb(),

                  const SizedBox(width: 12),

                  // 文章信息列
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 标签与时间栏
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _primaryTeal.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                category,
                                style: const TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: _primaryTeal,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (postType == 'poll')
                              const Text('· 投票', style: TextStyle(fontSize: 11, color: Color(0xFFD97706), fontWeight: FontWeight.bold))
                            else if (postType == 'short_post')
                              const Text('· 说说', style: TextStyle(fontSize: 11, color: Color(0xFF3B82F6), fontWeight: FontWeight.bold)),
                            const Spacer(),
                            Text(
                              createdAtStr,
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),

                        // 标题
                        Text(
                          mainHeading,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF1E293B)),
                        ),

                        // 摘要
                        if (hasSubtitle) ...[
                          const SizedBox(height: 3),
                          Text(
                            snippet,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.3),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF94A3B8)),
                ],
              ),
            ),
          ),
        );
      },
    ).animate().fadeIn(duration: 200.ms);
  }

  Widget _buildFallbackThumb() {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: _primaryTeal.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.article_rounded, color: _primaryTeal, size: 26),
    );
  }
}