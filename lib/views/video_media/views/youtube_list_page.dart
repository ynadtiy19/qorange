// lib/views/video_media/views/youtube_list_page.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../network/local_media_proxy_server.dart';
import '../controllers/youtube_list_controller.dart';
import '../models/youtube_model.dart';
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
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1D6),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFFFE099)),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFE59819).withValues(alpha: 0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const HugeIcon(
                      icon: HugeIcons.strokeRoundedPlayCircle,
                      color: Color(0xFFE59819),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '青橙视频',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF2C2416),
                          letterSpacing: -0.4,
                        ),
                      ),
                      Text(
                        '开启生活之旅',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF8C806D),
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
                    // 🌟🌟 1. 参考图二重构的极简高级搜索栏 🌟🌟
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Focus(
                        onFocusChange: (hasFocus) {
                          controller.isSearchFocused.value = hasFocus;
                        },
                        child: Obx(() => Container(
                          height: 50,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(26),
                            border: Border.all(
                              color: controller.isSearchFocused.value
                                  ? const Color(0xFFE59819)
                                  : const Color(0xFFE6DFD3),
                              width: controller.isSearchFocused.value ? 1.4 : 1.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF2C2416).withValues(alpha: 0.04),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              const SizedBox(width: 18),
                              // 搜索输入框核心
                              Expanded(
                                child: TextField(
                                  controller: controller.searchTextController,
                                  onChanged: controller.onSearchChanged,
                                  onSubmitted: (val) => controller.performSearch(val),
                                  style: const TextStyle(
                                    color: Color(0xFF2C2416),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  cursorColor: const Color(0xFFE59819),
                                  decoration: const InputDecoration(
                                    hintText: '搜索或提问',
                                    hintStyle: TextStyle(
                                      color: Color(0xFF9E927E),
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w400,
                                    ),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ),

                              // 清除文本按键
                              if (controller.currentSearchQuery.value.isNotEmpty)
                                GestureDetector(
                                  onTap: () {
                                    controller.searchTextController.clear();
                                    controller.currentSearchQuery.value = '';
                                    controller.onTagSelected(controller.categoryTags.first);
                                  },
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 6),
                                    child: Icon(Icons.cancel_rounded, size: 18, color: Color(0xFFB8AA95)),
                                  ),
                                ),

                              // 🌟 右侧内嵌胶囊功能按钮 (例如: 问问YouTube吧 / 智能检索)
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: () {
                                    final text = controller.searchTextController.text.trim();
                                    controller.performSearch(text.isNotEmpty ? text : 'Trending');
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(vertical: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF6F3EC),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: const Color(0xFFEDE7DC)),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        HugeIcon(
                                          icon: HugeIcons.strokeRoundedAiChat02,
                                          color: Color(0xFF2C2416),
                                          size: 15,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          '问问Stream吧',
                                          style: TextStyle(
                                            color: Color(0xFF2C2416),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),

                              // 🌟 最右侧圆形检索放大镜按钮
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: () {
                                    final text = controller.searchTextController.text.trim();
                                    if (text.isNotEmpty) {
                                      controller.performSearch(text);
                                    }
                                  },
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Center(
                                      child: HugeIcon(
                                        icon: HugeIcons.strokeRoundedSearch01,
                                        color: Color(0xFF2C2416),
                                        size: 19,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                          ),
                        )),
                      ),
                    ),

                    // 🌟 2. 水平分类胶囊条
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
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isSelected ? const Color(0xFFFFF2D1) : Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: isSelected ? const Color(0xFFE59819) : const Color(0xFFECE6D8),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF2B2005).withValues(alpha: 0.02),
                                        blurRadius: 4,
                                        offset: const Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                  alignment: Alignment.center,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (tag == '热门推荐') ...[
                                        HugeIcon(
                                          icon: HugeIcons.strokeRoundedFire,
                                          color: isSelected ? const Color(0xFFB57400) : const Color(0xFF8C806D),
                                          size: 13,
                                        ),
                                        const SizedBox(width: 4),
                                      ],
                                      Text(
                                        tag,
                                        style: TextStyle(
                                          color: isSelected ? const Color(0xFF945B00) : const Color(0xFF706452),
                                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
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
            // 3. 搜索历史记录浮层
            if (controller.isSearchFocused.value && controller.searchHistory.isNotEmpty) {
              return _buildSearchHistoryView(controller);
            }

            // 4. 骨架 Loading 态
            if (controller.isLoading.value && controller.videoList.isEmpty) {
              return const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE59819)),
                ),
              );
            }

            // 5. 空列表态
            if (controller.videoList.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF4EFE6),
                        shape: BoxShape.circle,
                      ),
                      child: const HugeIcon(
                        icon: HugeIcons.strokeRoundedVideo01,
                        size: 40,
                        color: Color(0xFFD4A03D),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      '未检索到相关视频内容',
                      style: TextStyle(
                        color: Color(0xFF8C806D),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            }

            // 6. 视频列表与无限分页
            return RefreshIndicator(
              color: const Color(0xFFE59819),
              backgroundColor: Colors.white,
              onRefresh: () async {
                if (controller.currentTag.value.isNotEmpty) {
                  await controller.fetchVideosByTag(controller.currentTag.value);
                } else {
                  await controller.fetchVideosByQuery(controller.currentSearchQuery.value);
                }
              },
              child: ListView.builder(
                controller: controller.scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                itemCount: controller.videoList.length + 1,
                itemBuilder: (context, index) {
                  if (index == controller.videoList.length) {
                    return _buildLoadMoreIndicator(controller);
                  }

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

  Widget _buildSearchHistoryView(YouTubeListController controller) {
    return Container(
      color: const Color(0xFFFBFBF7),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '搜索历史',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2C2416),
                ),
              ),
              InkWell(
                onTap: controller.clearAllHistory,
                borderRadius: BorderRadius.circular(12),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    children: [
                      HugeIcon(
                        icon: HugeIcons.strokeRoundedDelete02,
                        size: 13,
                        color: Color(0xFF8C806D),
                      ),
                      SizedBox(width: 4),
                      Text(
                        '清空',
                        style: TextStyle(fontSize: 11, color: Color(0xFF8C806D), fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: controller.searchHistory.map((term) {
              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFECE6D8)),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      controller.searchTextController.text = term;
                      controller.performSearch(term);
                    },
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            term,
                            style: const TextStyle(fontSize: 12, color: Color(0xFF5A4D3B), fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () => controller.deleteHistoryItem(term),
                            child: const Padding(
                              padding: EdgeInsets.all(2),
                              child: Icon(Icons.close_rounded, size: 13, color: Color(0xFFB8AA95)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadMoreIndicator(YouTubeListController controller) {
    return Obx(() {
      if (controller.isMoreLoading.value) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE59819)),
                  ),
                ),
                SizedBox(width: 10),
                Text(
                  '正在加载更多流媒体...',
                  style: TextStyle(fontSize: 12, color: Color(0xFF8C806D), fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        );
      }
      if (!controller.hasMore.value && controller.videoList.isNotEmpty) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Center(
            child: Text(
              '已加载全部精彩内容 🍀',
              style: TextStyle(fontSize: 11.5, color: Color(0xFFB5AA98), fontWeight: FontWeight.w500),
            ),
          ),
        );
      }
      return const SizedBox(height: 20);
    });
  }
}

class _CleanVideoCard extends StatelessWidget {
  final YouTubeVideoModel video;
  const _CleanVideoCard({required this.video});

  @override
  Widget build(BuildContext context) {
    final proxiedThumbUrl = LocalMediaProxyServer.instance.buildPlayUrl(video.thumbnail);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFECE6D8)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2B2005).withValues(alpha: 0.035),
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
              // 1. 视频封面与时长标签 (优化占位骨架，防白屏)
              Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Container(
                      color: const Color(0xFFF2ECE0), // 优化的温暖浅灰底色
                      child: Image.network(
                        proxiedThumbUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: const Color(0xFFF2ECE0),
                          child: const Center(
                            child: HugeIcon(
                              icon: HugeIcons.strokeRoundedImage01,
                              color: Color(0xFFD4C8B4),
                              size: 28,
                            ),
                          ),
                        ),
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(
                            color: const Color(0xFFF2ECE0),
                            child: const Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
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
                  ),
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: video.isLive
                            ? const Color(0xFFFF4D4F).withValues(alpha: 0.92)
                            : const Color(0xFF1F1A12).withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (video.isLive) ...[
                            Container(
                              width: 5,
                              height: 5,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            video.duration,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              // 2. 作者头像、标题与播放量
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (video.authorAvatar.isNotEmpty)
                      ClipOval(
                        child: Image.network(
                          LocalMediaProxyServer.instance.buildPlayUrl(video.authorAvatar),
                          width: 36,
                          height: 36,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildInitialAvatar(video.author),
                        ),
                      )
                    else
                      _buildInitialAvatar(video.author),

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
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  video.author,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF8C806D),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              if (video.authorVerified) ...[
                                const SizedBox(width: 4),
                                const HugeIcon(
                                  icon: HugeIcons.strokeRoundedCheckmarkBadge01,
                                  color: Color(0xFF1D9BF0),
                                  size: 13,
                                ),
                              ],
                              const SizedBox(width: 6),
                              Text(
                                '• ${video.views}',
                                style: const TextStyle(
                                  color: Color(0xFF8C806D),
                                  fontSize: 12,
                                ),
                              ),
                              if (video.publishedText.isNotEmpty) ...[
                                const SizedBox(width: 4),
                                Text(
                                  '• ${video.publishedText}',
                                  style: const TextStyle(
                                    color: Color(0xFF8C806D),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ],
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

  Widget _buildInitialAvatar(String author) {
    return CircleAvatar(
      radius: 18,
      backgroundColor: const Color(0xFFFFF1D6),
      child: Text(
        author.isNotEmpty ? author[0].toUpperCase() : 'Y',
        style: const TextStyle(
          color: Color(0xFFB57400),
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }
}