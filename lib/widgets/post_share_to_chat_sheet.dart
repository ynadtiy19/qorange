// lib/views/post_detail/widgets/post_share_to_chat_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:qorange/theme.dart';

import '../../../network/http_client.dart';

class PostShareToChatSheet extends StatefulWidget {
  final String postId;
  final String postTitle;
  final String postThumbnail;
  final String postCategory;

  const PostShareToChatSheet({
    super.key,
    required this.postId,
    required this.postTitle,
    required this.postThumbnail,
    required this.postCategory,
  });

  @override
  State<PostShareToChatSheet> createState() => _PostShareToChatSheetState();
}

class _PostShareToChatSheetState extends State<PostShareToChatSheet> {
  static Color get _primaryTeal => AppColors.primary;

  final List<Map<String, dynamic>> _contacts = [];
  bool _isLoading = true;
  String _searchKeyword = '';

  @override
  void initState() {
    super.initState();
    _fetchContacts();
  }

  Future<void> _fetchContacts() async {
    setState(() => _isLoading = true);
    try {
      final res = await HttpClient.instance.get<List<dynamic>>(
        '/api-im/contacts',
        queryParameters: {
          if (_searchKeyword.isNotEmpty) 'search': _searchKeyword,
        },
      );

      if (res.datas != null) {
        setState(() {
          _contacts.clear();
          _contacts.addAll(res.datas!.map((e) => Map<String, dynamic>.from(e as Map)));
        });
      }
    } catch (e) {
      debugPrint("🔴 [ShareToChat] 获取通讯录失败: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// 发送文章推荐卡片给目标用户
  Future<void> _sendPostToUser(String targetUserId, String targetNickname) async {
    HapticFeedback.mediumImpact();
    try {
      Fluttertoast.showToast(msg: 'share_sending'.trParams({'name': targetNickname}));

      final res = await HttpClient.instance.post<Map<String, dynamic>>(
        '/api-im/send',
        data: {
          'recipient_id': targetUserId,
          'msg_type': 'post_card',
          'payload': {
            'post_id': widget.postId,
            'title': widget.postTitle,
            'thumbnail': widget.postThumbnail,
            'category': widget.postCategory,
          },
        },
      );

      if (res.respCode == 0) {
        Get.back();
        Fluttertoast.showToast(msg: 'share_success'.trParams({'name': targetNickname}));
      } else {
        Fluttertoast.showToast(msg: res.respMsg);
      }
    } catch (e) {
      Fluttertoast.showToast(msg: 'share_failed'.tr);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: BoxDecoration(color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // 1. 顶部把手与标题
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _primaryTeal.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.send_rounded, color: _primaryTeal, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'share_to_dm_title'.tr,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                    ),
                  ],
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: AppColors.textSecondary, size: 22),
                  onPressed: () => Get.back(),
                ),
              ],
            ),
          ),

          // 2. 当前分享文章迷你卡片预览
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              children: [
                if (widget.postThumbnail.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(widget.postThumbnail, width: 44, height: 44, fit: BoxFit.cover),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.postTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
          ),

          // 3. 搜索栏
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(16),
              ),
              child: TextField(
                onChanged: (val) {
                  _searchKeyword = val.trim();
                  _fetchContacts();
                },
                decoration: InputDecoration(
                  icon: Icon(Icons.search_rounded, size: 18, color: AppColors.textHint),
                  hintText: 'share_search_hint'.tr,
                  hintStyle: TextStyle(fontSize: 13, color: AppColors.textHint),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),

          Divider(height: 1, color: AppColors.surfaceAlt),

          // 4. 好友列表
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: _primaryTeal, strokeWidth: 2))
                : _contacts.isEmpty
                ? Center(
              child: Text('share_no_users'.tr, style: TextStyle(fontSize: 13, color: AppColors.textHint)),
            )
                : ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              itemCount: _contacts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final user = _contacts[index];
                final userId = user['user_id']?.toString() ?? '';
                final nickname = user['nickname']?.toString() ?? 'user'.tr;
                final avatar = user['avatar']?.toString() ?? '';

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _sendPostToUser(userId, nickname),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.surfaceAlt),
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.network(
                              avatar.isNotEmpty ? avatar : 'https://api.dicebear.com/7.x/micah/png?seed=${nickname.hashCode}',
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(nickname, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                                Text('@${user['username'] ?? ''}', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: _primaryTeal.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('im_send_btn'.tr, style: const TextStyle(color: _primaryTeal, fontSize: 12, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms).slideY(begin: 0.1, end: 0);
  }
}