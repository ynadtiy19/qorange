// lib/views/video_media/views/media_discovery_view.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';

import '../controllers/media_player_controller.dart';
import '../models/media_item_model.dart';
import 'media_player_view.dart';

class MediaDiscoveryView extends StatelessWidget {
  const MediaDiscoveryView({super.key});

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 10000) return '${(count / 10000).toStringAsFixed(1)}万';
    return '$count';
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(MediaPlayerController());
    final TextEditingController searchC = TextEditingController();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: controller.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: HugeIcon(
                icon: HugeIcons.strokeRoundedPlayList,
                color: controller.primaryColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              '影音探索',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF1E293B)),
            ),
          ],
        ),
        // 🌟 修复输入框对齐与精致设计
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(58),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(width: 14),
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedSearch01,
                    color: controller.primaryColor,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: searchC,
                      textInputAction: TextInputAction.search,
                      textAlignVertical: TextAlignVertical.center, // 🌟 修复：垂直方向严格几何居中
                      onSubmitted: (val) => controller.searchMedia(val),
                      style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B), fontWeight: FontWeight.w500),
                      decoration: InputDecoration(
                        hintText: '搜索全球 YouTube 歌曲、音乐MV、精彩视频...',
                        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero, // 🌟 修复：消除多余内边距导致的文本偏斜
                      ),
                    ),
                  ),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: searchC,
                    builder: (context, value, _) {
                      if (value.text.isEmpty) return const SizedBox.shrink();
                      return IconButton(
                        icon: const Icon(Icons.close_rounded, size: 16, color: Colors.grey),
                        onPressed: () {
                          searchC.clear();
                          controller.loadCategoryFeeds(controller.selectedTrendTag.value);
                        },
                      );
                    },
                  ),
                  const SizedBox(width: 6),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // 🌟 结合热搜潮流趋势的胶囊选择区 (Material + InkWell)
              Container(
                height: 52,
                color: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: controller.trendingChips.length,
                  itemBuilder: (context, index) {
                    final chip = controller.trendingChips[index];
                    return Obx(() {
                      final isSelected = controller.selectedTrendTag.value == chip['name'];
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Material(
                          color: isSelected ? controller.primaryColor : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(20),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            splashColor: controller.primaryColor.withOpacity(0.2),
                            onTap: () {
                              HapticFeedback.lightImpact();
                              controller.selectTrendTag(chip);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                              child: Text(
                                chip['name']!,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                  color: isSelected ? Colors.white : const Color(0xFF64748B),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    });
                  },
                ),
              ),

              // 媒体列表展示
              Expanded(
                child: Obx(() {
                  if (controller.isLoading.value) {
                    return Center(
                      child: CircularProgressIndicator(color: controller.primaryColor, strokeWidth: 2),
                    );
                  }

                  if (controller.mediaList.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          HugeIcon(icon: HugeIcons.strokeRoundedMusicNote01, color: Colors.grey.shade300, size: 54),
                          const SizedBox(height: 12),
                          const Text('暂无相关媒体，换个关键词搜搜看吧', style: TextStyle(color: Colors.grey, fontSize: 13)),
                        ],
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: () => controller.loadCategoryFeeds(controller.selectedTrendTag.value),
                    color: controller.primaryColor,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                      physics: const BouncingScrollPhysics(),
                      itemCount: controller.mediaList.length,
                      itemBuilder: (context, index) {
                        final item = controller.mediaList[index];
                        return _buildAestheticMediaCard(context, controller, item);
                      },
                    ),
                  );
                }),
              ),
            ],
          ),

          // 🌟 底部浮动 Mini 播放条（当有播放任务时显示，随手点回播放器）
          Positioned(
            bottom: 12,
            left: 16,
            right: 16,
            child: Obx(() {
              final item = controller.currentPlaying.value;
              if (item == null) return const SizedBox.shrink();

              return Material(
                elevation: 8,
                shadowColor: Colors.black.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                color: const Color(0xFF0F172A),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => Get.to(() => const MediaPlayerView(), transition: Transition.fadeIn),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            item.thumbnailUrl,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.author,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Color(0xFFE2B04E), fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            controller.isPlaying.value ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,
                            color: const Color(0xFFE2B04E),
                            size: 34,
                          ),
                          onPressed: controller.togglePlayPause,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  // 🌟 高质感 Material 卡片设计
  Widget _buildAestheticMediaCard(BuildContext context, MediaPlayerController controller, MediaItemModel item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          splashColor: controller.primaryColor.withOpacity(0.08),
          onTap: () {
            HapticFeedback.lightImpact();
            controller.playMedia(item);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 封面与时长角标
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Image.network(
                        item.thumbnailUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (c, e, s) => Container(
                          color: controller.primaryColor.withOpacity(0.05),
                          child: Center(
                            child: HugeIcon(icon: HugeIcons.strokeRoundedMusicNote01, color: controller.primaryColor),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 10,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.75),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        item.duration,
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: controller.primaryColor.withOpacity(0.85),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
                      ),
                    ),
                  ),
                ],
              ),

              // 标题、作者与操作栏
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Color(0xFF1E293B),
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.person_outline_rounded, size: 14, color: Colors.grey.shade500),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  item.author,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${_formatCount(item.viewsCount)} 播放 · ${item.uploadDate}',
                                style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),

                    // 一键离线下载按钮
                    Obx(() {
                      if (item.isDownloading.value) {
                        return SizedBox(
                          width: 36,
                          height: 36,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CircularProgressIndicator(
                                value: item.downloadProgress.value,
                                strokeWidth: 2.5,
                                color: controller.primaryColor,
                                backgroundColor: const Color(0xFFE2E8F0),
                              ),
                              Text(
                                '${(item.downloadProgress.value * 100).toInt()}%',
                                style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: controller.primaryColor),
                              )
                            ],
                          ),
                        );
                      }

                      return IconButton(
                        onPressed: () => controller.downloadMediaToLocal(item),
                        icon: HugeIcon(
                          icon: item.isDownloaded.value
                              ? HugeIcons.strokeRoundedCheckmarkCircle02
                              : HugeIcons.strokeRoundedDownload01,
                          color: item.isDownloaded.value ? Colors.green : const Color(0xFF64748B),
                          size: 20,
                        ),
                      );
                    }),
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