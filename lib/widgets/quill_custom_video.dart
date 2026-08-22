// lib/widgets/quill_custom_video.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:qorange/theme.dart';

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

/// 🌟 2. VideoEmbedBuilder (精准物理位置更新与防误删防弹键盘)
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
        // 🌟 原位安全替换：先查实时 offset，保障文案保存即生效
        onUpdateData: (updatedMap) {
          final doc = embedContext.controller.document;
          int currentOffset = 0;
          bool replaced = false;

          for (final op in doc.toDelta().toList()) {
            if (op.isInsert && op.data is Map) {
              final map = op.data as Map;
              if (map.containsKey('custom_video')) {
                final parsed = VideoBlockEmbed.parseData(map['custom_video']);
                if (parsed['video_url'] == videoData['video_url'] ||
                    (parsed['id'] != null && parsed['id'] == videoData['id'])) {
                  embedContext.controller.replaceText(
                    currentOffset,
                    1,
                    quill.BlockEmbed.custom(VideoBlockEmbed(updatedMap)),
                    null,
                  );
                  replaced = true;
                  break;
                }
              }
            }
            currentOffset += op.length!;
          }

          if (!replaced && embedContext.node.parent != null) {
            embedContext.controller.replaceText(
              embedContext.node.documentOffset,
              1,
              quill.BlockEmbed.custom(VideoBlockEmbed(updatedMap)),
              null,
            );
          }
        },
        // 🌟 防误删节点
        onDeleteRequested: () {
          final doc = embedContext.controller.document;
          int currentOffset = 0;
          bool deleted = false;

          for (final op in doc.toDelta().toList()) {
            if (op.isInsert && op.data is Map) {
              final map = op.data as Map;
              if (map.containsKey('custom_video')) {
                final parsed = VideoBlockEmbed.parseData(map['custom_video']);
                if (parsed['video_url'] == videoData['video_url'] ||
                    (parsed['id'] != null && parsed['id'] == videoData['id'])) {
                  final plainText = doc.toPlainText();
                  int deleteLen = 1;
                  if (currentOffset + 1 < plainText.length &&
                      plainText[currentOffset + 1] == '\n') {
                    deleteLen = 2;
                  }
                  embedContext.controller.replaceText(currentOffset, deleteLen, '', null);
                  deleted = true;
                  break;
                }
              }
            }
            currentOffset += op.length!;
          }

          if (!deleted && embedContext.node.parent != null) {
            embedContext.controller.replaceText(
              embedContext.node.documentOffset,
              1,
              '',
              null,
            );
          }
        },
        // 🌟 支持视频在富文本中安全上移/下移一个段落
        // 修复：旧逻辑 ① 只删嵌入符不删行尾换行 → 原地残留空段落
        //        ② 下移目标点落在视频自身行尾 → 最后的视频"下移失效"
        //        ③ 最底部判断 off-by-one（视频位于最后段时偏移为 length-2）
        onMoveRequested: (bool moveUp) {
          final doc = embedContext.controller.document;
          int currentOffset = 0;
          bool found = false;

          for (final op in doc.toDelta().toList()) {
            if (op.isInsert && op.data is Map) {
              final map = op.data as Map;
              if (map.containsKey('custom_video')) {
                final parsed = VideoBlockEmbed.parseData(map['custom_video']);
                if (parsed['video_url'] == videoData['video_url'] ||
                    (parsed['id'] != null && parsed['id'] == videoData['id'])) {
                  found = true;
                  break;
                }
              }
            }
            currentOffset += op.length!;
          }

          if (!found) return;

          final plainText = doc.toPlainText();
          // 视频节点在纯文本中占 1 个 \uFFFC 字符，其后恒跟随 1 个段落换行符
          final bool hasTerminator =
              currentOffset + 1 < plainText.length &&
              plainText[currentOffset + 1] == '\n';
          final int deleteLen = hasTerminator ? 2 : 1;

          if (moveUp) {
            // 视频即首段（偏移 0）时已在最顶部
            if (currentOffset <= 0) {
              Fluttertoast.showToast(msg: 'video_at_top'.tr);
              return;
            }
            // 目标：上一个段落的开头（位于删除点之前，偏移不受删除影响）
            final int prevNewline =
                plainText.lastIndexOf('\n', currentOffset - 2);
            final int targetOffset = prevNewline == -1 ? 0 : prevNewline + 1;

            // 1) 整行移除视频（嵌入符 + 行尾换行），不残留空段落
            embedContext.controller.replaceText(
              currentOffset,
              deleteLen,
              '',
              null,
            );
            // 2) 在上一段开头插入视频（自带新行）
            embedContext.controller.replaceText(
              targetOffset,
              0,
              quill.BlockEmbed.custom(VideoBlockEmbed(videoData)),
              null,
            );
            Fluttertoast.showToast(msg: 'video_moved_up'.tr);
          } else {
            // 视频行后只剩最终换行符 → 已是最后一段
            if (currentOffset + 2 >= plainText.length) {
              Fluttertoast.showToast(msg: 'video_at_bottom'.tr);
              return;
            }
            // 下一段自己的行尾换行符（currentOffset+1 是视频自身的行尾）
            final int nextLineTerminator =
                plainText.indexOf('\n', currentOffset + 2);
            if (nextLineTerminator == -1) {
              Fluttertoast.showToast(msg: 'video_at_bottom'.tr);
              return;
            }
            // 目标：下一段行尾之后；删除 2 字符后整体偏移 -2
            final int insertAt = (nextLineTerminator + 1) - deleteLen;

            // 1) 整行移除视频
            embedContext.controller.replaceText(
              currentOffset,
              deleteLen,
              '',
              null,
            );
            // 2) 插到下一段之后，形成新的视频行
            embedContext.controller.replaceText(
              insertAt,
              0,
              quill.BlockEmbed.custom(VideoBlockEmbed(videoData)),
              null,
            );
            Fluttertoast.showToast(msg: 'video_moved_down'.tr);
          }
        },
      ),
    );
  }
}

