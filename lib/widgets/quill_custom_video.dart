// lib/widgets/quill_custom_video.dart (原生硬件解码直连 + 帖内多视频上下滑切 + 零报错全功能完全体)
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../network/http_client.dart';
import '../user_controller.dart';
import '../views/login/login_view.dart';
import '../views/profile/profile_view.dart';

/// 🌟 1. 自定义 Quill 视频数据载荷模型
class VideoBlockEmbed extends quill.CustomBlockEmbed {
  static const String embedType = 'custom_video';

  VideoBlockEmbed(Map<String, dynamic> data)
      : super(embedType, jsonEncode(data));

  static Map<String, dynamic> parseData(dynamic rawData) {
    if (rawData is Map<String, dynamic>) return rawData;
    if (rawData is String) {
      try {
        return jsonDecode(rawData) as Map<String, dynamic>;
      } catch (_) {}
    }
    return {};
  }
}

/// 🌟 2. VideoEmbedBuilder
class VideoEmbedBuilder extends quill.EmbedBuilder {
  final Map<String, dynamic>? author;
  final List<Map<String, dynamic>> Function()? onExtractAllVideosInPost;

  VideoEmbedBuilder({
    this.author,
    this.onExtractAllVideosInPost,
  });

  @override
  String get key => VideoBlockEmbed.embedType;

  @override
  bool get expanded => false;

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final rawData = embedContext.node.value.data;
    final Map<String, dynamic> videoData = VideoBlockEmbed.parseData(rawData);

    if (author != null) {
      videoData['author_id'] ??= author!['id'] ?? author!['_id'];
      videoData['author_nickname'] ??= author!['nickname'];
      videoData['author_avatar'] ??= author!['avatar'];
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14.0),
      child: QuillCustomVideoWidget(
        videoData: videoData,
        author: author,
        readOnly: embedContext.readOnly,
        onExtractAllVideosInPost: onExtractAllVideosInPost,
        onUpdateData: (updatedMap) {
          final offset = embedContext.node.documentOffset;
          embedContext.controller.replaceText(
            offset,
            1,
            quill.BlockEmbed.custom(VideoBlockEmbed(updatedMap)),
            null,
          );
        },
        onDeleteRequested: () {
          final offset = embedContext.node.documentOffset;
          embedContext.controller.replaceText(offset, 1, '', null);
        },
      ),
    );
  }
}

/// 🌟 3. 富文本内的视频卡片小部件
class QuillCustomVideoWidget extends StatefulWidget {
  final Map<String, dynamic> videoData;
  final Map<String, dynamic>? author;
  final bool readOnly;
  final Function(Map<String, dynamic> updatedMap)? onUpdateData;
  final List<Map<String, dynamic>> Function()? onExtractAllVideosInPost;
  final VoidCallback? onDeleteRequested;

  const QuillCustomVideoWidget({
    super.key,
    required this.videoData,
    this.author,
    this.readOnly = false,
    this.onUpdateData,
    this.onExtractAllVideosInPost,
    this.onDeleteRequested,
  });

  @override
  State<QuillCustomVideoWidget> createState() => _QuillCustomVideoWidgetState();
}

class _QuillCustomVideoWidgetState extends State<QuillCustomVideoWidget> {
  VideoPlayerController? _videoPlayerController;
  bool _isPlayingInline = false;
  bool _isInitialized = false;
  bool _isSelected = false;

  static const Color _primaryTeal = Color.fromRGBO(44, 123, 109, 1.0);

  @override
  void dispose() {
    _videoPlayerController?.dispose();
    super.dispose();
  }

  void _toggleInlinePlay() async {
    final videoUrl = widget.videoData['video_url']?.toString() ?? '';
    if (videoUrl.isEmpty) return;

    if (_videoPlayerController == null) {
      _videoPlayerController =
          VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      await _videoPlayerController!.initialize();
      if (mounted) setState(() => _isInitialized = true);
    }

    if (_videoPlayerController!.value.isPlaying) {
      _videoPlayerController!.pause();
      if (mounted) setState(() => _isPlayingInline = false);
    } else {
      _videoPlayerController!.play();
      if (mounted) setState(() => _isPlayingInline = true);
    }
  }

