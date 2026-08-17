// lib/views/im/im_chat_view.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../controllers/im_chat_controller.dart';
import '../../models/im_message_model.dart';
import '../../user_controller.dart';
import '../../widgets/im_post_picker_bottom_sheet.dart';
import '../../widgets/pinterest_gallery_picker_sheet.dart';
import '../post_detail/post_detail_view.dart';
import '../profile/profile_view.dart';

class ImChatView extends StatefulWidget {
  final String conversationId;
  final String partnerId;
  final String partnerNickname;
  final String partnerAvatar;
  final String initialRelationshipStatus;

  const ImChatView({
    super.key,
    required this.conversationId,
    required this.partnerId,
    required this.partnerNickname,
    required this.partnerAvatar,
    this.initialRelationshipStatus = 'friend',
  });

  @override
  State<ImChatView> createState() => _ImChatViewState();
}

class _ImChatViewState extends State<ImChatView> {
  late ImChatController _controller;
  Worker? _userWorker;

  // 全局语音播放器管理
  final AudioPlayer _audioPlayer = AudioPlayer();
  String _currentlyPlayingUrl = '';
  bool _isPlayingAudio = false;

  static const Color _primaryTeal = Color.fromRGBO(44, 123, 109, 1.0);
  static const Color _goldAccent = Color(0xFFD97706);
  static const Color _bgSlate = Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    // 🌟 核心保护：如果已有实例直接复用，防止重复覆盖注册
    if (Get.isRegistered<ImChatController>(tag: widget.conversationId)) {
      _controller = Get.find<ImChatController>(tag: widget.conversationId);
    } else {
      _controller = Get.put(
        ImChatController(
          conversationId: widget.conversationId,
          partnerId: widget.partnerId,
          partnerNickname: widget.partnerNickname,
        ),
        tag: widget.conversationId,
      );
    }
    _controller.relationshipStatus.value = widget.initialRelationshipStatus;

    // 2. 监听账号状态
    _userWorker = ever(UserController.to.user, (user) {
      if (mounted) {
        if (UserController.to.isLoggedIn) {
          _controller.fetchHistoryMessages(refresh: true);
        } else {
          _controller.messages.clear();
        }
      }
    });