/// 🌟 3. 富文本内的视频卡片小部件（阻断键盘弹起、文案实时双向同步）
class QuillCustomVideoWidget extends StatefulWidget {
  final Map<String, dynamic> videoData;
  final Map<String, dynamic>? author;
  final bool readOnly;
  final Function(Map<String, dynamic> updatedMap)? onUpdateData;
  final List<Map<String, dynamic>> Function()? onExtractAllVideosInPost;
  final VoidCallback? onDeleteRequested;
  final Function(bool moveUp)? onMoveRequested; // 🌟 接收移动请求

  const QuillCustomVideoWidget({
    super.key,
    required this.videoData,
    this.author,
    this.readOnly = false,
    this.onUpdateData,
    this.onExtractAllVideosInPost,
    this.onDeleteRequested,
    this.onMoveRequested, // 🌟
  });

  @override
  State<QuillCustomVideoWidget> createState() => _QuillCustomVideoWidgetState();
}

class _QuillCustomVideoWidgetState extends State<QuillCustomVideoWidget> {
  VideoPlayerController? _videoPlayerController;
  bool _isPlayingInline = false;
  bool _isInitialized = false;
  bool _isSelected = false;
  late Map<String, dynamic> _currentVideoData;

  static Color get _primaryTeal => AppColors.primary;

  @override
  void initState() {
    super.initState();
    _currentVideoData = Map<String, dynamic>.from(widget.videoData);
  }

  @override
  void didUpdateWidget(covariant QuillCustomVideoWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 🌟 无论 Map 引用是否变化，直接同步最新数据并触发重绘
    _currentVideoData = Map<String, dynamic>.from(widget.videoData);
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _videoPlayerController?.dispose();
    super.dispose();
  }

