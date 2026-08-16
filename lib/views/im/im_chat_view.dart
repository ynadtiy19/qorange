// lib/views/im/im_chat_view.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:image_picker/image_picker.dart';

import '../../controllers/im_chat_controller.dart';
import '../../models/im_message_model.dart';
import '../../user_controller.dart';
import '../../widgets/pinterest_gallery_picker_sheet.dart';
import '../post_detail/post_detail_view.dart';

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

  static const Color _primaryTeal = Color.fromRGBO(44, 123, 109, 1.0);
  static const Color _goldAccent = Color(0xFFD97706);
  static const Color _bgSlate = Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    // 1. 注入当前会话的独立控制器
    _controller = Get.put(
      ImChatController(
        conversationId: widget.conversationId,
        partnerId: widget.partnerId,
        partnerNickname: widget.partnerNickname,
      ),
      tag: widget.conversationId,
    );
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
  }

  @override
  void dispose() {
    _userWorker?.dispose();
    Get.delete<ImChatController>(tag: widget.conversationId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myId = UserController.to.user.value?.id ?? '';

    return Scaffold(
      backgroundColor: _bgSlate,
      resizeToAvoidBottomInset: true, // 🌟 确保物理键盘顶起时整体平滑位移
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Color(0xFF1E293B)),
          onPressed: () => Get.back(),
        ),
        title: Row(
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.partnerNickname,
                  style: const TextStyle(color: Color(0xFF0F172A), fontSize: 15, fontWeight: FontWeight.w700),
                ),
                Obx(() => Text(
                  _controller.relationshipStatus.value == 'stranger_pending'
                      ? '陌生人消息请求'
                      : (_controller.relationshipStatus.value == 'blocked' ? '已拉黑' : '在线'),
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
          ],
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
          // 🌟 1. 自定义壁纸背景层 (支持本地图片与网络高清图)
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

          // 轻微半透明蒙层（确保无论壁纸颜色多亮，文字气泡都清晰舒适）
          Obx(() {
            final hasBg = _controller.customBgPath.value.isNotEmpty || _controller.customBgUrl.value.isNotEmpty;
            if (!hasBg) return const SizedBox.shrink();
            return Positioned.fill(
              child: Container(color: Colors.white.withOpacity(0.4)),
            );
          }),

          // 🌟 2. 前台主内容区域
          Column(
            children: [
              // 陌生人审核提示悬浮横幅
              Obx(() {
                if (_controller.relationshipStatus.value == 'stranger_pending') {
                  return _buildStrangerBanner();
                }
                return const SizedBox.shrink();
              }),

              // 消息气泡列表
              Expanded(
                child: Obx(() {
                  if (_controller.isLoadingHistory.value && _controller.messages.isEmpty) {
                    return const Center(child: CircularProgressIndicator(color: _primaryTeal, strokeWidth: 2));
                  }

                  return ListView.builder(
                    controller: _controller.scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: _controller.messages.length,
                    itemBuilder: (context, index) {
                      final msg = _controller.messages[index];
                      final bool isMe = msg.senderId == myId;
                      return _buildMessageBubble(context, msg, isMe);
                    },
                  );
                }),
              ),

              // 底部自适应输入工具栏与拓展盘
              _buildInputBar(context),

              // 🌟 3. 展开的多功能操作盘（发图、发青橙币、收款、拍照等）
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

  /// 陌生人审核横幅
  Widget _buildStrangerBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFFFFFBEB),
        border: Border(bottom: BorderSide(color: Color(0xFFFDE68A))),
      ),
      child: Row(
        children: [
          const Icon(Icons.shield_outlined, color: _goldAccent, size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '对方为未互关陌生人，仅可发送 1 条打招呼私信',
              style: TextStyle(fontSize: 12, color: Color(0xFF92400E), fontWeight: FontWeight.w600),
            ),
          ),
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

  /// 多模态气泡构建器
  Widget _buildMessageBubble(BuildContext context, ImMessageModel msg, bool isMe) {
    return Padding(
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
            child: _buildBubbleContent(msg, isMe),
          ),
        ],
      ),
    );
  }

  Widget _buildBubbleContent(ImMessageModel msg, bool isMe) {
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

    // 2. 图片消息
    else if (msg.msgType == 'image') {
      final imgUrl = msg.payload['url']?.toString() ?? '';
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          imgUrl,
          fit: BoxFit.cover,
          loadingBuilder: (c, w, p) => p == null ? w : const SizedBox(height: 120, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
        ),
      );
    }

    // 3. 🌟 青橙币直接转账 (Token Transfer / 红包)
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
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(color: Color(0xFFF59E0B), shape: BoxShape.circle),
              child: const Icon(Icons.monetization_on_rounded, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('¥ ${tokens.toStringAsFixed(1)} 青橙币', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: isMe ? Colors.white : const Color(0xFFB45309))),
                const SizedBox(height: 2),
                Text(remark, style: TextStyle(fontSize: 12, color: isMe ? Colors.white70 : const Color(0xFF92400E))),
              ],
            ),
          ],
        ),
      );
    }

    // 4. 🌟 青橙币请款收款单 (Token Payment Request)
    else if (msg.msgType == 'token_request') {
      final double tokens = double.tryParse(msg.payload['tokens']?.toString() ?? '0') ?? 0.0;
      final String remark = msg.payload['remark']?.toString() ?? '请款单';
      final String status = msg.payload['status']?.toString() ?? 'pending';

      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMe ? Colors.white.withOpacity(0.15) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.receipt_long_rounded, color: isMe ? Colors.white70 : _primaryTeal, size: 18),
                const SizedBox(width: 6),
                Text('青橙币收款单', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: isMe ? Colors.white70 : _primaryTeal)),
              ],
            ),
            const SizedBox(height: 8),
            Text('$remark：需支付 ${tokens.toStringAsFixed(1)} 币', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textColor)),
            const SizedBox(height: 10),
            if (!isMe && status == 'pending')
              ElevatedButton(
                onPressed: () => _controller.payTokenRequest(msg.messageId),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('立即支付', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              )
            else
              Text(
                status == 'paid' ? '✓ 已完成支付' : (status == 'rejected' ? '✕ 已拒绝' : '等待对方支付'),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: status == 'paid' ? const Color(0xFF10B981) : Colors.grey),
              ),
          ],
        ),
      );
    }

    // 5. 文章推荐卡片
    else if (msg.msgType == 'post_card') {
      final title = msg.payload['title']?.toString() ?? '文章推荐';
      final postId = msg.payload['post_id']?.toString() ?? '';
      return InkWell(
        onTap: () => Get.to(() => PostDetailView(postId: postId)),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isMe ? Colors.white.withOpacity(0.15) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.article_rounded, size: 16, color: isMe ? Colors.white70 : _primaryTeal),
                  const SizedBox(width: 6),
                  Text('文章推荐', style: TextStyle(fontSize: 11, color: isMe ? Colors.white70 : _primaryTeal, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 6),
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: textColor)),
            ],
          ),
        ),
      );
    }

    return Text(msg.payload['text']?.toString() ?? '[消息]', style: TextStyle(color: textColor));
  }

  /// 🌟 底部自适应输入工具栏 (支持物理键盘回车 1~5 行撑大位移)
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
          // 左侧拓展盘开关按钮 (+)
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
              FocusScope.of(context).unfocus(); // 收起键盘展开面板
              _controller.isAttachmentOpen.toggle();
            },
          ),

          // 核心多行输入框 (1~5 行弹性高度撑大)
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
                maxLines: 5, // 🌟 物理键盘换行时，输入框优雅撑大最多 5 行
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

          // 发送按钮
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

  /// 🌟 展开的多功能操作盘组件
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
          _buildActionItem(
            icon: HugeIcons.strokeRoundedCamera01,
            label: '拍照',
            color: const Color(0xFF3B82F6),
            onTap: () {
              _controller.isAttachmentOpen.value = false;
              _controller.pickAndSendImage(ImageSource.camera);
            },
          ),
          _buildActionItem(
            icon: HugeIcons.strokeRoundedImage02,
            label: '相册图片',
            color: const Color(0xFF10B981),
            onTap: () {
              _controller.isAttachmentOpen.value = false;
              _controller.pickAndSendImage(ImageSource.gallery);
            },
          ),
          _buildActionItem(
            icon: HugeIcons.strokeRoundedCoins01,
            label: '发送青橙币',
            color: const Color(0xFFF59E0B),
            onTap: () {
              _controller.isAttachmentOpen.value = false;
              _showTokenTransferDialog(context);
            },
          ),
          _buildActionItem(
            icon: HugeIcons.strokeRoundedReceiptDollar,
            label: '发起收款',
            color: const Color(0xFF8B5CF6),
            onTap: () {
              _controller.isAttachmentOpen.value = false;
              _showTokenRequestDialog(context);
            },
          ),
          _buildActionItem(
            icon: HugeIcons.strokeRoundedPaintBoard,
            label: '更换壁纸',
            color: _primaryTeal,
            onTap: () {
              _controller.isAttachmentOpen.value = false;
              _showBackgroundPickerSheet(context);
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

  /// 🌟 弹出背景选择面板（支持拍照、相册、从数据库 Pinterest 意境池精选、恢复默认）
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
            // 🌟 核心升级：拉起 Pinterest 意境图库资产挑选大厅
            ListTile(
              leading: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF8B5CF6)),
              title: const Text('从 Pinterest 意境池精选壁纸', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('浏览并选用数据库已存储的高清大图', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
              onTap: () {
                Get.back(); // 关闭当前简易菜单
                // 拉起完整的双列瀑布流壁纸抽屉
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

  /// 弹出发送青橙币对话框
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

  /// 弹出请求青橙币收款对话框
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
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.block_flipped, color: Color(0xFFEF4444)),
              title: const Text('拉黑此用户', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w600)),
              onTap: () {
                Get.back();
                _controller.blockUser();
              },
            ),
          ],
        ),
      ),
    );
  }
}