  void _showDeleteConfirmSheet() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            top: 16,
            left: 24,
            right: 24,
            bottom: MediaQuery.of(context).padding.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: const HugeIcon(
                  icon: HugeIcons.strokeRoundedDelete02,
                  color: Colors.redAccent,
                  size: 28,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                '移除此视频组件？',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '移除后该视频将从文章内容中清除。',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13, color: Color(0xFF64748B), height: 1.4),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() => _isSelected = false);
                      },
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('取消',
                          style: TextStyle(
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        if (widget.onDeleteRequested != null) {
                          widget.onDeleteRequested!();
                          Fluttertoast.showToast(msg: "视频组件已移除");
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('确认移除',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showEditCaptionSheet() {
    final currentCaption = widget.videoData['caption']?.toString() ?? '';
    final TextEditingController captionC =
    TextEditingController(text: currentCaption);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            top: 16,
            left: 24,
            right: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _primaryTeal.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const HugeIcon(
                      icon: HugeIcons.strokeRoundedPencilEdit02,
                      color: _primaryTeal,
                      size: 18.0,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    '编辑视频描述 / 注解',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: TextField(
                  controller: captionC,
                  maxLines: 3,
                  minLines: 1,
                  style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B)),
                  decoration: const InputDecoration(
                    hintText: '为这个视频写下一段深度见解或说明（可选）...',
                    hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                    border: InputBorder.none,
                    contentPadding:
                    EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    final newCaption = captionC.text.trim();
                    final newMap = Map<String, dynamic>.from(widget.videoData);
                    newMap['caption'] = newCaption;

                    if (widget.onUpdateData != null) {
                      widget.onUpdateData!(newMap);
                    }
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryTeal,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text(
                    '保存视频注解',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _launchFullscreenReels() {
    final videoUrl = widget.videoData['video_url']?.toString() ?? '';
    if (videoUrl.isEmpty) return;

    _videoPlayerController?.pause();
    setState(() => _isPlayingInline = false);

    List<Map<String, dynamic>> allVideoMaps = [];
    if (widget.onExtractAllVideosInPost != null) {
      allVideoMaps = widget.onExtractAllVideosInPost!();
    }
    if (allVideoMaps.isEmpty) {
      allVideoMaps = [widget.videoData];
    }

    int targetIndex = allVideoMaps
        .indexWhere((m) => m['video_url']?.toString() == videoUrl);
    if (targetIndex < 0) targetIndex = 0;

    Get.to(
          () => _FullscreenReelsPlayerScreen(
        videoList: allVideoMaps,
        initialIndex: targetIndex,
        author: widget.author,
      ),
      transition: Transition.fadeIn,
    );
  }

  @override
  Widget build(BuildContext context) {
    final thumbnailUrl = widget.videoData['thumbnail_url']?.toString() ?? '';
    final caption = widget.videoData['caption']?.toString() ?? '';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (!widget.readOnly) {
          HapticFeedback.lightImpact();
          setState(() {
            _isSelected = !_isSelected;
          });
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _isSelected ? Colors.redAccent : const Color(0xFFE2E8F0),
            width: _isSelected ? 2.5 : 1.0,
          ),
          boxShadow: [
            if (_isSelected)
              BoxShadow(
                color: Colors.redAccent.withOpacity(0.25),
                blurRadius: 16,
                offset: const Offset(0, 4),
              )
            else
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_isPlayingInline &&
                            _videoPlayerController != null &&
                            _isInitialized)
                          VideoPlayer(_videoPlayerController!)
                        else if (thumbnailUrl.isNotEmpty)
                          Image.network(
                            thumbnailUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _buildPlaceholder(),
                          )
                        else
                          _buildPlaceholder(),

                        if (!_isPlayingInline)
                          Container(color: Colors.black.withOpacity(0.25)),

                        Center(
                          child: GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              _toggleInlinePlay();
                            },
                            child: Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.55),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: Center(
                                child: HugeIcon(
                                  icon: _isPlayingInline
                                      ? HugeIcons.strokeRoundedPause
                                      : HugeIcons.strokeRoundedPlay,
                                  color: Colors.white,
                                  size: 24.0,
                                ),
                              ),
                            ),
                          ),
                        ),

                        Positioned(
                          top: 10,
                          right: 10,
                          child: GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              _launchFullscreenReels();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.55),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: Colors.white.withOpacity(0.3),
                                    width: 1),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  HugeIcon(
                                    icon: HugeIcons.strokeRoundedMaximize02,
                                    color: Colors.white,
                                    size: 13.0,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'Reels 全屏',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: widget.readOnly ? null : _showEditCaptionSheet,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
                      ),
                      child: Row(
                        children: [
                          const HugeIcon(
                            icon: HugeIcons.strokeRoundedNote01,
                            color: Color(0xFF94A3B8),
                            size: 15.0,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              caption.isNotEmpty
                                  ? caption
                                  : (widget.readOnly
                                  ? '无视频描述'
                                  : '点击添加视频说明文案 / 注解...'),
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: caption.isNotEmpty
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: caption.isNotEmpty
                                    ? const Color(0xFF334155)
                                    : const Color(0xFF94A3B8),
                                fontStyle: caption.isEmpty
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (!widget.readOnly) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: _primaryTeal.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const HugeIcon(
                                icon: HugeIcons.strokeRoundedPencilEdit02,
                                color: _primaryTeal,
                                size: 13.0,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (_isSelected && !widget.readOnly)
                Positioned(
                  top: 10,
                  left: 10,
                  child: GestureDetector(
                    onTap: _showDeleteConfirmSheet,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: const Color(0xFF0F172A),
      child: const Center(
        child: HugeIcon(
          icon: HugeIcons.strokeRoundedPlayList,
          color: Color(0xFF475569),
          size: 42.0,
        ),
      ),
    );
  }
}

/// 🌟 4. 全屏 Reels 播放器（采用纯原生 HTTPS 直连 + PageView，零代理、零报错）
class _FullscreenReelsPlayerScreen extends StatefulWidget {
  final List<Map<String, dynamic>> videoList;
  final int initialIndex;
  final Map<String, dynamic>? author;

  const _FullscreenReelsPlayerScreen({
    required this.videoList,
    required this.initialIndex,
    this.author,
  });

  @override
  State<_FullscreenReelsPlayerScreen> createState() =>
      _FullscreenReelsPlayerScreenState();
}

class _FullscreenReelsPlayerScreenState
    extends State<_FullscreenReelsPlayerScreen> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: widget.videoList.length,
            onPageChanged: (idx) {
              setState(() => _currentIndex = idx);
            },
            itemBuilder: (context, index) {
              final vMap = widget.videoList[index];
              return _DirectReelsVideoPage(
                videoMap: vMap,
                author: widget.author,
                isActive: index == _currentIndex,
                totalCount: widget.videoList.length,
                currentIndex: index,
              );
            },
          ),
          // 顶部退出按钮
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: IconButton(
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedCancel01,
                  color: Colors.white,
                  size: 22.0,
                ),
                onPressed: () => Get.back(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 🌟 5. 单个直连视频播放页（直接连接 Zeabur 原生 HTTPS，带双击点赞、长按2X倍速）
class _DirectReelsVideoPage extends StatefulWidget {
  final Map<String, dynamic> videoMap;
  final Map<String, dynamic>? author;
  final bool isActive;
  final int totalCount;
  final int currentIndex;

  const _DirectReelsVideoPage({
    required this.videoMap,
    this.author,
    required this.isActive,
    required this.totalCount,
    required this.currentIndex,
  });

  @override
  State<_DirectReelsVideoPage> createState() => _DirectReelsVideoPageState();
}

class _DirectReelsVideoPageState extends State<_DirectReelsVideoPage> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _showHeartAnim = false;
  bool _isFastForwarding = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  @override
  void didUpdateWidget(covariant _DirectReelsVideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        _controller?.play();
      } else {
        _controller?.pause();
      }
    }
  }

  Future<void> _initPlayer() async {
    final videoUrl = widget.videoMap['video_url']?.toString() ?? '';
    if (videoUrl.isEmpty) return;

    try {
      // 🌟 直接连接 Zeabur 原生 HTTPS 流，100% 走 ExoPlayer 原生硬件解码
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(videoUrl),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );

      await _controller!.initialize();
      _controller!.setLooping(true);

      if (mounted) {
        setState(() => _isInitialized = true);
        if (widget.isActive) {
          _controller!.play();
        }
      }
    } catch (e) {
      debugPrint("🔴 直连播放初始化异常: $e");
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onDoubleTapLike() {
    setState(() => _showHeartAnim = true);
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _showHeartAnim = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final thumbnailUrl = widget.videoMap['thumbnail_url']?.toString() ?? '';

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. 视频底层与手势监听
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (_controller != null && _isInitialized) {
              if (_controller!.value.isPlaying) {
                _controller!.pause();
              } else {
                _controller!.play();
              }
              setState(() {});
            }
          },
          onDoubleTap: _onDoubleTapLike,
          onLongPressStart: (_) {
            if (_controller != null && _isInitialized) {
              _controller!.setPlaybackSpeed(2.0);
              HapticFeedback.mediumImpact();
              setState(() => _isFastForwarding = true);
            }
          },
          onLongPressEnd: (_) {
            if (_controller != null && _isInitialized) {
              _controller!.setPlaybackSpeed(1.0);
              setState(() => _isFastForwarding = false);
            }
          },
          child: Center(
            child: _isInitialized && _controller != null
                ? AspectRatio(
              aspectRatio: _controller!.value.aspectRatio,
              child: VideoPlayer(_controller!),
            )
                : (thumbnailUrl.isNotEmpty
                ? Image.network(thumbnailUrl, fit: BoxFit.cover)
                : const Center(
              child: CircularProgressIndicator(
                color: Color.fromRGBO(44, 123, 109, 1.0),
                strokeWidth: 2,
              ),
            )),
          ),
        ),

        // 2. 长按 2X 倍速提示徽章
        if (_isFastForwarding)
          Positioned(
            top: 70,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.65),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedPlayListFavourite01,
                      color: Colors.amber,
                      size: 16.0,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      '2.0X 极速播放中',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // 3. 双击点赞飘心动画
        if (_showHeartAnim)
          Center(
            child: const HugeIcon(
              icon: HugeIcons.strokeRoundedFavourite,
              color: Colors.redAccent,
              size: 90.0,
            ),
          ),

        // 4. 社交互动覆盖层 (点赞、评论、分享、作者资料)
        _ReelsSocialOverlayWidget(
          videoMap: widget.videoMap,
          author: widget.author,
          totalVideosInPost: widget.totalCount,
          currentIndex: widget.currentIndex,
        ),

        // 5. 底部进度条 (Scrubber)
        if (_controller != null && _isInitialized)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: VideoProgressIndicator(
              _controller!,
              allowScrubbing: true,
              colors: const VideoProgressColors(
                playedColor: Color.fromRGBO(44, 123, 109, 1.0),
                bufferedColor: Colors.white24,
                backgroundColor: Colors.transparent,
              ),
            ),
          ),
      ],
    );
  }
}

