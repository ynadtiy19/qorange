// lib/views/video_media/views/media_player_view.dart
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:video_player/video_player.dart';

import '../controllers/media_player_controller.dart';
import '../models/media_item_model.dart';

class MediaPlayerView extends StatefulWidget {
  const MediaPlayerView({super.key});

  @override
  State<MediaPlayerView> createState() => _MediaPlayerViewState();
}

class _MediaPlayerViewState extends State<MediaPlayerView> with SingleTickerProviderStateMixin {
  final MediaPlayerController controller = Get.find<MediaPlayerController>();
  late AnimationController _vinylController;
  bool _showVideoControls = true;
  Timer? _controlsTimer;

  @override
  void initState() {
    super.initState();
    _vinylController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
  }

  @override
  void dispose() {
    _vinylController.dispose();
    _controlsTimer?.cancel();
    // 🌟 修复：退出当前播放页时，自动触发暂停，杜绝后台持续播放
    controller.pauseOnPlayerExit();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _triggerControlsVisibility() {
    setState(() => _showVideoControls = !_showVideoControls);
    _controlsTimer?.cancel();
    if (_showVideoControls) {
      _controlsTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _showVideoControls = false);
      });
    }
  }

  void _showDescriptionSheet(MediaItemModel item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 20),
              const Text('视频 / 歌曲详细简介', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Text(
                    item.description.isNotEmpty ? item.description : "暂无详细描述",
                    style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.6),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color obsidianBg = const Color(0xFF0F172A);
    final Color goldAccent = const Color(0xFFE2B04E);

    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        // 🌟 拦截物理返回按键，安全暂停
        controller.pauseOnPlayerExit();
      },
      child: Scaffold(
        backgroundColor: obsidianBg,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            onPressed: () {
              controller.pauseOnPlayerExit();
              Get.back();
            },
            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 30),
          ),
          title: Obx(() => Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  controller.isVideoMode.value ? '🎬 超清视频模式' : '🎵 黑胶纯乐模式',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70),
                ),
              ],
            ),
          )),
          centerTitle: true,
          actions: [
            // 切换视频/音频模式按钮
            Obx(() => IconButton(
              onPressed: () {
                HapticFeedback.selectionClick();
                controller.toggleVideoAudioMode();
              },
              tooltip: controller.isVideoMode.value ? "切换到黑胶纯乐" : "切换到超清视频",
              icon: HugeIcon(
                icon: controller.isVideoMode.value
                    ? HugeIcons.strokeRoundedMusicNote01
                    : HugeIcons.strokeRoundedVideo01,
                color: goldAccent,
                size: 20,
              ),
            )),
            Obx(() {
              final item = controller.currentPlaying.value;
              if (item == null) return const SizedBox.shrink();
              return IconButton(
                onPressed: () => _showDescriptionSheet(item),
                icon: HugeIcon(icon: HugeIcons.strokeRoundedInformationCircle, color: goldAccent, size: 20),
              );
            }),
          ],
        ),
        body: Obx(() {
          final item = controller.currentPlaying.value;
          if (item == null) {
            return const Center(child: Text("未选择播放内容", style: TextStyle(color: Colors.white)));
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Column(
                children: [
                  const Spacer(),

                  // 核心画面展示区
                  if (controller.isVideoMode.value)
                    _buildVideoPlayerSection(goldAccent)
                  else
                    _buildVinylRecordSection(item, goldAccent),

                  const Spacer(),

                  // 标题与作者
                  Text(
                    item.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900, height: 1.3),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.author,
                    style: TextStyle(color: goldAccent, fontSize: 13, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 28),

                  // 拖动进度条
                  Obx(() {
                    final pos = controller.currentPosition.value;
                    final total = controller.totalDuration.value;
                    final maxVal = total.inMilliseconds.toDouble();
                    final currentVal = pos.inMilliseconds.toDouble().clamp(0.0, maxVal > 0 ? maxVal : 1.0);

                    return Column(
                      children: [
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3.5,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                            activeTrackColor: goldAccent,
                            inactiveTrackColor: Colors.white12,
                            thumbColor: goldAccent,
                          ),
                          child: Slider(
                            value: currentVal,
                            max: maxVal > 0 ? maxVal : 1.0,
                            onChanged: (val) {
                              controller.seekTo(Duration(milliseconds: val.toInt()));
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_formatDuration(pos), style: const TextStyle(color: Colors.white54, fontSize: 11)),
                              Text(_formatDuration(total), style: const TextStyle(color: Colors.white54, fontSize: 11)),
                            ],
                          ),
                        ),
                      ],
                    );
                  }),

                  const SizedBox(height: 20),

                  // 控制栏 (Material + InkWell 触控)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // 离线下载按钮
                      Obx(() {
                        final isDownloading = item.isDownloading.value;
                        final isDownloaded = item.isDownloaded.value;

                        return IconButton(
                          onPressed: () => controller.downloadMediaToLocal(
                            item,
                            downloadVideo: controller.isVideoMode.value,
                          ),
                          icon: HugeIcon(
                            icon: isDownloaded
                                ? HugeIcons.strokeRoundedCheckmarkCircle02
                                : HugeIcons.strokeRoundedDownload01,
                            color: isDownloaded ? Colors.greenAccent : (isDownloading ? goldAccent : Colors.white60),
                            size: 22,
                          ),
                        );
                      }),

                      // 播放/暂停大按键 (Material 涟漪按压)
                      Material(
                        color: goldAccent,
                        shape: const CircleBorder(),
                        elevation: 6,
                        shadowColor: goldAccent.withOpacity(0.35),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          splashColor: Colors.black.withOpacity(0.2),
                          onTap: controller.togglePlayPause,
                          child: Container(
                            padding: const EdgeInsets.all(18),
                            child: controller.isMediaLoading.value
                                ? const SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2.5),
                            )
                                : Obx(() => Icon(
                              controller.isPlaying.value ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              color: Colors.black,
                              size: 32,
                            )),
                          ),
                        ),
                      ),

                      // 简介抽屉按钮
                      IconButton(
                        onPressed: () => _showDescriptionSheet(item),
                        icon: const HugeIcon(
                          icon: HugeIcons.strokeRoundedTextWrap,
                          color: Colors.white60,
                          size: 22,
                        ),
                      ),
                    ],
                  ),

                  const Spacer(),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  /// 视频播放器视图
  Widget _buildVideoPlayerSection(Color goldAccent) {
    final vCtrl = controller.videoPlayerController;

    if (vCtrl != null && vCtrl.value.isInitialized) {
      return GestureDetector(
        onTap: _triggerControlsVisibility,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: AspectRatio(
            aspectRatio: vCtrl.value.aspectRatio,
            child: Stack(
              alignment: Alignment.center,
              children: [
                VideoPlayer(vCtrl),
                if (_showVideoControls)
                  AnimatedOpacity(
                    opacity: _showVideoControls ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      color: Colors.black38,
                      child: Center(
                        child: IconButton(
                          iconSize: 48,
                          icon: Icon(
                            vCtrl.value.isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                            color: goldAccent,
                          ),
                          onPressed: controller.togglePlayPause,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    } else {
      return Container(
        height: 220,
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: CircularProgressIndicator(color: goldAccent, strokeWidth: 2.5),
        ),
      );
    }
  }

  /// 黑胶唱片动效视图
  Widget _buildVinylRecordSection(MediaItemModel item, Color goldAccent) {
    return Center(
      child: RotationTransition(
        turns: _vinylController,
        child: Container(
          width: 250,
          height: 250,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF1E293B),
            border: Border.all(color: goldAccent.withOpacity(0.3), width: 3),
            boxShadow: [
              BoxShadow(
                color: goldAccent.withOpacity(0.12),
                blurRadius: 30,
                spreadRadius: 2,
              )
            ],
          ),
          child: ClipOval(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: ClipOval(
                child: Image.network(
                  item.thumbnailUrl,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}