  void _toggleInlinePlay() async {
    final videoUrl = _currentVideoData['video_url']?.toString() ?? '';
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
    FocusScope.of(context).unfocus(); // 🌟 解除富文本焦点
    HapticFeedback.mediumImpact();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(color: AppColors.surface,
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
                    color: AppColors.divider,
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
              Text(
                'video_remove_title'.tr,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'video_remove_desc'.tr,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13, color: AppColors.textSecondary, height: 1.4),
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
                        side: BorderSide(color: AppColors.divider),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text('cancel'.tr,
                          style: TextStyle(
                              color: AppColors.textSecondary,
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
                          Fluttertoast.showToast(msg: "video_removed".tr);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text('video_remove_confirm'.tr,
                          style: const TextStyle(
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
    FocusScope.of(context).unfocus(); // 🌟 阻止外界键盘弹起
    final currentCaption = _currentVideoData['caption']?.toString() ?? '';
    final TextEditingController captionC =
    TextEditingController(text: currentCaption);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomContext) {
        return Container(
          decoration: BoxDecoration(color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            top: 16,
            left: 24,
            right: 24,
            bottom: MediaQuery.of(bottomContext).viewInsets.bottom + 24,
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
                    color: AppColors.divider,
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
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedPencilEdit02,
                      color: _primaryTeal,
                      size: 18.0,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'video_caption_title'.tr,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.divider),
                ),
                child: TextField(
                  controller: captionC,
                  maxLines: 3,
                  minLines: 1,
                  autofocus: true,
                  style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'video_caption_hint'.tr,
                    hintStyle: TextStyle(color: AppColors.textHint, fontSize: 13),
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
                    final newMap = Map<String, dynamic>.from(_currentVideoData);
                    newMap['caption'] = newCaption;

                    // 🌟 1. 优先立即强制刷新当前卡片底部的文字状态
                    if (mounted) {
                      setState(() {
                        _currentVideoData = newMap;
                      });
                    }

                    // 🌟 2. 同步写入 Quill 的 Delta 数据链
                    widget.onUpdateData?.call(newMap);

                    Navigator.pop(bottomContext);
                    Fluttertoast.showToast(msg: "video_caption_saved".tr);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryTeal,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    'video_caption_save'.tr,
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
    FocusScope.of(context).unfocus();
    final videoUrl = _currentVideoData['video_url']?.toString() ?? '';
    if (videoUrl.isEmpty) return;

    _videoPlayerController?.pause();
    setState(() => _isPlayingInline = false);

    List<Map<String, dynamic>> allVideoMaps = [];
    if (widget.onExtractAllVideosInPost != null) {
      allVideoMaps = widget.onExtractAllVideosInPost!();
    }
    if (allVideoMaps.isEmpty) {
      allVideoMaps = [_currentVideoData];
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
    final thumbnailUrl = _currentVideoData['thumbnail_url']?.toString() ?? '';
    final caption = _currentVideoData['caption']?.toString() ?? '';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        FocusScope.of(context).unfocus(); // 🌟 阻断外界键盘响应
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
          color: AppColors.background,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _isSelected ? Colors.redAccent : AppColors.divider,
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
                              FocusScope.of(context).unfocus();
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
                              FocusScope.of(context).unfocus();
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
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const HugeIcon(
                                    icon: HugeIcons.strokeRoundedMaximize02,
                                    color: Colors.white,
                                    size: 13.0,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'video_reels_fullscreen'.tr,
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
                      decoration: BoxDecoration(color: AppColors.surface,
                        border: Border(top: BorderSide(color: AppColors.surfaceAlt)),
                      ),
                      child: Row(
                        children: [
                          HugeIcon(
                            icon: HugeIcons.strokeRoundedNote01,
                            color: AppColors.textHint,
                            size: 15.0,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              caption.isNotEmpty
                                  ? caption
                                  : (widget.readOnly
                                  ? 'video_no_caption'.tr
                                  : 'video_add_caption'.tr),
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: caption.isNotEmpty
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: caption.isNotEmpty
                                    ? AppColors.textPrimary
                                    : AppColors.textHint,
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
                              child: HugeIcon(
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
              // 🌟 选中状态下的高功能悬浮操作栏（支持上移、下移、注解、删除）
              if (_isSelected && !widget.readOnly)
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: AppColors.textHint, blurRadius: 10, offset: Offset(0, 3)),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 上移按钮
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            widget.onMoveRequested?.call(true);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            child: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 18),
                          ),
                        ),
                        const SizedBox(width: 2),
                        // 下移按钮
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            widget.onMoveRequested?.call(false);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            child: const Icon(Icons.arrow_downward_rounded, color: Colors.white, size: 18),
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 14,
                          color: Colors.white24,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                        ),
                        // 移除按钮
                        GestureDetector(
                          onTap: _showDeleteConfirmSheet,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            child: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                          ),
                        ),
                      ],
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
      color: AppColors.textPrimary,
      child: Center(
        child: HugeIcon(
          icon: HugeIcons.strokeRoundedPlayList,
          color: AppColors.textSecondary,
          size: 42.0,
        ),
      ),
    );
  }
}

/// 🌟 4. 全屏 Reels 播放器（直连硬件解码 + 开启防挤压）
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
      resizeToAvoidBottomInset: false, // 🌟 核心防挤压：打开评论键盘时，视频画面绝不形变上移
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

/// 🌟 5. 单个直连视频播放页（搭载防手势误触 + 放大交互进度条）
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
                : Center(
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 2,
              ),
            )),
          ),
        ),
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
                    Text(
                      'video_fast_forward'.tr,
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
        if (_showHeartAnim)
          const Center(
            child: HugeIcon(
              icon: HugeIcons.strokeRoundedFavourite,
              color: Colors.redAccent,
              size: 90.0,
            ),
          ),
        _ReelsSocialOverlayWidget(
          videoMap: widget.videoMap,
          author: widget.author,
          totalVideosInPost: widget.totalCount,
          currentIndex: widget.currentIndex,
        ),
        // 🌟 自定义拖动进度条（带放大交互与防小白条手势避让）
        if (_controller != null && _isInitialized)
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 6,
            left: 0,
            right: 0,
            child: _InteractiveReelsProgressBar(controller: _controller!),
          ),
      ],
    );
  }
}