/// 🌟 6. 独立的视频社交互动覆盖层
class _ReelsSocialOverlayWidget extends StatefulWidget {
  final Map<String, dynamic> videoMap;
  final Map<String, dynamic>? author;
  final int totalVideosInPost;
  final int currentIndex;

  const _ReelsSocialOverlayWidget({
    required this.videoMap,
    this.author,
    required this.totalVideosInPost,
    required this.currentIndex,
  });

  @override
  State<_ReelsSocialOverlayWidget> createState() =>
      _ReelsSocialOverlayWidgetState();
}

class _ReelsSocialOverlayWidgetState extends State<_ReelsSocialOverlayWidget> {
  bool _isLiked = false;
  int _likesCount = 0;
  int _commentsCount = 0;

  @override
  void initState() {
    super.initState();
    _likesCount =
        int.tryParse(widget.videoMap['likes_count']?.toString() ?? '0') ?? 0;
    _commentsCount =
        int.tryParse(widget.videoMap['comments_count']?.toString() ?? '0') ?? 0;
    _isLiked = widget.videoMap['is_liked'] == true;

    _fetchRealtimeVideoDetails();
  }

  String get _resolvedVideoId {
    final vMap = widget.videoMap;
    final vUrl = vMap['video_url']?.toString() ?? '';
    if (vMap['id'] != null && vMap['id'].toString().isNotEmpty) {
      return vMap['id'].toString();
    }
    if (vUrl.contains('/files/')) {
      return vUrl.split('/files/').last.replaceAll('.mp4', '');
    }
    return '';
  }