    // 监听音频播放状态
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlayingAudio = state == PlayerState.playing;
        });
      }
    });
  }

  @override
  void dispose() {
    _userWorker?.dispose();
    _audioPlayer.dispose();
    Get.delete<ImChatController>(tag: widget.conversationId);
    super.dispose();
  }

  /// 🌟 播放/暂停远程音频
  void _togglePlayAudio(String audioUrl) async {
    if (audioUrl.isEmpty) return;
    HapticFeedback.lightImpact();

    if (_currentlyPlayingUrl == audioUrl && _isPlayingAudio) {
      await _audioPlayer.pause();
    } else {
      _currentlyPlayingUrl = audioUrl;
      await _audioPlayer.stop();
      await _audioPlayer.play(UrlSource(audioUrl));
    }
  }

  // /// 🌟 生成 Cloudinary 专属声波波形 PNG 直链
  // String _getCloudinaryWaveformUrl(String audioUrl, {bool isMe = false}) {
  //   if (!audioUrl.contains('cloudinary.com')) return '';
  //   // 将 .m4a / .mp3 / .aac 替换为 .png
  //   final pngUrl = audioUrl.replaceAll(RegExp(r'\.(m4a|mp3|aac|wav|ogg)$', caseSensitive: false), '.png');
  //   // 根据己方/对方自动设定声波柱颜色：己方白声波，对方青橙绿声波
  //   final colorParam = isMe ? 'co_rgb:ffffff' : 'co_rgb:2C7B6D';
  //   if (pngUrl.contains('/upload/')) {
  //     return pngUrl.replaceFirst('/upload/', '/upload/w_140,h_28,c_fill,b_transparent,$colorParam/');
  //   }
  //   return pngUrl;
  // }


  /// 🌟 修复并标准化 Cloudinary 声波波形 PNG 生成规则
  String _getCloudinaryWaveformUrl(String audioUrl, {bool isMe = false}) {
    if (!audioUrl.contains('cloudinary.com')) return '';

    // 1. 强制将路径校准为 /video/upload/ 确保 Cloudinary 启用音频分析器
    String normalizedUrl = audioUrl;
    if (normalizedUrl.contains('/image/upload/')) {
      normalizedUrl = normalizedUrl.replaceFirst('/image/upload/', '/video/upload/');
    } else if (normalizedUrl.contains('/raw/upload/')) {
      normalizedUrl = normalizedUrl.replaceFirst('/raw/upload/', '/video/upload/');
    }

    // 2. 设定声波颜色：己方为纯白，对方为青橙品牌绿 (#2C7B6D)
    final colorHex = isMe ? 'ffffff' : '2c7b6d';

    // 3. 注入标准 Cloudinary 波形切片参数
    final waveformParams = 'fl_waveform,co_rgb:$colorHex,b_transparent,w_240,h_48,c_fit';

    return normalizedUrl
        .replaceFirst(
      '/upload/',
      '/upload/$waveformParams/',
    )
        .replaceAll(
      RegExp(r'\.(m4a|mp3|aac|wav|ogg|flac)$', caseSensitive: false),
      '.png',
    );
  }

  @override
  Widget build(BuildContext context) {
    final myId = UserController.to.user.value?.id ?? '';

    return Scaffold(
      backgroundColor: _bgSlate,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Color(0xFF1E293B)),
          onPressed: () => Get.back(),
        ),
        // 🌟 核心升级：顶部头像与昵称防溢出 + 点击直接跳转至该用户/创作者主页
        title: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            HapticFeedback.lightImpact();
            // 无论对方是创作者还是普通用户，点击均直接进入主页
            Get.to(
                  () => ProfileView(profileId: widget.partnerId),
              transition: Transition.cupertino,
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 2.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    widget.partnerAvatar,
                    width: 34,
                    height: 34,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 34,
                      height: 34,
                      color: const Color(0xFFE2E8F0),
                      child: const Icon(Icons.person, size: 18, color: Color(0xFF94A3B8)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // 🌟 使用 Flexible + maxLines: 1 + ellipsis 彻底杜绝超长昵称溢出报错
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.partnerNickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis, // 🌟 标题防溢出截断
                        style: const TextStyle(color: Color(0xFF0F172A), fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      Obx(() => Text(
                        _controller.relationshipStatus.value == 'stranger_pending'
                            ? '陌生人消息请求'
                            : (_controller.relationshipStatus.value == 'blocked' ? '已拉黑' : '在线'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: _controller.relationshipStatus.value == 'stranger_pending'
                              ? _goldAccent
                              : (_controller.relationshipStatus.value == 'blocked' ? const Color(0xFFEF4444) : _primaryTeal),
                          fontWeight: FontWeight.w600,
                        ),
                      )),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const HugeIcon(icon: HugeIcons.strokeRoundedImage01, color: Color(0xFF64748B), size: 20),
            tooltip: '更换聊天壁纸',
            onPressed: () => _showBackgroundPickerSheet(context),
          ),
          IconButton(
            icon: const HugeIcon(icon: HugeIcons.strokeRoundedMoreHorizontal, color: Color(0xFF64748B), size: 22),
            onPressed: () => _showMoreOptionsModal(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: [
          // 1. 自定义壁纸背景层
          Positioned.fill(
            child: Obx(() {
              if (_controller.customBgPath.value.isNotEmpty) {
                return Image.file(File(_controller.customBgPath.value), fit: BoxFit.cover);
              }
              if (_controller.customBgUrl.value.isNotEmpty) {
                return Image.network(_controller.customBgUrl.value, fit: BoxFit.cover);
              }
              return Container(color: _bgSlate);
            }),
          ),

          // 轻微半透明蒙层
          Obx(() {
            final hasBg = _controller.customBgPath.value.isNotEmpty || _controller.customBgUrl.value.isNotEmpty;
            if (!hasBg) return const SizedBox.shrink();
            return Positioned.fill(
              child: Container(color: Colors.white.withOpacity(0.4)),
            );
          }),

          // 2. 主内容区
          Column(
            children: [
              // 陌生人审核提示横幅
              Obx(() {
                if (_controller.relationshipStatus.value == 'stranger_pending') {
                  return _buildStrangerBanner();
                }
                return const SizedBox.shrink();
              }),

              // 消息气泡列表 (reverse: true 架构)
              Expanded(
                child: Stack(
                  children: [
                    Obx(() {
                      if (_controller.isLoadingHistory.value && _controller.messages.isEmpty) {
                        return const Center(child: CircularProgressIndicator(color: _primaryTeal, strokeWidth: 2));
                      }

                      return ListView.builder(
                        controller: _controller.scrollController,
                        reverse: true, // index 0 为最新消息
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        itemCount: _controller.messages.length,
                        itemBuilder: (context, index) {
                          final msg = _controller.messages[index];
                          final bool isMe = msg.senderId == myId;
                          return _buildMessageBubbleItem(context, msg, isMe);
                        },
                      );
                    }),

                    // 悬浮回底按钮 / 新消息动态胶囊
                    _buildFloatingScrollDownButton(),
                  ],
                ),
              ),

              // 底部自适应多行输入栏
              _buildInputBar(context),

              // 展开的多功能操作盘
              Obx(() {
                if (!_controller.isAttachmentOpen.value) return const SizedBox.shrink();
                return _buildAttachmentDrawer(context);
              }),
            ],
          ),
        ],
      ),
    );
  }

  /// 自适应返回底部/新消息动态悬浮胶囊
  Widget _buildFloatingScrollDownButton() {
    return Positioned(
      right: 16,
      bottom: 16,
      child: Obx(() {
        final bool show = _controller.showScrollDownBtn.value;
        final int newCount = _controller.newMessagesWhileBrowsingCount.value;

        return AnimatedOpacity(
          opacity: show ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: IgnorePointer(
            ignoring: !show,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  _controller.scrollToBottom();
                },
                borderRadius: BorderRadius.circular(24),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  padding: EdgeInsets.symmetric(horizontal: newCount > 0 ? 12 : 10, vertical: 9),
                  decoration: BoxDecoration(
                    color: newCount > 0 ? _goldAccent : Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.12),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (newCount > 0) ...[
                        Text(
                          '$newCount 条新消息',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: newCount > 0 ? Colors.white : _primaryTeal,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  /// 🌟 严格区分发信者与收信者的陌生人横幅
  Widget _buildStrangerBanner() {
    final bool isMeSender = _controller.isLastSenderMe;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFFFFFBEB),
        border: Border(bottom: BorderSide(color: Color(0xFFFDE68A))),
      ),
      child: Row(
        children: [
          Icon(
            isMeSender ? Icons.hourglass_top_rounded : Icons.shield_outlined,
            color: _goldAccent,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isMeSender
                  ? '已发送打招呼消息，等待对方回复后解锁畅聊'
                  : '对方为未互关陌生人，发来 1 条打招呼私信',
              style: const TextStyle(fontSize: 12, color: Color(0xFF92400E), fontWeight: FontWeight.w600),
            ),
          ),

          // 🌟 核心修复：只有接收方（对方给我发）才显示【同意沟通】按钮！发起方绝对不显示！
          if (!isMeSender)
            TextButton(
              onPressed: () => _controller.acceptStrangerRequest(),
              style: TextButton.styleFrom(
                backgroundColor: _primaryTeal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('同意沟通', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }

  /// 包含长按撤回/复制交互的气泡包装项
  Widget _buildMessageBubbleItem(BuildContext context, ImMessageModel msg, bool isMe) {
    return GestureDetector(
      onLongPress: () => _showMessageContextMenu(context, msg, isMe),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.76),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: isMe ? _primaryTeal : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMe ? 18 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 18),
                ),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2)),
                ],
              ),
              child: _buildBubbleContent(context, msg, isMe),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBubbleContent(BuildContext context, ImMessageModel msg, bool isMe) {
    final textColor = isMe ? Colors.white : const Color(0xFF1E293B);

    if (msg.isRevoked) {
      return const Text(
        '此消息已被撤回',
        style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: Color(0xFF94A3B8)),
      );
    }

    // 1. 文本消息
    if (msg.msgType == 'text') {
      return Text(
        msg.payload['text']?.toString() ?? '',
        style: TextStyle(fontSize: 14.5, height: 1.5, color: textColor, fontWeight: FontWeight.w500),
      );
    }

    // 2. 图片消息 (点击打开手势缩放查看器)
    else if (msg.msgType == 'image') {
      final imgUrl = msg.payload['url']?.toString() ?? '';
      return InkWell(
        onTap: () => _openInteractiveImageViewer(context, imgUrl),
        borderRadius: BorderRadius.circular(12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            imgUrl,
            fit: BoxFit.cover,
            loadingBuilder: (c, w, p) => p == null
                ? w
                : const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          ),
        ),
      );
    }

    // 3. 🌟 语音消息气泡 (真实播放 + 动态律动声波 + Cloudinary 波形图渲染)
    else if (msg.msgType == 'voice') {
      final String audioUrl = msg.payload['url']?.toString() ?? '';
      final int duration = int.tryParse(msg.payload['duration_sec']?.toString() ?? '0') ?? 0;
      final bool isCurrentActive = _currentlyPlayingUrl == audioUrl && _isPlayingAudio;
      final String waveformPngUrl = _getCloudinaryWaveformUrl(audioUrl, isMe: isMe);

      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _togglePlayAudio(audioUrl),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 播放/暂停圆形按钮 (带微触感与背景)
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: isMe ? Colors.white.withOpacity(0.22) : _primaryTeal.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isCurrentActive ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: textColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),

                // 🌟 声波展示区：双重渲染（网络声波 PNG 优先，本地跳动动画兜底）
                SizedBox(
                  width: 120,
                  height: 28,
                  child: waveformPngUrl.isNotEmpty
                      ? Image.network(
                    waveformPngUrl,
                    fit: BoxFit.fill,
                    loadingBuilder: (c, child, progress) =>
                    progress == null ? child : _buildDynamicWaveform(textColor, isCurrentActive),
                    errorBuilder: (_, __, ___) => _buildDynamicWaveform(textColor, isCurrentActive),
                  )
                      : _buildDynamicWaveform(textColor, isCurrentActive),
                ),

                const SizedBox(width: 10),

                // 时长显示
                Text(
                  '$duration"',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 3. 🌟 青橙币直接转账 (修复长文本自动换行扩展，杜绝溢出)
    else if (msg.msgType == 'token_transfer') {
      final double tokens = double.tryParse(msg.payload['tokens']?.toString() ?? '0') ?? 0.0;
      final String remark = msg.payload['remark']?.toString() ?? '青橙币转账';

      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMe ? Colors.white.withOpacity(0.15) : const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFDE68A).withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 左侧转账币图标
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(color: Color(0xFFF59E0B), shape: BoxShape.circle),
              child: const Icon(Icons.monetization_on_rounded, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),

            // 🌟 核心修复：使用 Expanded 限制右侧区域宽度，使多行备注自适应平滑换行
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '¥ ${tokens.toStringAsFixed(1)} 青橙币',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: isMe ? Colors.white : const Color(0xFFB45309),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    remark,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4, // 增加舒适阅读行高
                      color: isMe ? Colors.white.withOpacity(0.85) : const Color(0xFF92400E),
                    ),
                    softWrap: true, // 允许自由自动换行
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // 4. 🌟 青橙币请款收款单 (增强防溢出排版与高质感账单卡片设计)
    else if (msg.msgType == 'token_request') {
      final double tokens = double.tryParse(msg.payload['tokens']?.toString() ?? '0') ?? 0.0;
      final String remark = msg.payload['remark']?.toString() ?? '款项结算';
      final String status = msg.payload['status']?.toString() ?? 'pending';
      final bool isPending = status == 'pending';
      final bool isPaid = status == 'paid';

      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isMe ? Colors.white.withOpacity(0.15) : const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isMe
                ? Colors.white.withOpacity(0.2)
                : const Color(0xFFFDE68A).withOpacity(0.8),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. 头部标题栏与状态徽标
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.receipt_long_rounded,
                      color: isMe ? Colors.white : const Color(0xFFD97706),
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '青橙币收款单',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: isMe ? Colors.white : const Color(0xFFB45309),
                      ),
                    ),
                  ],
                ),
                // 右上角状态小胶囊
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isPaid
                        ? const Color(0xFF10B981).withOpacity(0.15)
                        : (isPending
                        ? const Color(0xFFF59E0B).withOpacity(0.15)
                        : Colors.grey.shade200),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isPaid ? '已支付' : (isPending ? '待付款' : '已拒绝'),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: isPaid
                          ? (isMe ? Colors.white : const Color(0xFF059669))
                          : (isPending
                          ? (isMe ? Colors.white : const Color(0xFFD97706))
                          : Colors.grey.shade600),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // 2. 大字号请款金额
            Text(
              '¥ ${tokens.toStringAsFixed(1)} 青橙币',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: isMe ? Colors.white : const Color(0xFF92400E),
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),

            // 3. 请款事由说明框 (长文本自动自适应换行，彻底杜绝溢出)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: isMe ? Colors.black.withOpacity(0.08) : Colors.white.withOpacity(0.8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '事由: $remark',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: isMe ? Colors.white.withOpacity(0.9) : const Color(0xFF78350F),
                  fontWeight: FontWeight.w500,
                ),
                softWrap: true, // 🌟 允许自适应折行
              ),
            ),
            const SizedBox(height: 12),

            // 4. 底部操作按钮与状态描述
            if (!isMe && isPending)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    _controller.payTokenRequest(msg.messageId);
                  },
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                  label: const Text('立即支付此请款', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              )
            else
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  isPaid
                      ? '✓ 交易已完成，青橙币已到账'
                      : (status == 'rejected' ? '✕ 付款人已拒绝此收款' : '⏳ 等待对方确认并支付'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isPaid
                        ? (isMe ? Colors.white70 : const Color(0xFF059669))
                        : (isMe ? Colors.white60 : Colors.grey.shade600),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    // 6. 🌟 全新设计：杂志级高质感文章推荐气泡卡片
    else if (msg.msgType == 'post_card') {
      final title = msg.payload['title']?.toString() ?? '文章推荐';
      final postId = msg.payload['post_id']?.toString() ?? '';
      final thumbnail = msg.payload['thumbnail']?.toString() ?? '';
      final category = (msg.payload['category']?.toString() ?? '专栏').toUpperCase();

      return InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          Get.to(() => PostDetailView(postId: postId));
        },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 230,
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: isMe ? Colors.white.withOpacity(0.14) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isMe ? Colors.white.withOpacity(0.25) : const Color(0xFFE2E8F0),
              width: 0.8,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. 顶部：分类标签与推荐角标
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: isMe ? Colors.white.withOpacity(0.2) : _primaryTeal.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      category,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: isMe ? Colors.white : _primaryTeal,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.auto_stories_rounded,
                    size: 14,
                    color: isMe ? Colors.white60 : Colors.grey.shade400,
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // 2. 中间：标题 + 封面图左右排版
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 文章标题 (最多 2 行截断)
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                        color: textColor,
                      ),
                    ),
                  ),

                  // 封面缩略小图
                  if (thumbnail.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        thumbnail,
                        width: 46,
                        height: 46,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),

              // 3. 底部：阅读全文引导条
              Container(
                padding: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: isMe ? Colors.white.withOpacity(0.12) : const Color(0xFFE2E8F0),
                      width: 0.8,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '阅读全文',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isMe ? Colors.white70 : const Color(0xFF64748B),
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 10,
                      color: isMe ? Colors.white70 : const Color(0xFF64748B),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Text(msg.payload['text']?.toString() ?? '[消息]', style: TextStyle(color: textColor));
  }



  /// 🌟 动态律动声波条组件（未播放时静态优雅，播放时模拟声波跳跃）
  Widget _buildDynamicWaveform(Color color, bool isPlaying) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(14, (i) {
        final double staticHeight = (8 + (i % 5) * 4).toDouble();
        return AnimatedContainer(
          duration: Duration(milliseconds: isPlaying ? (200 + (i % 4) * 80) : 300),
          width: 2.5,
          height: isPlaying ? (6 + (i * 3) % 18).toDouble() : staticHeight,
          decoration: BoxDecoration(
            color: color.withOpacity(isPlaying ? 0.9 : 0.65),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
  /// 🌟 极简高颜值长按消息上下文操作面板
  void _showMessageContextMenu(BuildContext context, ImMessageModel msg, bool isMe) {
    HapticFeedback.mediumImpact();

    final int diffInSeconds = DateTime.now().difference(msg.createdAt).inSeconds.abs();
    final bool canRevoke = isMe && !msg.isRevoked && diffInSeconds <= 120;
    final int remainSec = 120 - diffInSeconds;

    String previewText = '[消息]';
    if (msg.msgType == 'text') previewText = msg.payload['text']?.toString() ?? '';
    if (msg.msgType == 'image') previewText = '[图片]';
    if (msg.msgType == 'voice') previewText = '[语音留言]';
    if (msg.msgType == 'post_card') previewText = '[文章分享] ${msg.payload['title'] ?? ''}';

    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 20,
              offset: Offset(0, -4),
            )
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 顶部小把手
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // 消息快照引用卡片
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 16,
                    decoration: BoxDecoration(
                      color: _primaryTeal,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      previewText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 操作选项列表
            Row(
              children: [
                // 1. 复制文本 (仅文字消息展现)
                if (msg.msgType == 'text' && !msg.isRevoked)
                  Expanded(
                    child: _buildContextMenuButton(
                      icon: Icons.copy_rounded,
                      label: '复制文本',
                      color: const Color(0xFF1E293B),
                      bgColor: const Color(0xFFF1F5F9),
                      onTap: () {
                        Get.back();
                        Clipboard.setData(ClipboardData(text: msg.payload['text']?.toString() ?? ''));
                        Fluttertoast.showToast(msg: '已复制到剪贴板');
                      },
                    ),
                  ),

                if (msg.msgType == 'text' && !msg.isRevoked && canRevoke)
                  const SizedBox(width: 12),

                // 2. 撤回按钮 (2分钟内高亮)
                if (canRevoke)
                  Expanded(
                    child: _buildContextMenuButton(
                      icon: Icons.undo_rounded,
                      label: '撤回 (${remainSec}s)',
                      color: const Color(0xFFEF4444),
                      bgColor: const Color(0xFFFEF2F2),
                      onTap: () {
                        Get.back();
                        _controller.revokeMessage(msg.messageId);
                      },
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContextMenuButton({
    required IconData icon,
    required String label,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
  /// 打开全功能手势缩放图片预览页
  void _openInteractiveImageViewer(BuildContext context, String imageUrl) {
    HapticFeedback.lightImpact();
    Get.to(
          () => _InteractiveImagePreviewPage(
        imageUrl: imageUrl,
        onSave: () => _controller.saveImageToDevice(imageUrl),
      ),
      transition: Transition.fadeIn,
      fullscreenDialog: true,
    );
  }

  /// 底部自适应多行输入工具栏 (1~5 行丝滑撑大)
  Widget _buildInputBar(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 10,
        right: 14,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            icon: Obx(() => AnimatedRotation(
              turns: _controller.isAttachmentOpen.value ? 0.125 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: HugeIcon(
                icon: HugeIcons.strokeRoundedAddCircle,
                color: _controller.isAttachmentOpen.value ? _primaryTeal : const Color(0xFF64748B),
                size: 24,
              ),
            )),
            onPressed: () {
              HapticFeedback.lightImpact();
              FocusScope.of(context).unfocus();
              _controller.isAttachmentOpen.toggle();
            },
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 2),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(20),
              ),
              child: TextField(
                controller: _controller.textEditingController,
                minLines: 1,
                maxLines: 5,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                onTap: () {
                  if (_controller.isAttachmentOpen.value) {
                    _controller.isAttachmentOpen.value = false;
                  }
                },
                decoration: const InputDecoration(
                  hintText: '输入消息，支持换行...',
                  hintStyle: TextStyle(fontSize: 14, color: Color(0xFF94A3B8)),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 4),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Material(
              color: _primaryTeal,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () {
                  HapticFeedback.lightImpact();
                  final text = _controller.textEditingController.text.trim();
                  if (text.isNotEmpty) {
                    _controller.sendMessage(msgType: 'text', payload: {'text': text});
                  }
                },
                child: const Padding(
                  padding: EdgeInsets.all(9),
                  child: Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 展开的多功能操作盘
  Widget _buildAttachmentDrawer(BuildContext context) {
    return Container(
      height: 220,
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: GridView.count(
        crossAxisCount: 4,
        mainAxisSpacing: 16,
        crossAxisSpacing: 12,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          // 1. 语音留言
          _buildActionItem(
            icon: HugeIcons.strokeRoundedMic01,
            label: '语音留言',
            color: const Color(0xFFEF4444),
            onTap: () {
              _controller.isAttachmentOpen.value = false;
              _showVoiceRecordDialog(context);
            },
          ),
          // 2. 拍照
          _buildActionItem(
            icon: HugeIcons.strokeRoundedCamera01,
            label: '拍照',
            color: const Color(0xFF3B82F6),
            onTap: () {
              _controller.isAttachmentOpen.value = false;
              _controller.pickAndSendImage(ImageSource.camera);
            },
          ),
          // 3. 相册图片
          _buildActionItem(
            icon: HugeIcons.strokeRoundedImage02,
            label: '相册图片',
            color: const Color(0xFF10B981),
            onTap: () {
              _controller.isAttachmentOpen.value = false;
              _controller.pickAndSendImage(ImageSource.gallery);
            },
          ),
          // 4. 发送青橙币
          _buildActionItem(
            icon: HugeIcons.strokeRoundedCoins01,
            label: '发送青橙币',
            color: const Color(0xFFF59E0B),
            onTap: () {
              _controller.isAttachmentOpen.value = false;
              _showTokenTransferDialog(context);
            },
          ),
          // 5. 发起收款
          _buildActionItem(
            icon: HugeIcons.strokeRoundedReceiptDollar,
            label: '发起收款',
            color: const Color(0xFF8B5CF6),
            onTap: () {
              _controller.isAttachmentOpen.value = false;
              _showTokenRequestDialog(context);
            },
          ),
          // 6. 更换壁纸
          _buildActionItem(
            icon: HugeIcons.strokeRoundedPaintBoard,
            label: '更换壁纸',
            color: _primaryTeal,
            onTap: () {
              _controller.isAttachmentOpen.value = false;
              _showBackgroundPickerSheet(context);
            },
          ),

          // 🌟 推荐文章按钮
          _buildActionItem(
            icon: HugeIcons.strokeRoundedNote01,
            label: '推荐文章',
            color: const Color(0xFF06B6D4),
            onTap: () {
              _controller.isAttachmentOpen.value = false;
              Get.bottomSheet(
                ImPostPickerBottomSheet(
                  onPostSelected: (post) {
                    _controller.sendPostCard(
                      postId: post['id'].toString(),
                      title: post['title']?.toString() ?? '文章推荐',
                      thumbnail: post['thumbnail']?.toString() ?? '',
                      category: post['category']?.toString() ?? 'general',
                    );
                  },
                ),
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
              );
            },
          ),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildActionItem({
    required dynamic icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: HugeIcon(icon: icon, color: color, size: 24),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
        ],
      ),
    );
  }

  /// 🌟 录音与实时波形采集弹窗
  void _showVoiceRecordDialog(BuildContext context) {
    Get.bottomSheet(
      _VoiceRecordBottomSheet(
        onVoiceRecorded: (audioBytes, durationSec) {
          _controller.sendVoiceMessage(audioBytes: audioBytes, durationSec: durationSec);
        },
      ),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  /// 弹出背景选择面板
  void _showBackgroundPickerSheet(BuildContext context) {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '设置此聊天的专属背景',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
            ),
            const SizedBox(height: 18),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: _primaryTeal),
              title: const Text('从手机本地相册选取', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () async {
                Get.back();
                final XFile? img = await ImagePicker().pickImage(source: ImageSource.gallery);
                if (img != null) _controller.setCustomBackground(filePath: img.path);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded, color: Color(0xFF3B82F6)),
              title: const Text('拍照设为背景', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () async {
                Get.back();
                final XFile? img = await ImagePicker().pickImage(source: ImageSource.camera);
                if (img != null) _controller.setCustomBackground(filePath: img.path);
              },
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF8B5CF6)),
              title: const Text('从 Pinterest 意境池精选壁纸', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('浏览并选用数据库已存储的高清大图', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
              onTap: () {
                Get.back();
                Get.bottomSheet(
                  PinterestGalleryPickerSheet(
                    onImageSelected: (url) {
                      _controller.setCustomBackground(networkUrl: url);
                    },
                  ),
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.refresh_rounded, color: Color(0xFFEF4444)),
              title: const Text('恢复默认浅色背景', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w600)),
              onTap: () {
                Get.back();
                _controller.setCustomBackground();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showTokenTransferDialog(BuildContext context) {
    final amountCtrl = TextEditingController();
    final remarkCtrl = TextEditingController();

    Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('转账青橙币给对方', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              TextField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: '青橙币数量', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: remarkCtrl,
                decoration: const InputDecoration(labelText: '备注 (如: 请喝咖啡)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  final tokens = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                  if (tokens > 0) {
                    Get.back();
                    _controller.sendTokenTransfer(tokens: tokens, remark: remarkCtrl.text.trim());
                  } else {
                    Fluttertoast.showToast(msg: '请输入有效数量');
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 44),
                ),
                child: const Text('确认转账', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTokenRequestDialog(BuildContext context) {
    final amountCtrl = TextEditingController();
    final remarkCtrl = TextEditingController();

    Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('发起青橙币收款单', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              TextField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: '请求支付数量', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: remarkCtrl,
                decoration: const InputDecoration(labelText: '请款事由 (如: 稿费结算)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  final tokens = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                  if (tokens > 0) {
                    Get.back();
                    _controller.sendTokenRequest(tokens: tokens, remark: remarkCtrl.text.trim());
                  } else {
                    Fluttertoast.showToast(msg: '请输入有效数量');
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 44),
                ),
                child: const Text('生成收款单', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMoreOptionsModal(BuildContext context) {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Obx(() {
              final bool isBlocked = _controller.isBlockedByMe.value || _controller.relationshipStatus.value == 'blocked';

              return ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                tileColor: isBlocked ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
                leading: Icon(
                  isBlocked ? Icons.check_circle_outline_rounded : Icons.block_flipped,
                  color: isBlocked ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                ),
                title: Text(
                  isBlocked ? '解除拉黑' : '拉黑此用户',
                  style: TextStyle(
                    color: isBlocked ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  isBlocked ? '解除后可恢复正常私信交流' : '拉黑后对方将无法向您发送任何私信',
                  style: TextStyle(
                    color: isBlocked ? const Color(0xFF059669) : const Color(0xFF991B1B),
                    fontSize: 11,
                  ),
                ),
                onTap: () {
                  Get.back();
                  if (isBlocked) {
                    _controller.unblockUser(); // 🌟 执行解除拉黑
                  } else {
                    _controller.blockUser();   // 🌟 执行拉黑
                  }
                },
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// 🌟 极简高颜值录音采集抽屉 (带脉冲声波与计时器)
class _VoiceRecordBottomSheet extends StatefulWidget {
  final Function(Uint8List audioBytes, int durationSec) onVoiceRecorded;

  const _VoiceRecordBottomSheet({required this.onVoiceRecorded});

  @override
  State<_VoiceRecordBottomSheet> createState() => _VoiceRecordBottomSheetState();
}

class _VoiceRecordBottomSheetState extends State<_VoiceRecordBottomSheet> {
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  int _recordDuration = 0;
  Timer? _timer;
  String? _recordedFilePath;

  static const Color _primaryTeal = Color.fromRGBO(44, 123, 109, 1.0);

  @override
  void initState() {
    super.initState();
    _startRecording();
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final Directory tempDir = await getTemporaryDirectory();
        _recordedFilePath = '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100),
          path: _recordedFilePath!,
        );

        HapticFeedback.mediumImpact();
        setState(() {
          _isRecording = true;
          _recordDuration = 0;
        });

        _timer = Timer.periodic(const Duration(seconds: 1), (t) {
          setState(() {
            _recordDuration++;
          });
        });
      }
    } catch (e) {
      Fluttertoast.showToast(msg: '无法开启麦克风录音: $e');
      Get.back();
    }
  }

  Future<void> _stopAndSend() async {
    _timer?.cancel();
    HapticFeedback.lightImpact();

    final path = await _audioRecorder.stop();
    setState(() {
      _isRecording = false;
    });

    if (path != null && _recordDuration >= 1) {
      final file = File(path);
      if (await file.exists()) {
        final Uint8List bytes = await file.readAsBytes();
        Get.back();
        widget.onVoiceRecorded(bytes, _recordDuration);
      }
    } else {
      Fluttertoast.showToast(msg: '录音时间太短');
      Get.back();
    }
  }

  Future<void> _cancelRecording() async {
    _timer?.cancel();
    await _audioRecorder.stop();
    HapticFeedback.lightImpact();
    if (_recordedFilePath != null) {
      final file = File(_recordedFilePath!);
      if (await file.exists()) await file.delete();
    }
    Get.back();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String minutes = (_recordDuration ~/ 60).toString().padLeft(2, '0');
    final String seconds = (_recordDuration % 60).toString().padLeft(2, '0');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('正在录制语音留言', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
          const SizedBox(height: 18),

          // 录音计时器
          Text(
            '$minutes:$seconds',
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: _primaryTeal, letterSpacing: 1),
          ),
          const SizedBox(height: 24),

          // 脉冲呼吸麦克风动效
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle),
                child: const Icon(Icons.mic_rounded, color: Colors.white, size: 30),
              ),
            ),
          ).animate(onPlay: (controller) => controller.repeat(reverse: true)).scale(begin: const Offset(1, 1), end: const Offset(1.15, 1.15), duration: 800.ms),

          const SizedBox(height: 32),

          // 操作按钮 (取消 / 发送)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton.icon(
                onPressed: _cancelRecording,
                icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8)),
                label: const Text('取消', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w600, fontSize: 14)),
              ),
              ElevatedButton.icon(
                onPressed: _stopAndSend,
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text('发送语音', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryTeal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 🌟 全屏沉浸式图片预览页 (支持双指缩放、双击缩放、手势拖拽退出与本地保存)
class _InteractiveImagePreviewPage extends StatefulWidget {
  final String imageUrl;
  final VoidCallback onSave;

  const _InteractiveImagePreviewPage({
    required this.imageUrl,
    required this.onSave,
  });

  @override
  State<_InteractiveImagePreviewPage> createState() => _InteractiveImagePreviewPageState();
}

class _InteractiveImagePreviewPageState extends State<_InteractiveImagePreviewPage> {
  final TransformationController _transformController = TransformationController();
  TapDownDetails? _doubleTapDetails;

  void _handleDoubleTap() {
    if (_transformController.value != Matrix4.identity()) {
      _transformController.value = Matrix4.identity();
    } else {
      final position = _doubleTapDetails?.localPosition ?? Offset.zero;
      _transformController.value = Matrix4.identity()
        ..translate(-position.dx * 1.5, -position.dy * 1.5)
        ..scale(2.5);
    }
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white, size: 24),
          onPressed: () => Get.back(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded, color: Colors.white, size: 24),
            tooltip: '保存到本地',
            onPressed: () {
              HapticFeedback.mediumImpact();
              widget.onSave();
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: GestureDetector(
        onDoubleTapDown: (details) => _doubleTapDetails = details,
        onDoubleTap: _handleDoubleTap,
        child: Center(
          child: InteractiveViewer(
            transformationController: _transformController,
            minScale: 0.8,
            maxScale: 4.0,
            child: Image.network(
              widget.imageUrl,
              fit: BoxFit.contain,
              loadingBuilder: (c, child, progress) {
                if (progress == null) return child;
                return const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2));
              },
            ),
          ),
        ),
      ),
    );
  }
}