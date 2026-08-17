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

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // 1. 获取自己发布的文章
      final resMy = await HttpClient.instance.get<Map<String, dynamic>>('/api-users/profile', queryParameters: {'tab': 'published'});
      if (resMy.datas != null) {
        final list = resMy.datas!['posts'] as List? ?? [];
        _myPosts.assignAll(list.map((e) => Map<String, dynamic>.from(e as Map)));
      }

      // 2. 获取自己收藏的文章
      final resCollect = await HttpClient.instance.get<List<dynamic>>('/api-users/collects');
      if (resCollect.datas != null) {
        _myCollects.assignAll(resCollect.datas!.map((e) => Map<String, dynamic>.from(e as Map)));
      }
    } catch (_) {}
    setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // 头部标题
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '选择要分享的文章',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B), size: 22),
                  onPressed: () => Get.back(),
                ),
              ],
            ),
          ),

          // 双 Tab (我发布的 / 我的收藏)
          TabBar(
            controller: _tabController,
            labelColor: _primaryTeal,
            unselectedLabelColor: Colors.grey.shade400,
            indicatorColor: _primaryTeal,
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
            tabs: const [
              Tab(text: '我发布的'),
              Tab(text: '我的收藏'),
            ],
          ),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: _primaryTeal, strokeWidth: 2))
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
      return Center(child: Text('暂无文章', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final post = list[index];
        final title = post['title']?.toString() ?? '无题';
        final snippet = post['content_min']?.toString() ?? '';
        final thumb = post['thumbnail']?.toString() ?? '';

        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            HapticFeedback.mediumImpact();
            Get.back();
            widget.onPostSelected(post);
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                if (thumb.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(thumb, width: 56, height: 56, fit: BoxFit.cover),
                  )
                else
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: _primaryTeal.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.article_rounded, color: _primaryTeal, size: 24),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                      const SizedBox(height: 4),
                      Text(snippet, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
              ],
            ),
          ),
        );
      },
    );
  }
}