  Future<void> _fetchRealtimeVideoDetails() async {
    final videoId = _resolvedVideoId;
    if (videoId.isEmpty) return;

    try {
      final res = await HttpClient.instance.get<Map<String, dynamic>>(
        '/api-videos/$videoId',
      );
      if (res.respCode == 0 && res.datas != null) {
        final data = res.datas!;
        if (mounted) {
          setState(() {
            _isLiked = data['is_liked'] == true;
            _likesCount = int.tryParse(data['likes_count']?.toString() ?? '0') ??
                _likesCount;
            _commentsCount =
                int.tryParse(data['comments_count']?.toString() ?? '0') ??
                    _commentsCount;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _toggleVideoLike() async {
    if (!UserController.to.isLoggedIn) {
      Get.to(() => const LoginView());
      Fluttertoast.showToast(msg: "请登录后点赞视频");
      return;
    }

    HapticFeedback.lightImpact();
    final String videoId = _resolvedVideoId;

    setState(() {
      _isLiked = !_isLiked;
      _likesCount += _isLiked ? 1 : -1;
    });

    try {
      final res = await HttpClient.instance.post<Map<String, dynamic>>(
        '/api-videos/$videoId/like',
      );
      if (res.respCode == 0 && res.datas != null) {
        if (mounted) {
          setState(() {
            _isLiked = res.datas!['is_liked'] == true;
            _likesCount = res.datas!['likes_count'] ?? _likesCount;
          });
        }
      }
    } catch (_) {}
  }

  void _openVideoCommentSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _VideoCommentBottomSheet(
        videoId: _resolvedVideoId,
        onCommentCountChanged: (newCount) {
          if (mounted) setState(() => _commentsCount = newCount);
        },
      ),
    );
  }

  void _shareVideo() {
    final String caption = widget.videoMap['caption']?.toString() ?? '';
    final String videoUrl = widget.videoMap['video_url']?.toString() ?? '';

    Share.share(
      '🎬 给你分享一段精彩视频内容：\n$caption\n$videoUrl',
      subject: '精彩视频分享',
    );
  }

  @override
  Widget build(BuildContext context) {
    final String caption = widget.videoMap['caption']?.toString() ?? '';
    final authorMap = widget.author ?? {};
    final String authorName = authorMap['nickname']?.toString() ??
        widget.videoMap['author_nickname']?.toString() ??
        '创作者';
    final String authorAvatar = authorMap['avatar']?.toString() ??
        widget.videoMap['author_avatar']?.toString() ??
        '';
    final String authorId = authorMap['id']?.toString() ??
        widget.videoMap['author_id']?.toString() ??
        '';

    return Positioned.fill(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.totalVideosInPost > 1) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Text(
                          '本帖第 ${widget.currentIndex + 1}/${widget.totalVideosInPost} 条视频 (上下滑动切换)',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 10),
                        ),
                      ),
                    ],
                    GestureDetector(
                      onTap: () {
                        if (authorId.isNotEmpty) {
                          Get.to(() => ProfileView(profileId: authorId));
                        }
                      },
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundImage: authorAvatar.isNotEmpty
                                ? NetworkImage(authorAvatar)
                                : null,
                            backgroundColor: Colors.white24,
                            child: authorAvatar.isEmpty
                                ? const HugeIcon(
                              icon: HugeIcons.strokeRoundedUser,
                              color: Colors.white,
                              size: 16.0,
                            )
                                : null,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            authorName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (caption.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        caption,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          height: 1.4,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: _toggleVideoLike,
                    child: Column(
                      children: [
                        HugeIcon(
                          icon: _isLiked
                              ? HugeIcons.strokeRoundedFavourite
                              : HugeIcons.strokeRoundedFavourite,
                          color: _isLiked
                              ? const Color(0xFFEF4444)
                              : Colors.white,
                          size: 28.0,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$_likesCount',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: _openVideoCommentSheet,
                    child: Column(
                      children: [
                        const HugeIcon(
                          icon: HugeIcons.strokeRoundedComment01,
                          color: Colors.white,
                          size: 28.0,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$_commentsCount',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: _shareVideo,
                    child: const Column(
                      children: [
                        HugeIcon(
                          icon: HugeIcons.strokeRoundedShare01,
                          color: Colors.white,
                          size: 26.0,
                        ),
                        SizedBox(height: 4),
                        Text(
                          '分享',
                          style: TextStyle(
                              color: Colors.white, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 🌟 7. 独立视频评论二级回复抽屉
class _VideoCommentBottomSheet extends StatefulWidget {
  final String videoId;
  final Function(int count)? onCommentCountChanged;

  const _VideoCommentBottomSheet({
    required this.videoId,
    this.onCommentCountChanged,
  });

  @override
  State<_VideoCommentBottomSheet> createState() =>
      _VideoCommentBottomSheetState();
}

class _VideoCommentBottomSheetState extends State<_VideoCommentBottomSheet> {
  final TextEditingController _inputC = TextEditingController();
  List<dynamic> _comments = [];
  bool _isLoading = true;
  String? _replyParentId;
  String? _replyToUserId;
  String _hint = '写下对视频的看法...';

  static const Color _primaryTeal = Color.fromRGBO(44, 123, 109, 1.0);

  @override
  void initState() {
    super.initState();
    _loadVideoComments();
  }

  Future<void> _loadVideoComments() async {
    if (widget.videoId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final res = await HttpClient.instance.get<List<dynamic>>(
        '/api-videos/${widget.videoId}/comments',
      );
      if (res.respCode == 0 && res.datas != null) {
        if (mounted) {
          setState(() {
            _comments = res.datas!;
            _isLoading = false;
          });
          widget.onCommentCountChanged?.call(_comments.length);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendComment() async {
    final text = _inputC.text.trim();
    if (text.isEmpty || widget.videoId.isEmpty) return;

    if (!UserController.to.isLoggedIn) {
      Get.to(() => const LoginView());
      Fluttertoast.showToast(msg: "请登录后参与评论");
      return;
    }

    try {
      final res = await HttpClient.instance.post<Map<String, dynamic>>(
        '/api-videos/${widget.videoId}/comments',
        data: {
          'content': text,
          if (_replyParentId != null) 'parent_comment_id': _replyParentId,
          if (_replyToUserId != null) 'reply_to_user_id': _replyToUserId,
        },
      );

      if (res.respCode == 0) {
        _inputC.clear();
        setState(() {
          _replyParentId = null;
          _replyToUserId = null;
          _hint = '写下对视频的看法...';
        });
        _loadVideoComments();
      }
    } catch (e) {
      Fluttertoast.showToast(msg: "发送评论失败: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '视频讨论 (${_comments.length})',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                child: CircularProgressIndicator(
                    color: _primaryTeal, strokeWidth: 2))
                : _comments.isEmpty
                ? const Center(
              child: Text('暂无讨论，快来发表第一条见解吧',
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
            )
                : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _comments.length,
              separatorBuilder: (_, __) => const Divider(
                  height: 16, color: Color(0xFFF8FAFC)),
              itemBuilder: (context, index) {
                final c = _comments[index];
                final author = c['author'] ?? {};
                final replies = c['replies'] as List? ?? [];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundImage:
                          NetworkImage(author['avatar'] ?? ''),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment.start,
                            children: [
                              Text(
                                author['nickname'] ?? '学者',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                c['content'] ?? '',
                                style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF1E293B)),
                              ),
                              const SizedBox(height: 4),
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _replyParentId = c['id'];
                                    _replyToUserId = author['id'];
                                    _hint =
                                    '回复 @${author['nickname']}...';
                                  });
                                },
                                child: Text('回复',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: _primaryTeal,
                                        fontWeight:
                                        FontWeight.bold)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (replies.isNotEmpty)
                      Padding(
                        padding:
                        const EdgeInsets.only(left: 38, top: 8),
                        child: Column(
                          children: replies.map((r) {
                            final rAuth = r['author'] ?? {};
                            return Padding(
                              padding:
                              const EdgeInsets.only(bottom: 6.0),
                              child: Row(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    radius: 10,
                                    backgroundImage: NetworkImage(
                                        rAuth['avatar'] ?? ''),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: RichText(
                                      text: TextSpan(
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF334155)),
                                        children: [
                                          TextSpan(
                                            text:
                                            '${rAuth['nickname']}: ',
                                            style: const TextStyle(
                                                fontWeight:
                                                FontWeight.bold),
                                          ),
                                          TextSpan(
                                              text: r['content'] ?? ''),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TextField(
                      controller: _inputC,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: _hint,
                        hintStyle: const TextStyle(
                            color: Color(0xFF94A3B8), fontSize: 12),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const HugeIcon(
                    icon: HugeIcons.strokeRoundedSent,
                    color: _primaryTeal,
                    size: 20,
                  ),
                  onPressed: _sendComment,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}