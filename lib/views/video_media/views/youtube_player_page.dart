// lib/modules/youtube/views/youtube_player_page.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:omni_video_player/omni_video_player.dart';
import '../../../network/local_media_proxy_server.dart';
import '../controllers/youtube_player_controller.dart';
import '../models/youtube_model.dart';

class YouTubePlayerPage extends StatelessWidget {
  final YouTubeVideoModel videoItem;
  const YouTubePlayerPage({super.key, required this.videoItem});

  @override
  Widget build(BuildContext context) {
    // 初始化控制器
    final controller = Get.put(
      YouTubePlayerController(initialVideo: videoItem),
      tag: videoItem.videoId,
    );

    final vid = videoItem.videoId.isNotEmpty ? videoItem.videoId : 'dQw4w9WgXcQ';
    final targetVideoUrl = 'https://www.youtube.com/watch?v=$vid';

    return Scaffold(
      backgroundColor: const Color(0xFFFBFBF7), // 清爽晨曦米白
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. 🌟 播放器核心视口（使用 ExcludeSemantics 隔离语义树，杜绝 iOS 原生 View 崩溃）
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                color: Colors.black,
                child: ExcludeSemantics(
                  child: OmniVideoPlayer(
                    callbacks: VideoPlayerCallbacks(
                      onControllerCreated: controller.onControllerCreated,
                      onFinished: () {},
                    ),
                    configuration: VideoPlayerConfiguration(
                      videoSourceConfiguration: VideoSourceConfiguration.youtube(
                        videoUrl: Uri.parse(targetVideoUrl),
                        preferredQualities: const [
                          OmniVideoQuality.high720,
                          OmniVideoQuality.medium480,
                          OmniVideoQuality.medium360,
                        ],
                        availableQualities: const [
                          OmniVideoQuality.high1080,
                          OmniVideoQuality.high720,
                          OmniVideoQuality.medium480,
                          OmniVideoQuality.medium360,
                          OmniVideoQuality.low144,
                        ],
                      ).copyWith(
                        autoPlay: true,
                        initialPosition: Duration.zero,
                        initialVolume: 1.0,
                        allowSeeking: true,
                        timeoutDuration: const Duration(seconds: 25),
                      ),
                      playerTheme: OmniVideoPlayerThemeData().copyWith(
                        icons: VideoPlayerIconTheme().copyWith(
                          playPause: AnimatedIcons.play_pause,
                          fullScreen: Icons.fullscreen_rounded,
                          exitFullScreen: Icons.fullscreen_exit_rounded,
                          mute: Icons.volume_off_rounded,
                          unMute: Icons.volume_up_rounded,
                          playbackSpeedButton: Icons.speed_rounded,
                          error: Icons.warning_amber_rounded,
                        ),
                        backdrop: VideoPlayerBackdropTheme().copyWith(
                          backgroundColor: const Color(0xFF1F1A12),
                          alpha: 40,
                        ),
                      ),
                      playerUIVisibilityOptions: PlayerUIVisibilityOptions().copyWith(
                        showSeekBar: true,
                        showCurrentTime: true,
                        showDurationTime: true,
                        showRemainingTime: false,
                        showFullScreenButton: true,
                        showPlaybackSpeedButton: true,
                        showMuteUnMuteButton: true,
                        showSwitchVideoQuality: true,
                        enableForwardGesture: true,
                        enableBackwardGesture: true,
                        fitVideoToBounds: true,
                      ),
                      customPlayerWidgets: CustomPlayerWidgets().copyWith(
                        loadingWidget: const CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE59819)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // 2. 视频信息与推荐列表（仅局部使用 Obx 响应数据）
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                children: [
                  // 返回按钮与小标题栏
                  Row(
                    children: [
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => Get.back(),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            child: Row(
                              children: [
                                Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: Color(0xFFE59819)),
                                SizedBox(width: 4),
                                Text(
                                  '返回列表',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFE59819),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // 视频标题（局部响应）
                  Obx(() => Text(
                    controller.videoDetail.value.title.isNotEmpty
                        ? controller.videoDetail.value.title
                        : videoItem.title,
                    style: const TextStyle(
                      color: Color(0xFF2C2416),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                    ),
                  )),
                  const SizedBox(height: 10),

                  // 作者卡片（局部响应）
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFECE6D8)),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: const Color(0xFFFFF1D6),
                          child: Obx(() {
                            final author = controller.videoDetail.value.author.isNotEmpty
                                ? controller.videoDetail.value.author
                                : videoItem.author;
                            return Text(
                              author.isNotEmpty ? author[0].toUpperCase() : 'Y',
                              style: const TextStyle(
                                color: Color(0xFFB57400),
                                fontWeight: FontWeight.bold,
                              ),
                            );
                          }),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Obx(() => Text(
                                controller.videoDetail.value.author.isNotEmpty
                                    ? controller.videoDetail.value.author
                                    : videoItem.author,
                                style: const TextStyle(
                                  color: Color(0xFF2C2416),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              )),
                              Obx(() => Text(
                                controller.videoDetail.value.views.isNotEmpty
                                    ? controller.videoDetail.value.views
                                    : videoItem.views,
                                style: const TextStyle(
                                  color: Color(0xFF8C806D),
                                  fontSize: 11,
                                ),
                              )),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF5DE),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFFFE099)),
                          ),
                          child: const Text(
                            'Omni Player',
                            style: TextStyle(
                              color: Color(0xFF996100),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Divider(color: Color(0xFFECE6D8), height: 30),

                  // 推荐列表标题
                  const Text(
                    '推荐流媒体',
                    style: TextStyle(
                      color: Color(0xFF2C2416),
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 推荐视频卡片列表（局部响应）
                  Obx(() => Column(
                    children: controller.relatedVideos
                        .map((item) => _buildCleanRelatedItem(item))
                        .toList(),
                  )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCleanRelatedItem(YouTubeVideoModel item) {
    final proxiedThumb = LocalMediaProxyServer.instance.buildPlayUrl(item.thumbnail);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFECE6D8)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2B2005).withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          splashColor: const Color(0xFFFFEAA7).withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            // 🌟 使用 Get.off 进行规范页面流转，彻底避免旧播放器堆叠冲突
            Get.off(
                  () => YouTubePlayerPage(videoItem: item),
              preventDuplicates: false,
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 110,
                    height: 65,
                    child: Image.network(
                      proxiedThumb,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: const Color(0xFFF7F3E9),
                        child: const Icon(Icons.broken_image_rounded, color: Color(0xFFD4C8B4)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF2C2416),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${item.author} • ${item.duration}',
                        style: const TextStyle(
                          color: Color(0xFF8C806D),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}