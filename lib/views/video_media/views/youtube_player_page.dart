import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:video_player/video_player.dart';
import '../../../network/local_media_proxy_server.dart';
import '../../../services/youtube_service.dart';
import '../controllers/youtube_player_controller.dart';
import '../models/youtube_model.dart';

class YouTubePlayerPage extends StatelessWidget {
  final YouTubeVideoModel videoItem;
  const YouTubePlayerPage({super.key, required this.videoItem});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(
      YouTubePlayerController(initialVideo: videoItem),
      tag: videoItem.videoId,
    );

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          controller.stopPlayback();
          Get.delete<YouTubePlayerController>(tag: videoItem.videoId);
        }
      },
      child: OrientationBuilder(
        builder: (context, orientation) {
          final isLandscape = orientation == Orientation.landscape;

          // 🌟 1. 自研原生播放器视口
          final Widget playerView = _buildCustomPlayerView(context, controller, isLandscape);

          // 🌟 2. 横屏沉浸全屏
          if (isLandscape) {
            return Scaffold(
              backgroundColor: Colors.black,
              body: Center(child: playerView),
            );
          }

          // 🌟 3. 竖屏常规界面
          return Scaffold(
            backgroundColor: const Color(0xFFFBFBF7), // 清亮晨曦米白
            body: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. 播放器核心视口 (16:9)
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: playerView,
                  ),

                  // 2. 视频信息与推荐列表
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      children: [
                        // 返回按钮
                        Row(
                          children: [
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () {
                                  controller.stopPlayback();
                                  Get.back();
                                },
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                  child: Row(
                                    children: [
                                      HugeIcon(
                                        icon: HugeIcons.strokeRoundedArrowLeft01,
                                        color: Color(0xFFE59819),
                                        size: 18,
                                      ),
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

                        // 视频标题
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

                        // 作者卡片与清晰度调节
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
                              Obx(() {
                                final hasStreams =
                                    controller.streamDetail.value?.formatStreams.isNotEmpty ?? false;
                                return Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: hasStreams
                                        ? () => _showQualitySheet(context, controller)
                                        : null,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFF5DE),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: const Color(0xFFFFE099)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const HugeIcon(
                                            icon: HugeIcons.strokeRoundedSettings02,
                                            color: Color(0xFF996100),
                                            size: 13,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            controller.currentQualityLabel.value,
                                            style: const TextStyle(
                                              color: Color(0xFF996100),
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }),
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

                        // 推荐视频卡片列表
                        Obx(() => Column(
                          children: controller.relatedVideos
                              .map((item) => _buildCleanRelatedItem(controller, item))
                              .toList(),
                        )),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 🌟 2. 播放器核心视图（手势交互 + 覆盖控制层）
  Widget _buildCustomPlayerView(
      BuildContext context, YouTubePlayerController controller, bool isLandscape) {
    return Container(
      color: Colors.black,
      child: Obx(() {
        if (controller.isLoading.value) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE59819)),
                ),
                SizedBox(height: 12),
                Text('正在拉取并解封装流媒体...', style: TextStyle(color: Color(0xFFD4C8B4), fontSize: 12)),
              ],
            ),
          );
        }

        if (controller.isError.value || controller.videoPlayerController == null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const HugeIcon(
                  icon: HugeIcons.strokeRoundedAlert02,
                  color: Color(0xFFE59819),
                  size: 32,
                ),
                const SizedBox(height: 8),
                const Text('媒体流加载失败，请检查网络隧道',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 10),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE59819),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () => controller.initVideoPlayer(videoItem.videoId),
                  child: const Text('重试', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          );
        }

        final playerCtrl = controller.videoPlayerController!;

        return Stack(
          alignment: Alignment.center,
          children: [
            // 2.1 原生画面
            Center(
              child: AspectRatio(
                aspectRatio: playerCtrl.value.aspectRatio > 0 ? playerCtrl.value.aspectRatio : 16 / 9,
                child: VideoPlayer(playerCtrl),
              ),
            ),

            // 2.2 手势交互层 (单击显隐、双击左右半屏快进快退)
            Positioned.fill(
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: controller.toggleControls,
                      onDoubleTap: controller.rewind10Seconds,
                      child: Container(),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: controller.toggleControls,
                      onDoubleTap: controller.forward10Seconds,
                      child: Container(),
                    ),
                  ),
                ],
              ),
            ),

            // 2.3 快退 10 秒水波纹动画
            Obx(() => controller.isRewindingRipple.value
                ? Positioned(
              left: 40,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedGoBackward10Sec,
                      color: Color(0xFFE59819),
                      size: 28,
                    ),
                    SizedBox(height: 2),
                    Text('-10s', style: TextStyle(color: Colors.white, fontSize: 11)),
                  ],
                ),
              ),
            )
                : const SizedBox.shrink()),

            // 2.4 快进 10 秒水波纹动画
            Obx(() => controller.isForwardingRipple.value
                ? Positioned(
              right: 40,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedArrowTurnForward,
                      color: Color(0xFFE59819),
                      size: 28,
                    ),
                    SizedBox(height: 2),
                    Text('+10s', style: TextStyle(color: Colors.white, fontSize: 11)),
                  ],
                ),
              ),
            )
                : const SizedBox.shrink()),

            // 2.5 缓冲 Loading 动画
            Obx(() => controller.isBuffering.value
                ? Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE59819)),
              ),
            )
                : const SizedBox.shrink()),

            // 2.6 自研高级浮层控制面板
            Obx(() => AnimatedOpacity(
              opacity: controller.showControls.value ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 250),
              child: IgnorePointer(
                ignoring: !controller.showControls.value,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.65),
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.75),
                      ],
                      stops: const [0.0, 0.25, 0.75, 1.0],
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // 顶部控制条
                      _buildTopBar(context, controller, isLandscape),

                      // 中间播放/暂停按钮
                      _buildCenterControls(controller),

                      // 底部进度条与操作按钮
                      _buildBottomBar(context, controller, isLandscape),
                    ],
                  ),
                ),
              ),
            )),
          ],
        );
      }),
    );
  }

  /// 顶部标题栏
  Widget _buildTopBar(BuildContext context, YouTubePlayerController controller, bool isLandscape) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: isLandscape ? 12 : 6),
      child: Row(
        children: [
          if (isLandscape)
            IconButton(
              icon: const HugeIcon(
                icon: HugeIcons.strokeRoundedArrowLeft01,
                color: Colors.white,
                size: 22,
              ),
              onPressed: controller.toggleFullScreen,
            ),
          Expanded(
            child: Obx(() => Text(
              controller.videoDetail.value.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            )),
          ),
          IconButton(
            icon: const HugeIcon(
              icon: HugeIcons.strokeRoundedSettings02,
              color: Colors.white,
              size: 20,
            ),
            onPressed: () => _showQualitySheet(context, controller),
          ),
        ],
      ),
    );
  }

  /// 中间核心播放/暂停图标
  Widget _buildCenterControls(YouTubePlayerController controller) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(32),
        onTap: controller.togglePlay,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24, width: 1.2),
          ),
          child: Obx(() => HugeIcon(
            icon: controller.isPlaying.value
                ? HugeIcons.strokeRoundedPause
                : HugeIcons.strokeRoundedPlay,
            color: const Color(0xFFE59819),
            size: 34,
          )),
        ),
      ),
    );
  }

  /// 底部进度控制条与工具按钮
  Widget _buildBottomBar(
      BuildContext context, YouTubePlayerController controller, bool isLandscape) {
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, isLandscape ? 14 : 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 进度条 Slider
          Obx(() {
            final max = controller.totalDuration.value.inMilliseconds.toDouble();
            final value = controller.currentPosition.value.inMilliseconds
                .toDouble()
                .clamp(0.0, max > 0 ? max : 1.0);

            return SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3.5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                activeTrackColor: const Color(0xFFE59819),
                inactiveTrackColor: Colors.white24,
                thumbColor: const Color(0xFFE59819),
                overlayColor: const Color(0xFFE59819).withValues(alpha: 0.2),
              ),
              child: Slider(
                value: value,
                min: 0.0,
                max: max > 0 ? max : 1.0,
                onChanged: (val) {
                  controller.seekTo(Duration(milliseconds: val.toInt()));
                },
              ),
            );
          }),

          // 时间显示与右侧工具栏
          Row(
            children: [
              // 时间文本
              Obx(() => Text(
                '${_formatDuration(controller.currentPosition.value)} / ${_formatDuration(controller.totalDuration.value)}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              )),

              const Spacer(),

              // 倍速调节按钮
              Obx(() => TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => _showSpeedSheet(context, controller),
                child: Text(
                  '${controller.playbackSpeed.value}x',
                  style: const TextStyle(
                    color: Color(0xFFE59819),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )),

              const SizedBox(width: 8),

              // 清晰度按钮
              Obx(() => TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => _showQualitySheet(context, controller),
                child: Text(
                  controller.currentQualityLabel.value,
                  style: const TextStyle(
                    color: Color(0xFFE59819),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )),

              const SizedBox(width: 4),

              // 全屏切换按钮（🌟 已移除非法 Obx）
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: HugeIcon(
                  icon: isLandscape
                      ? HugeIcons.strokeRoundedMinimizeScreen
                      : HugeIcons.strokeRoundedMaximizeScreen,
                  color: Colors.white,
                  size: 20,
                ),
                onPressed: controller.toggleFullScreen,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 🌟 3. 画质选择 BottomSheet
  void _showQualitySheet(BuildContext context, YouTubePlayerController controller) {
    final streams = controller.streamDetail.value?.formatStreams ?? [];
    if (streams.isEmpty) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const HugeIcon(
                      icon: HugeIcons.strokeRoundedVideo01,
                      color: Color(0xFFE59819),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '选择视频清晰度',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2C2416),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20, color: Color(0xFF8C806D)),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...streams.map((s) {
                  final isCurrent = controller.currentQualityLabel.value == s.qualityLabel;
                  return ListTile(
                    dense: true,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    tileColor: isCurrent ? const Color(0xFFFFF7E6) : null,
                    leading: HugeIcon(
                      icon: HugeIcons.strokeRoundedVideo01,
                      color: isCurrent ? const Color(0xFFE59819) : const Color(0xFF8C806D),
                      size: 18,
                    ),
                    title: Text(
                      '${s.qualityLabel} (${s.container.toUpperCase()})',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                        color: isCurrent ? const Color(0xFFB57400) : const Color(0xFF2C2416),
                      ),
                    ),
                    trailing: isCurrent
                        ? const Icon(Icons.check_circle_rounded,
                        color: Color(0xFFE59819), size: 18)
                        : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      controller.switchQuality(s);
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 🌟 4. 倍速选择 BottomSheet
  void _showSpeedSheet(BuildContext context, YouTubePlayerController controller) {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '播放速度',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2C2416),
                  ),
                ),
                const SizedBox(height: 8),
                ...speeds.map((sp) {
                  final isCurrent = controller.playbackSpeed.value == sp;
                  return ListTile(
                    dense: true,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    tileColor: isCurrent ? const Color(0xFFFFF7E6) : null,
                    leading: const HugeIcon(
                      icon: HugeIcons.strokeRoundedSpeedTrain01,
                      color: Color(0xFFE59819),
                      size: 18,
                    ),
                    title: Text(
                      '${sp}x ${sp == 1.0 ? '(正常)' : ''}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                        color: isCurrent ? const Color(0xFFB57400) : const Color(0xFF2C2416),
                      ),
                    ),
                    trailing: isCurrent
                        ? const Icon(Icons.check_circle_rounded,
                        color: Color(0xFFE59819), size: 18)
                        : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      controller.setSpeed(sp);
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 推荐列表项
  Widget _buildCleanRelatedItem(YouTubePlayerController controller, YouTubeVideoModel item) {
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
            controller.stopPlayback();
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
                        child: const Center(
                          child: HugeIcon(
                            icon: HugeIcons.strokeRoundedImage01,
                            color: Color(0xFFD4C8B4),
                            size: 24,
                          ),
                        ),
                      ),
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          color: const Color(0xFFF7F3E9),
                          child: const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
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

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return '${twoDigits(duration.inHours)}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
}