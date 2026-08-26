import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/youtube_list_controller.dart';
import 'youtube_player_page.dart';

class YouTubeListPage extends StatelessWidget {
  const YouTubeListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(YouTubeListController());

    return Scaffold(
      backgroundColor: const Color(0xFFFBFBF7), // 清亮晨曦米白
      body: SafeArea(
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverAppBar(
              floating: true,
              pinned: false,
              snap: true,
              backgroundColor: const Color(0xFFFBFBF7),
              elevation: 0,
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1D6), // 柔和淡黄色容器
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFFE5A3)),
                    ),
                    child: const Icon(
                      Icons.play_circle_filled_rounded,
                      color: Color(0xFFE59819), // 暖蜂蜜金图标
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Omni Stream',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF2C2416),
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        'Clear & Bright Media Hub',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF9E927E),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(122),
                child: Column(
                  children: [
                    // 1. 简约纯白淡黄色搜索框
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: Material(
                        color: Colors.transparent,
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: const Color(0xFFEDE6D8)),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF2B2005).withValues(alpha: 0.04),
                                blurRadius: 14,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: TextField(
                            controller: controller.searchTextController,
                            onChanged: controller.onSearchChanged,
                            style: const TextStyle(color: Color(0xFF2C2416), fontSize: 14),
                            cursorColor: const Color(0xFFE59819),
                            decoration: InputDecoration(
                              hintText: '搜索视频、音乐或输入 YouTube 链接...',
                              hintStyle: TextStyle(
                                color: const Color(0xFF2C2416).withValues(alpha: 0.35),
                                fontSize: 13,
                              ),
                              prefixIcon: const Icon(
                                Icons.search_rounded,
                                color: Color(0xFFD4A03D),
                                size: 21,
                              ),
                              suffixIcon: Obx(() => controller.searchKeyword.value.isNotEmpty
                                  ? Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: () {
                                    controller.searchTextController.clear();
                                    controller.onSearchChanged('');
                                  },
                                  child: const Icon(
                                    Icons.cancel_rounded,
                                    size: 18,
                                    color: Color(0xFFB8AA95),
                                  ),
                                ),
                              )
                                  : const SizedBox.shrink()),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 13),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // 2. 淡黄色滑动胶囊标签
                    SizedBox(
                      height: 52,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: controller.categoryTags.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final tag = controller.categoryTags[index];
                          return Obx(() {
                            final isSelected = controller.currentTag.value == tag;
                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => controller.onTagSelected(tag),
                                borderRadius: BorderRadius.circular(20),
                                splashColor: const Color(0xFFFFEAA7).withValues(alpha: 0.5),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isSelected ? const Color(0xFFFFF2D1) : Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: isSelected
                                          ? const Color(0xFFE59819)
                                          : const Color(0xFFECE5D8),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF2B2005).withValues(alpha: 0.02),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    tag,
                                    style: TextStyle(
                                      color: isSelected
                                          ? const Color(0xFF945B00)
                                          : const Color(0xFF706452),
                                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          body: Obx(() {
            if (controller.isLoading.value && controller.videoList.isEmpty) {
              return const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE59819)),
                ),
              );
            }

            if (controller.videoList.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.video_collection_outlined,
                      size: 60,
                      color: const Color(0xFFD4A03D).withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '未检索到相关内容',
                      style: TextStyle(
                        color: Color(0xFF9E927E),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              );
            }

            return RefreshIndicator(
              color: const Color(0xFFE59819),
              backgroundColor: Colors.white,
              onRefresh: () async {
                if (controller.currentTag.value.isNotEmpty) {
                  await controller.fetchVideosByTag(controller.currentTag.value);
                } else {
                  await controller.fetchVideosByQuery(controller.searchTextController.text);
                }
              },
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                itemCount: controller.videoList.length,
                itemBuilder: (context, index) {
                  final video = controller.videoList[index];
                  return _CleanVideoCard(video: video);
                },
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _CleanVideoCard extends StatelessWidget {
  final dynamic video;
  const _CleanVideoCard({required this.video});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white, // 纯白卡片底
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFECE6D8)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2B2005).withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          splashColor: const Color(0xFFFFEAA7).withValues(alpha: 0.3),
          highlightColor: const Color(0xFFFFEAA7).withValues(alpha: 0.15),
          onTap: () => Get.to(() => YouTubePlayerPage(videoItem: video)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 封面图与时长标签
              Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      video.thumbnail,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: const Color(0xFFF7F3E9),
                        child: const Icon(Icons.broken_image_rounded, color: Color(0xFFD4C8B4)),
                      ),
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          color: const Color(0xFFF7F3E9),
                          child: const Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE59819)),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1F1A12).withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        video.duration,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // 标题与作者
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: const Color(0xFFFFF1D6),
                      child: Text(
                        video.author.isNotEmpty ? video.author[0].toUpperCase() : 'Y',
                        style: const TextStyle(
                          color: Color(0xFFB57400),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            video.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF2C2416),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${video.author} • ${video.views}',
                            style: const TextStyle(
                              color: Color(0xFF8C806D),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}