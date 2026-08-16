// lib/views/im/widgets/pinterest_gallery_picker_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../network/http_client.dart';

class PinterestGalleryPickerSheet extends StatefulWidget {
  final Function(String selectedUrl) onImageSelected;

  const PinterestGalleryPickerSheet({
    super.key,
    required this.onImageSelected,
  });

  @override
  State<PinterestGalleryPickerSheet> createState() => _PinterestGalleryPickerSheetState();
}

class _PinterestGalleryPickerSheetState extends State<PinterestGalleryPickerSheet> {
  static const Color _primaryTeal = Color.fromRGBO(44, 123, 109, 1.0);

  final List<String> _tags = ['全部'];
  String _selectedTag = '全部';

  final List<Map<String, dynamic>> _images = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _page = 1;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchGalleryData(isRefresh: true);

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
        if (!_isLoadingMore && _hasMore) {
          _fetchGalleryData(isRefresh: false);
        }
      }
    });
  }

  Future<void> _fetchGalleryData({bool isRefresh = false}) async {
    if (isRefresh) {
      setState(() {
        _page = 1;
        _isLoading = true;
        _hasMore = true;
      });
    } else {
      setState(() {
        _isLoadingMore = true;
      });
    }

    try {
      final res = await HttpClient.instance.get<Map<String, dynamic>>(
        '/api-system/gallery',
        queryParameters: {
          'page': '$_page',
          'limit': '20',
          if (_selectedTag != '全部') 'tag': _selectedTag,
        },
      );

      if (res.datas != null) {
        final datas = res.datas!;
        final List<dynamic> rawImages = datas['images'] as List? ?? [];
        final List<dynamic> rawTags = datas['tags'] as List? ?? [];

        final fetchedImages = rawImages.map((e) => Map<String, dynamic>.from(e as Map)).toList();

        setState(() {
          if (isRefresh) {
            _images.clear();
            _images.addAll(fetchedImages);
            if (rawTags.isNotEmpty) {
              _tags.clear();
              _tags.addAll(rawTags.map((t) => t.toString()));
            }
          } else {
            _images.addAll(fetchedImages);
          }

          _hasMore = datas['has_more'] == true;
          _page++;
        });
      }
    } catch (e) {
      debugPrint("🔴 [GalleryPicker] 获取图库失败: $e");
    } finally {
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // 1. 顶部把手条与标题
          Padding(
            padding: const EdgeInsets.only(top: 12, left: 20, right: 12, bottom: 8),
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
                      child: const Icon(Icons.auto_awesome_rounded, color: _primaryTeal, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Pinterest 意境图库壁纸',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                        ),
                        Text(
                          '点击直接设为当前聊天背景',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
                        ),
                      ],
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

          // 2. 标签横向滑动选择栏
          SizedBox(
            height: 44,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              scrollDirection: Axis.horizontal,
              itemCount: _tags.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final tag = _tags[index];
                final isSelected = _selectedTag == tag;

                return ChoiceChip(
                  label: Text(tag),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _selectedTag = tag;
                      });
                      _fetchGalleryData(isRefresh: true);
                    }
                  },
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? Colors.white : const Color(0xFF475569),
                  ),
                  selectedColor: _primaryTeal,
                  backgroundColor: const Color(0xFFF1F5F9),
                  elevation: 0,
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                );
              },
            ),
          ),

          const SizedBox(height: 6),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),

          // 3. 瀑布流壁纸卡片展示区
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: _primaryTeal, strokeWidth: 2.5))
                : _images.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
              color: _primaryTeal,
              onRefresh: () => _fetchGalleryData(isRefresh: true),
              child: GridView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.65, // 9:16 适合作为壁纸比例
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: _images.length + (_hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _images.length) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(color: _primaryTeal, strokeWidth: 2),
                      ),
                    );
                  }

                  final img = _images[index];
                  final String url = img['cloudinary_url']?.toString() ?? '';
                  final String tag = img['tag']?.toString() ?? '';

                  return _buildWallpaperCard(url, tag);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWallpaperCard(String url, String tag) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          HapticFeedback.mediumImpact();
          widget.onImageSelected(url);
          Get.back();
          Fluttertoast.showToast(msg: '聊天壁纸已设置为【#$tag】精选大图');
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  url,
                  fit: BoxFit.cover,
                  loadingBuilder: (c, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      color: const Color(0xFFF1F5F9),
                      child: const Center(
                        child: CircularProgressIndicator(color: _primaryTeal, strokeWidth: 2),
                      ),
                    );
                  },
                  errorBuilder: (_, __, ___) => Container(
                    color: const Color(0xFFF1F5F9),
                    child: const Icon(Icons.broken_image_rounded, color: Color(0xFF94A3B8)),
                  ),
                ),
                // 底部轻量半透明标签渐变
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withOpacity(0.7),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Text(
                      '#$tag',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 250.ms).scale(begin: const Offset(0.96, 0.96), end: const Offset(1, 1));
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(color: Color(0xFFF1F5F9), shape: BoxShape.circle),
            child: const Icon(Icons.photo_library_outlined, color: Color(0xFF94A3B8), size: 32),
          ),
          const SizedBox(height: 12),
          const Text('该分类暂无蓄水池图片', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
          const SizedBox(height: 4),
          const Text('请通过后台 crawl-images 接口继续灌水', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
        ],
      ),
    );
  }
}