/// 🌟 6. 高品质自绘制交互进度条（触碰即放大 + 避让系统小白条防误触）
class _InteractiveReelsProgressBar extends StatefulWidget {
  final VideoPlayerController controller;

  const _InteractiveReelsProgressBar({required this.controller});

  @override
  State<_InteractiveReelsProgressBar> createState() =>
      _InteractiveReelsProgressBarState();
}

class _InteractiveReelsProgressBarState
    extends State<_InteractiveReelsProgressBar> {
  bool _isDragging = false;
  double _dragValue = 0.0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerUpdate);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerUpdate);
    super.dispose();
  }

  void _onControllerUpdate() {
    if (!_isDragging && mounted) {
      setState(() {});
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final duration = widget.controller.value.duration;
    final position = widget.controller.value.position;

    final double totalMs = duration.inMilliseconds.toDouble();
    final double currentMs = position.inMilliseconds.toDouble();
    final double progress = totalMs > 0 ? (currentMs / totalMs).clamp(0.0, 1.0) : 0.0;
    final double displayProgress = _isDragging ? _dragValue : progress;

    return Stack(
      alignment: Alignment.bottomCenter,
      clipBehavior: Clip.none,
      children: [
        // 拖拽时浮现的大字号时间气泡
        if (_isDragging)
          Positioned(
            bottom: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.85),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24),
              ),
              child: Text(
                '${_formatDuration(Duration(milliseconds: (displayProgress * totalMs).toInt()))} / ${_formatDuration(duration)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),

        // 触控条（热区扩大至 32px 彻底消灭切 App 冲突）
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (details) {
            final box = context.findRenderObject() as RenderBox?;
            if (box == null) return;
            HapticFeedback.selectionClick();
            setState(() {
              _isDragging = true;
              _dragValue = (details.localPosition.dx / box.size.width).clamp(0.0, 1.0);
            });
          },
          onHorizontalDragUpdate: (details) {
            final box = context.findRenderObject() as RenderBox?;
            if (box == null) return;
            setState(() {
              _dragValue = (details.localPosition.dx / box.size.width).clamp(0.0, 1.0);
            });
          },
          onHorizontalDragEnd: (details) async {
            final targetMs = (_dragValue * totalMs).toInt();
            await widget.controller.seekTo(Duration(milliseconds: targetMs));
            setState(() {
              _isDragging = false;
            });
          },
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    // 轨道背景
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      height: _isDragging ? 6.0 : 2.5,
                      width: constraints.maxWidth,
                      decoration: BoxDecoration(color: AppColors.surface.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    // 已播放进度
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      height: _isDragging ? 6.0 : 2.5,
                      width: constraints.maxWidth * displayProgress,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    // 拖动手柄指示圆点
                    if (_isDragging)
                      Positioned(
                        left: (constraints.maxWidth * displayProgress) - 7,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(color: AppColors.surface,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.textHint,
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// 🌟 7. 独立的视频社交互动覆盖层
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
            _likesCount =
                int.tryParse(data['likes_count']?.toString() ?? '0') ??
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
      Fluttertoast.showToast(msg: "video_like_login".tr);
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
      'video_share_text'.trParams({'caption': caption, 'url': videoUrl}),
      subject: 'video_share_subject'.tr,
    );
  }

  @override
  Widget build(BuildContext context) {
    final String caption = widget.videoMap['caption']?.toString() ?? '';
    final authorMap = widget.author ?? {};
    final String authorName = authorMap['nickname']?.toString() ??
        widget.videoMap['author_nickname']?.toString() ??
        'video_author_default'.tr;
    final String authorAvatar = authorMap['avatar']?.toString() ??
        widget.videoMap['author_avatar']?.toString() ??
        '';
    final String authorId = authorMap['id']?.toString() ??
        widget.videoMap['author_id']?.toString() ??
        '';

    return Positioned.fill(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
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
                          'video_index_in_post'.trParams({'index': (widget.currentIndex + 1).toString(), 'total': widget.totalVideosInPost.toString()}),
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
                    child: Column(
                      children: [
                        const HugeIcon(
                          icon: HugeIcons.strokeRoundedShare01,
                          color: Colors.white,
                          size: 26.0,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'video_share_btn'.tr,
                          style: const TextStyle(
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

/// 🌟 8. 独立视频评论二级回复抽屉
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
  String _hint = 'video_comment_hint'.tr;

  static Color get _primaryTeal => AppColors.primary;

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
      Fluttertoast.showToast(msg: "video_comment_login".tr);
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
          _hint = 'video_comment_hint'.tr;
        });
        _loadVideoComments();
      }
    } catch (e) {
      Fluttertoast.showToast(msg: "video_comment_failed".trParams({"error": e.toString()}));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: BoxDecoration(color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.surfaceAlt)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'video_discussion'.trParams({'count': _comments.length.toString()}),
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
                ? Center(
                child: CircularProgressIndicator(
                    color: _primaryTeal, strokeWidth: 2))
                : _comments.isEmpty
                ? Center(
              child: Text('video_no_discussion'.tr,
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
            )
                : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _comments.length,
              separatorBuilder: (_, __) => Divider(
                  height: 16, color: AppColors.background),
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
                                author['nickname'] ?? 'video_author_fallback'.tr,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                c['content'] ?? '',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textPrimary),
                              ),
                              const SizedBox(height: 4),
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _replyParentId = c['id'];
                                    _replyToUserId = author['id'];
                                    _hint = 'video_reply_hint'.trParams({'name': author['nickname']});
                                  });
                                },
                                child: Text('video_reply'.tr,
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
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textPrimary),
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
            decoration: BoxDecoration(color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.surfaceAlt)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TextField(
                      controller: _inputC,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: _hint,
                        hintStyle: TextStyle(
                            color: AppColors.textHint, fontSize: 12),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: HugeIcon(
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
