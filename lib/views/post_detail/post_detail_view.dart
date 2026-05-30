import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill/quill_delta.dart' as quill;
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../network/api_exception.dart';
import '../../network/http_client.dart';
import '../../user_controller.dart';
import '../../widgets/quill_custom_divider.dart';
import '../../services/quill_translation_service.dart';
import '../profile/profile_view.dart';

class PostDetailView extends StatefulWidget {
  final String postId;
  const PostDetailView({super.key, required this.postId});

  @override
  State<PostDetailView> createState() => _PostDetailViewState();
}

class _PostDetailViewState extends State<PostDetailView> with TickerProviderStateMixin {
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();
  quill.QuillController? _quillController;

  Map<String, dynamic>? _post;
  bool _isLoadingPost = true;
  List<CommentModel> _comments = [];
  bool _isLoadingComments = true;

  bool isLiked = false;
  int likeCount = 0;
  bool isCollected = false;

  // 翻译响应状态
  bool isTranslating = false;
  bool isShowingTranslation = false;
  quill.Delta? _originalDelta;

  bool _isSendingComment = false;
  String? _selectedOptionId;

  // 级联回复上下文状态
  String? _replyParentCommentId; // 目标顶级父评论
  String? _replyToUserId;        // 目标回复用户ID
  String? _replyToNickname;      // 目标回复用户昵称

  final Map<String, String> _supportedLanguages = {
    "en": "英语",
    "zh-CN": "简体中文",
    "zh-TW": "繁体中文",
    "es": "西班牙语",
    "ar": "阿拉伯语",
    "fr": "法语",
    "ru": "俄语",
    "pt": "葡萄语",
    "de": "德语",
    "ja": "日语",
    "hi": "印地语",
    "id": "印尼语",
    "ko": "韩语",
    "it": "意大利语",
    "tr": "土耳其语",
    "vi": "越南语",
    "th": "泰语",
    "nl": "荷兰语",
    "pl": "波兰语",
  };

  @override
  void initState() {
    super.initState();
    _loadPostDetails();
    _loadComments();
  }

  @override
  void dispose() {
    _quillController?.dispose();
    _commentController.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadPostDetails() async {
    try {
      final res = await HttpClient.instance.get<Map<String, dynamic>>('/api-posts/${widget.postId}');
      if (res.datas != null) {
        final postData = res.datas!;
        setState(() {
          _post = postData;
          _isLoadingPost = false;
          likeCount = (postData['likes'] as List?)?.length ?? 0;
          isCollected = postData['is_collected'] ?? false;
          isLiked = postData['is_liked'] ?? false;
        });
        _loadQuillContent(postData);
      }
    } catch (e) {
      setState(() => _isLoadingPost = false);
    }
  }

  void _loadQuillContent(Map<String, dynamic> post) {
    final type = post['post_type'] ?? 'quill';
    if (type != 'quill') return; // 图文说说等非 Quill 类型不进行富文本解析

    final contentStr = post['content'] ?? '';
    try {
      if (type == 'quill') {
        final json = jsonDecode(contentStr);
        final doc = quill.Document.fromJson(json);
        _quillController = quill.QuillController(
          document: doc,
          selection: const TextSelection.collapsed(offset: 0),
          readOnly: true,
        );
        _originalDelta = doc.toDelta();
      } else {
        final doc = quill.Document()..insert(0, contentStr);
        _quillController = quill.QuillController(
          document: doc,
          selection: const TextSelection.collapsed(offset: 0),
          readOnly: true,
        );
        _originalDelta = doc.toDelta();
      }
    } catch (_) {
      final doc = quill.Document()..insert(0, contentStr.toString());
      _quillController = quill.QuillController(
        document: doc,
        selection: const TextSelection.collapsed(offset: 0),
        readOnly: true,
      );
      _originalDelta = doc.toDelta();
    }
    setState(() {});
  }

  Future<void> _loadComments() async {
    try {
      final res = await HttpClient.instance.get<List<dynamic>>('/api-posts/${widget.postId}/comments');
      if (res.datas != null) {
        final parsed = (res.datas as List).map((e) => CommentModel.fromJson(e)).toList();
        setState(() {
          _comments = parsed;
          _isLoadingComments = false;
        });
      }
    } catch (e) {
      setState(() => _isLoadingComments = false);
    }
  }

  Future<void> _toggleLike() async {
    if (!UserController.to.isLoggedIn) {
      Fluttertoast.showToast(msg: "请登录后点赞");
      return;
    }
    try {
      final res = await HttpClient.instance.post<Map<String, dynamic>>('/api-posts/${widget.postId}/like');
      if (res.respCode == 0) {
        setState(() {
          isLiked = res.datas!['is_liked'];
          likeCount += isLiked ? 1 : -1;
        });
      }
    } catch (e) {
      if (e is ApiException) {
        Fluttertoast.showToast(msg: e.message);
      } else {
        Fluttertoast.showToast(msg: "点赞异常");
      }
    }
  }

  Future<void> _toggleCollect() async {
    if (!UserController.to.isLoggedIn) {
      Fluttertoast.showToast(msg: "请登录后收藏");
      return;
    }
    try {
      final res = await HttpClient.instance.post<Map<String, dynamic>>('/api-posts/${widget.postId}/collect');
      if (res.respCode == 0) {
        setState(() {
          isCollected = res.datas!['is_collected'];
        });
        Fluttertoast.showToast(msg: isCollected ? "收藏成功" : "已取消收藏");
      }
    } catch (e) {
      if (e is ApiException) {
        Fluttertoast.showToast(msg: e.message);
      } else {
        Fluttertoast.showToast(msg: "操作异常");
      }
    }
  }

  Future<bool?> showDeletePostDialog() {
    return Get.dialog<bool>(
      Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F1),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Center(
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedDelete02,
                    color: Color(0xFFFF4D4F),
                    size: 34,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "删除帖子",
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F1F1F),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                "确定要永久删除这篇帖子吗？\n删除后数据将无法恢复。",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.6,
                  color: Color(0xFF666666),
                ),
              ),
              const SizedBox(height: 26),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => Get.back(result: false),
                      child: Ink(
                        height: 52,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F5F7),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Center(
                          child: Text(
                            "取消",
                            style: TextStyle(
                              color: Color(0xFF666666),
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => Get.back(result: true),
                      child: Ink(
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFFFF6B6B),
                              Color(0xFFFF3B30),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFF3B30).withOpacity(0.25),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            HugeIcon(
                              icon: HugeIcons.strokeRoundedDelete02,
                              color: Colors.white,
                              size: 18,
                            ),
                            SizedBox(width: 6),
                            Text(
                              "删除",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      barrierDismissible: true,
      transitionCurve: Curves.easeOutCubic,
      transitionDuration: const Duration(milliseconds: 240),
    );
  }

  Future<void> _deletePost() async {
    final confirm = await showDeletePostDialog();
    if (confirm != true) return;

    try {
      final res = await HttpClient.instance.delete('/api-posts/${widget.postId}');
      if (res.respCode == 0) {
        Fluttertoast.showToast(msg: "帖子已成功删除");
        Get.back();
      }
    } catch (e) {
      Fluttertoast.showToast(msg: "删除失败: $e");
    }
  }

  Future<void> _submitVote() async {
    if (!UserController.to.isLoggedIn) {
      Fluttertoast.showToast(msg: "请登录后投票");
      return;
    }
    if (_selectedOptionId == null) {
      Fluttertoast.showToast(msg: "请选择一个投票项");
      return;
    }
    try {
      final res = await HttpClient.instance.post<Map<String, dynamic>>(
        '/api-posts/${widget.postId}/vote',
        data: {'option_id': _selectedOptionId},
      );
      if (res.respCode == 0) {
        Fluttertoast.showToast(msg: "投票提交成功");
        _loadPostDetails();
      }
    } catch (e) {
      if (e is ApiException) {
        Fluttertoast.showToast(msg: e.message);
      } else {
        Fluttertoast.showToast(msg: "投票失败，请稍后重试");
      }
    }
  }

  Future<void> _repostPost() async {
    if (!UserController.to.isLoggedIn) {
      Fluttertoast.showToast(msg: "请登录后进行转发");
      return;
    }
    try {
      final res = await HttpClient.instance.post('/api-posts/${widget.postId}/repost');
      if (res.respCode == 0) {
        Fluttertoast.showToast(msg: "已同步转发至您的空间");
        _loadPostDetails();
      }
    } catch (e) {
      if (e is ApiException) {
        Fluttertoast.showToast(msg: e.message);
      } else {
        Fluttertoast.showToast(msg: "转发失败: $e");
      }
    }
  }

  Future<void> _sharePost() async {
    if (!UserController.to.isLoggedIn) {
      Fluttertoast.showToast(msg: "请登录后分享");
      return;
    }

    // 1. 尝试拉取关注列表，即使失败也允许用户继续进行外部链接分享
    List<dynamic> topFollowed = [];
    try {
      final res = await HttpClient.instance.get<Map<String, dynamic>>('/api-users/profile');
      topFollowed = res.datas?['top_followed_users'] as List? ?? [];
    } catch (e) {
      // 仅作轻提示，不中断后续外部链接分享的操作
      Fluttertoast.showToast(msg: "拉取关系链失败");
    }

    // 拼接需要分享的外部链接
    final String shareUrl = "https://posts.zeabur.app/?id=${widget.postId}";

    // 2. 唤起重构后的现代化二级分享面板
    Get.bottomSheet(
      Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 10,
              spreadRadius: 1,
            )
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部下拉条指示器
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // 标题头部栏
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "分享至",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Get.back(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedCancel01,
                      color: Colors.grey,
                      size: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ================== 第一层：站内好友定向分享 ==================
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "分享给关注的好友",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[500],
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              SizedBox(
                height: 96,
                child: topFollowed.isEmpty
                    ? Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[100]!),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      HugeIcon(
                        icon: HugeIcons.strokeRoundedUserGroup,
                        color: Colors.grey[400]!,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "暂无关注好友，快去关注吧~",
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                )
                    : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: topFollowed.length,
                  itemBuilder: (context, index) {
                    final f = topFollowed[index];
                    final avatarUrl = f['avatar'] as String? ?? '';
                    final nickname = f['nickname'] as String? ?? '用户';

                    return Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () async {
                            final shareRes = await HttpClient.instance.post(
                              '/api-shares',
                              data: {
                                'post_id': widget.postId,
                                'recipient_user_ids': [f['id']]
                              },
                            );
                            if (shareRes.respCode == 0) {
                              Fluttertoast.showToast(msg: "定向推荐分享成功");
                              Get.back();
                            }
                          },
                          child: Container(
                            width: 64,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircleAvatar(
                                  radius: 24,
                                  backgroundColor: Colors.grey[100],
                                  backgroundImage: avatarUrl.isNotEmpty
                                      ? NetworkImage(avatarUrl)
                                      : null,
                                  child: avatarUrl.isEmpty
                                      ? const HugeIcon(
                                    icon: HugeIcons.strokeRoundedUser,
                                    color: Colors.grey,
                                    size: 20,
                                  )
                                      : null,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  nickname,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[800],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Divider(color: Colors.grey[100], thickness: 1, height: 1),
              ),

              // ================== 第二层：外部链接与应用分享 ==================
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "更多分享方式",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[500],
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  // 1. 复制外部链接
                  _buildShareOption(
                    icon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedCopy01,
                      color: Colors.black87,
                      size: 22,
                    ),
                    label: "复制链接",
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: shareUrl));
                      Fluttertoast.showToast(msg: "链接已复制到剪切板");
                      Get.back();
                    },
                  ),
                  const SizedBox(width: 16),

                  // 2. 浏览器打开
                  _buildShareOption(
                    icon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedGlobal,
                      color: Colors.black87,
                      size: 22,
                    ),
                    label: "浏览器打开",
                    onTap: () async {
                      final uri = Uri.parse(shareUrl);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                        Get.back();
                      } else {
                        Fluttertoast.showToast(msg: "无法打开浏览器");
                      }
                    },
                  ),
                  const SizedBox(width: 16),

                  // 3. 系统原生应用分享
                  _buildShareOption(
                    icon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedShare01,
                      color: Colors.black87,
                      size: 22,
                    ),
                    label: "系统分享",
                    onTap: () async {
                      // 提前关闭 BottomSheet，避免与原生底部分享弹窗在界面上重叠导致动画卡顿
                      Get.back();
                      await Share.share(
                        '给大家分享一个精彩瞬间：$shareUrl',
                        subject: '精彩内容分享',
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      isScrollControlled: true, // 确保高度自适应，防裁剪
    );
  }

// 提取的微操单元，包含平滑的材质水波纹及现代感 Squircle 边框
  Widget _buildShareOption({
    required HugeIcon icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(16), // 使用圆角矩形(Squircle)代替纯圆圈
                  border: Border.all(color: Colors.grey[100]!, width: 1.5),
                ),
                child: Center(child: icon),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _resetReplyState() {
    setState(() {
      _replyParentCommentId = null;
      _replyToUserId = null;
      _replyToNickname = null;
    });
  }

  void _startReply(CommentModel comment) {
    _openCommentInputBottomSheet(
      parentCommentId: comment.parentCommentId ?? comment.id,
      replyToUserId: comment.author.id,
      replyToNickname: comment.author.nickname,
      replyToAvatar: comment.author.avatar,
      replyToContent: comment.content,
    );
  }

  void _openCommentInputBottomSheet({
    String? parentCommentId,
    String? replyToUserId,
    String? replyToNickname,
    String? replyToAvatar,
    String? replyToContent,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _CommentInputSheet(
          postId: widget.postId,
          parentCommentId: parentCommentId,
          replyToUserId: replyToUserId,
          replyToNickname: replyToNickname,
          replyToAvatar: replyToAvatar,
          replyToContent: replyToContent,
          themeColor: const Color.fromRGBO(44, 123, 109, 1.0),
          onSuccess: () {
            _resetReplyState();
            _loadComments();
          },
        );
      },
    );
  }

  Future<void> _deleteComment(String commentId) async {
    try {
      final res = await HttpClient.instance.delete('/api-comments/$commentId');
      if (res.respCode == 0) {
        Fluttertoast.showToast(msg: "评论删除成功");
        _loadComments();
      }
    } catch (e) {
      Fluttertoast.showToast(msg: "删除评论失败: $e");
    }
  }

  void _handleTranslateTap() {
    if (isShowingTranslation) {
      _restoreOriginal();
    } else {
      _showCustomLanguageSelector();
    }
  }

  void _showCustomLanguageSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return _AnimatedLanguageSheet(
          languages: _supportedLanguages,
          onLanguageSelected: (key) {
            Navigator.pop(context);
            _performTranslate(key);
          },
        );
      },
    );
  }

  void _performTranslate(String targetLang) async {
    if (_post == null || _quillController == null || _originalDelta == null) return;
    setState(() => isTranslating = true);

    try {
      final QuillTranslationService translationService = QuillTranslationService();
      final quill.Delta translatedDelta = await translationService.translateDelta(_originalDelta!, targetLang);

      setState(() {
        _quillController = quill.QuillController(
          document: quill.Document.fromDelta(translatedDelta),
          selection: const TextSelection.collapsed(offset: 0),
          readOnly: true,
        );
        isShowingTranslation = true;
      });
    } catch (e) {
      Fluttertoast.showToast(msg: "翻译失败: $e");
    } finally {
      if (mounted) setState(() => isTranslating = false);
    }
  }

  void _restoreOriginal() {
    if (_originalDelta != null) {
      setState(() {
        _quillController = quill.QuillController(
          document: quill.Document.fromDelta(_originalDelta!),
          selection: const TextSelection.collapsed(offset: 0),
          readOnly: true,
        );
        isShowingTranslation = false;
      });
    }
  }

  Widget _buildTranslateButton() {
    if (isTranslating) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: Color.fromRGBO(44, 123, 109, 1.0)),
      );
    }
    return IconButton(
      onPressed: _handleTranslateTap,
      tooltip: isShowingTranslation ? "还原原文" : "翻译文章",
      icon: Icon(
        isShowingTranslation ? Icons.g_translate : Icons.translate_rounded,
        color: isShowingTranslation ? const Color.fromRGBO(44, 123, 109, 1.0) : Colors.black54,
      ),
    );
  }

  Widget _buildImageCarousel(List<dynamic> images) {
    if (images.isEmpty) return const SizedBox.shrink();
    final List<String> stringImages = images.map((e) => e.toString()).toList();
    return _DetailedImageCarousel(images: stringImages);
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = const Color.fromRGBO(44, 123, 109, 1.0);
    if (_isLoadingPost) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(backgroundColor: Colors.white, elevation: 0),
        body: Center(child: CircularProgressIndicator(color: themeColor, strokeWidth: 2)),
      );
    }
    if (_post == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(backgroundColor: Colors.white, elevation: 0),
        body: const Center(child: Text("内容不存在或已被删除")),
      );
    }

    final author = _post!['author'] ?? {};
    final title = _post!['title'] ?? '';
    final type = _post!['post_type'] ?? 'quill';
    final timestamp = _post!['created_at'] != null ? _post!['created_at'].toString().substring(0, 10) : '';
    final viewsCount = _post!['views_count'] ?? 0;
    final morePosts = _post!['more_posts'] as List? ?? [];
    final isMe = author['is_me'] ?? false;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true, // 确保中部组件强制居中
        leading: IconButton(
          onPressed: () => Get.back(),
          icon: const Icon(Icons.arrow_back, color: Colors.black),
        ),
        title: GestureDetector(
          onTap: () => Get.to(() => ProfileView(profileId: author['id'])),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade100, width: 0.5),
            ),
            // 限制中部胶囊的最大宽度，防止挤压右侧图标
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.35),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(radius: 12, backgroundImage: NetworkImage(author['avatar'] ?? '')),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    author['nickname'] ?? '未知昵称',
                    style: const TextStyle(fontSize: 13, color: Colors.black87, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (type == 'quill')
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: _buildTranslateButton(),
                ),
              IconButton(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  constraints: const BoxConstraints(), // 解除默认大热区限制
                  onPressed: _toggleCollect,
                  icon: Icon(isCollected ? Icons.bookmark : Icons.bookmark_border, color: themeColor, size: 22)
              ),
              IconButton(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  constraints: const BoxConstraints(),
                  onPressed: _sharePost,
                  icon: Icon(Icons.share, color: themeColor, size: 22)
              ),
              if (isMe)
                IconButton(
                  padding: const EdgeInsets.fromLTRB(4, 0, 12, 0),
                  constraints: const BoxConstraints(),
                  onPressed: _deletePost,
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 22),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 说说没有标题，其他有标题则展示
                  if (type != 'short_post' && title.isNotEmpty) ...[
                    SelectableText(
                      title,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.black87, height: 1.3),
                    ),
                    const SizedBox(height: 10),
                  ],

                  Row(
                    children: [
                      Text("发布于 $timestamp  ·  $viewsCount 次阅读", style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                      if (type == 'quill' && isShowingTranslation) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: themeColor.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: themeColor.withOpacity(0.2)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.translate, size: 12, color: themeColor),
                              const SizedBox(width: 4),
                              Text("机器译文", style: TextStyle(fontSize: 10, color: themeColor, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 24),

                  // 根据不同的帖子类型渲染主体内容
                  if (type == 'short_post') ...[
                    SelectableText(
                      _post!['content'] ?? '',
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.6,
                        color: Color(0xFF1F2937),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildImageCarousel(_post!['images'] as List? ?? []),
                  ] else if (type == 'poll') ...[
                    SelectableText(
                      _post!['content'] ?? '',
                      style: const TextStyle(fontSize: 16, height: 1.6, color: Color(0xFF374151)),
                    ),
                    const SizedBox(height: 16),
                    if (_post!['poll'] != null) _buildPollSection(themeColor),
                  ] else ...[
                    if (_quillController != null)
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 300),
                        opacity: isTranslating ? 0.3 : 1.0,
                        child: quill.QuillEditor.basic(
                          controller: _quillController!,
                          config: quill.QuillEditorConfig(
                            customStyles: const quill.DefaultStyles(
                              paragraph: quill.DefaultTextBlockStyle(
                                TextStyle(fontSize: 18.0, color: Colors.black87, height: 1.5, fontFamily: 'ShantellSans'),
                                quill.HorizontalSpacing(0, 0),
                                quill.VerticalSpacing(0, 0),
                                quill.VerticalSpacing(0, 0),
                                null,
                              ),
                              placeHolder: quill.DefaultTextBlockStyle(
                                TextStyle(fontSize: 18.0, color: Color(0xFF9CA3AF), height: 1.5, fontFamily: 'ShantellSans'),
                                quill.HorizontalSpacing(0, 0),
                                quill.VerticalSpacing(0, 0),
                                quill.VerticalSpacing(0, 0),
                                null,
                              ),
                            ),
                            embedBuilders: [
                              DividerEmbedBuilder(),
                              ...FlutterQuillEmbeds.editorBuilders(),
                            ],
                          ),
                        ),
                      ),
                  ],

                  const SizedBox(height: 24),
                  _buildLikeBar(themeColor),
                  const Divider(height: 40),
                  _buildAuthorCard(context, author, themeColor),
                  const Divider(height: 40),

                  if (morePosts.isNotEmpty) _buildMorePostsHorizontal(morePosts, themeColor),

                  const Text("精选讨论", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  if (_isLoadingComments)
                    Center(child: CircularProgressIndicator(color: themeColor, strokeWidth: 2))
                  else if (_comments.isEmpty)
                    const Center(child: Padding(padding: EdgeInsets.all(20), child: Text("暂无讨论，发表你的看法吧", style: TextStyle(color: Colors.grey))))
                  else
                    ..._comments.map((c) => _buildCommentItem(c, themeColor)),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
          _buildBottomInputArea(themeColor),
        ],
      ),
    );
  }

  Widget _buildPollSection(Color themeColor) {
    final poll = _post!['poll'] ?? {};
    final question = poll['question'] ?? '进行投票';
    final options = poll['options'] as List? ?? [];

    int totalVotes = 0;
    for (var opt in options) {
      totalVotes += (opt['votes'] as List?)?.length ?? 0;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText("投票：$question", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 12),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: options.length,
            itemBuilder: (context, index) {
              final opt = options[index];
              final optionId = opt['option_id'];
              final text = opt['text'];
              final optionVotes = (opt['votes'] as List?)?.length ?? 0;
              final ratio = totalVotes == 0 ? 0.0 : (optionVotes / totalVotes);

              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: GestureDetector(
                  onTap: () => setState(() => _selectedOptionId = optionId),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _selectedOptionId == optionId ? themeColor : Colors.grey.shade200,
                        width: _selectedOptionId == optionId ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.white,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(text, style: const TextStyle(fontSize: 13)),
                              const SizedBox(height: 4),
                              LinearProgressIndicator(value: ratio, color: themeColor, backgroundColor: Colors.grey.shade100),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text("${(ratio * 100).toStringAsFixed(1)}% ($optionVotes票)", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submitVote,
              style: ElevatedButton.styleFrom(backgroundColor: themeColor, elevation: 0),
              child: const Text("提交我的表态", style: TextStyle(color: Colors.white)),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildLikeBar(Color themeColor) {
    return Row(
      children: [
        InkWell(
          onTap: _toggleLike,
          borderRadius: BorderRadius.circular(30),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isLiked ? themeColor.withOpacity(0.1) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: isLiked ? themeColor.withOpacity(0.3) : Colors.transparent),
            ),
            child: Row(
              children: [
                HugeIcon(
                  icon: isLiked ? HugeIcons.strokeRoundedFavourite : HugeIcons.strokeRoundedFavourite,
                  size: 20,
                  color: isLiked ? themeColor : Colors.grey,
                ),
                const SizedBox(width: 6),
                Text(
                  "$likeCount",
                  style: TextStyle(color: isLiked ? themeColor : Colors.grey[700], fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        IconButton(
          onPressed: _repostPost,
          icon: const Icon(Icons.repeat, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildAuthorCard(BuildContext context, dynamic author, Color themeColor) {
    final bio = author['bio'] ?? '';
    final followersCount = author['followers_count'] ?? 0;
    final followingCount = author['following_count'] ?? 0;
    final isFollowing = author['is_following'] ?? false;
    final isMe = author['is_me'] ?? false;

    return Row(
      children: [
        GestureDetector(
          onTap: () => Get.to(() => ProfileView(profileId: author['id'])),
          child: CircleAvatar(radius: 24, backgroundImage: NetworkImage(author['avatar'] ?? '')),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: () => Get.to(() => ProfileView(profileId: author['id'])),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(author['nickname'] ?? '用户', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                if (bio.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final style = TextStyle(fontSize: 12, color: Colors.grey.shade500);
                      final span = TextSpan(text: bio, style: style);
                      final tp = TextPainter(
                        text: span,
                        maxLines: 2,
                        textDirection: TextDirection.ltr,
                      );
                      tp.layout(maxWidth: constraints.maxWidth);
                      final isExceeded = tp.didExceedMaxLines;

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Text(
                              bio,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: style,
                            ),
                          ),
                          if (isExceeded)
                            GestureDetector(
                              onTap: () => _showFullBioBottomSheet(context, bio),
                              child: Padding(
                                padding: const EdgeInsets.only(left: 6.0),
                                child: Text(
                                  "更多",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: themeColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
                const SizedBox(height: 4),
                Text("$followersCount 粉丝 · $followingCount 关注", style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
        ),
        if (!isMe)
          ElevatedButton(
            onPressed: () async {
              if (!UserController.to.isLoggedIn) {
                Fluttertoast.showToast(msg: "请登录后关注");
                return;
              }
              try {
                final res = await HttpClient.instance.post<Map<String, dynamic>>('/api-users/follow', data: {'target_user_id': author['id']});
                if (res.respCode == 0) {
                  _loadPostDetails();
                }
              } catch (e) {
                Fluttertoast.showToast(msg: "关注失败");
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isFollowing ? Colors.grey.shade100 : themeColor,
              foregroundColor: isFollowing ? Colors.black : Colors.white,
              elevation: 0,
            ),
            child: Text(isFollowing ? "已关注" : "关注"),
          ),
      ],
    );
  }

  void _showFullBioBottomSheet(BuildContext context, String bio) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "用户简介",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.4,
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      bio,
                      style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMorePostsHorizontal(List<dynamic> morePosts, Color themeColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("该作者的更多文章", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        SizedBox(
          height: 170,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: morePosts.length,
            itemBuilder: (context, index) {
              final p = morePosts[index];
              final thumbnail = p['thumbnail'] as String? ?? '';
              final title = p['title'] as String? ?? '';
              final dateStr = p['created_at'] != null ? p['created_at'].toString().substring(0, 10) : '';
              final views = p['views_count'] ?? 0;

              return GestureDetector(
                onTap: () => Get.off(() => PostDetailView(postId: p['id']), preventDuplicates: false),
                child: Container(
                  width: 200,
                  margin: const EdgeInsets.only(right: 14, bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200, width: 0.8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.02),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 5,
                          child: thumbnail.isNotEmpty
                              ? Image.network(thumbnail, fit: BoxFit.cover, width: double.infinity)
                              : Container(
                            color: themeColor.withOpacity(0.05),
                            width: double.infinity,
                            child: Icon(Icons.article_outlined, color: themeColor.withOpacity(0.3), size: 32),
                          ),
                        ),
                        Expanded(
                          flex: 4,
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text("$views 阅读", style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                    Text(dateStr, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                  ],
                                )
                              ],
                            ),
                          ),
                        )
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const Divider(height: 32),
      ],
    );
  }

  Widget _buildCommentItem(CommentModel comment, Color themeColor) {
    final isCommentMe = comment.author.id == UserController.to.user.value?.id;
    final formattedTime = comment.createdAt.length > 16 ? comment.createdAt.substring(0, 16).replaceAll('T', ' ') : comment.createdAt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => _startReply(comment),
          onLongPress: () => _showCommentLongPressMenu(comment),
          splashColor: Colors.transparent,
          highlightColor: Colors.grey.withOpacity(0.05),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => Get.to(() => ProfileView(profileId: comment.author.id)),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.blue.shade50,
                    backgroundImage: NetworkImage(comment.author.avatar),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          GestureDetector(
                            onTap: () => Get.to(() => ProfileView(profileId: comment.author.id)),
                            child: Text(
                              comment.author.nickname,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                            ),
                          ),
                          if (isCommentMe)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: themeColor.withOpacity(0.12), borderRadius: BorderRadius.circular(4)),
                              child: Text('我', style: TextStyle(fontSize: 10, color: themeColor, fontWeight: FontWeight.bold)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      RichText(
                        text: TextSpan(
                          style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.4),
                          children: [
                            if (comment.replyToUser != null) ...[
                              const TextSpan(text: "回复 "),
                              TextSpan(
                                text: "@${comment.replyToUser!.nickname} ",
                                style: TextStyle(color: themeColor, fontWeight: FontWeight.bold),
                              ),
                            ],
                            TextSpan(text: comment.content),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(formattedTime, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          const SizedBox(width: 14),
                          GestureDetector(
                            onTap: () => _startReply(comment),
                            child: Text("回复", style: TextStyle(fontSize: 11, color: themeColor, fontWeight: FontWeight.bold)),
                          )
                        ],
                      ),
                      if (comment.replies.isNotEmpty)
                        _buildSubCommentPreviewBox(comment, themeColor),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
      ],
    );
  }

  Widget _buildSubCommentPreviewBox(CommentModel comment, Color themeColor) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: GestureDetector(
        onTap: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (context) => PostSubCommentSheet(
              parentComment: comment,
              postId: widget.postId,
              themeColor: themeColor,
              onReplyRequested: (targetComment) {
                Navigator.pop(context);
                _startReply(targetComment);
              },
              onDeleteRequested: (commentId) {
                Navigator.pop(context);
                _deleteComment(commentId);
              },
            ),
          );
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...comment.replies.take(2).map((sub) => Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: RichText(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    style: const TextStyle(fontSize: 12, color: Color(0xFF4B5563)),
                    children: [
                      TextSpan(
                        text: "${sub.author.nickname}: ",
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1F2937)),
                      ),
                      TextSpan(text: sub.content),
                    ],
                  ),
                ),
              )),
              if (comment.replies.length > 2)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Row(
                    children: [
                      Text(
                        '查看全部 ${comment.replies.length} 条回复',
                        style: TextStyle(fontSize: 12, color: themeColor, fontWeight: FontWeight.bold),
                      ),
                      Icon(Icons.keyboard_arrow_right_rounded, size: 14, color: themeColor),
                    ],
                  ),
                )
            ],
          ),
        ),
      ),
    );
  }

  void _showCommentLongPressMenu(CommentModel comment) {
    final isCommentMe = comment.author.id == UserController.to.user.value?.id;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFFF2F2F7),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (menuContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: Column(
                  children: [
                    _buildIOSActionItem(
                      icon: Icons.reply,
                      title: "回复",
                      onTap: () {
                        Navigator.pop(menuContext);
                        _startReply(comment);
                      },
                    ),
                    const Divider(height: 0.5, indent: 16, endIndent: 16),
                    _buildIOSActionItem(
                      icon: Icons.copy,
                      title: "复制评论",
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: comment.content));
                        Navigator.pop(menuContext);
                        Fluttertoast.showToast(msg: "评论已复制到剪切板");
                      },
                    ),
                  ],
                ),
              ),
              if (isCommentMe)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                  child: _buildIOSActionItem(
                    icon: Icons.delete_outline,
                    title: "删除该条评论",
                    textColor: Colors.redAccent,
                    onTap: () {
                      Navigator.pop(menuContext);
                      _deleteComment(comment.id);
                    },
                  ),
                ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => Navigator.pop(menuContext),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 14),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                  alignment: Alignment.center,
                  child: const Text("取消", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildIOSActionItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color textColor = Colors.black87,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: textColor == Colors.redAccent ? Colors.redAccent : Colors.grey),
            const SizedBox(width: 12),
            Text(title, style: TextStyle(fontSize: 15, color: textColor, fontWeight: FontWeight.w500)),
            const Spacer(),
            const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  // 美化设计的底部占位评论输入框触发栏
  Widget _buildBottomInputArea(Color themeColor) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, -4),
          )
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _openCommentInputBottomSheet(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 16, color: Colors.grey[500]),
                        const SizedBox(width: 8),
                        Text(
                          "写下你的看法...",
                          style: TextStyle(color: Colors.grey[500], fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                onPressed: () => _openCommentInputBottomSheet(),
                icon: const Icon(Icons.reply_rounded, color: Colors.white, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: themeColor,
                  elevation: 0,
                  padding: const EdgeInsets.all(10),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 专门用来渲染子评论二级详情树的底部滑出 sheet
class PostSubCommentSheet extends StatelessWidget {
  final CommentModel parentComment;
  final String postId;
  final Color themeColor;
  final Function(CommentModel) onReplyRequested;
  final Function(String) onDeleteRequested;

  const PostSubCommentSheet({
    super.key,
    required this.parentComment,
    required this.postId,
    required this.themeColor,
    required this.onReplyRequested,
    required this.onDeleteRequested,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              Container(
                height: 52,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6), width: 0.5)),
                ),
                child: Stack(
                  children: [
                    const Center(
                      child: Text('回复详情', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1F2937))),
                    ),
                    Positioned(
                      left: 16,
                      top: 0,
                      bottom: 0,
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF9CA3AF), size: 16),
                      ),
                    )
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: parentComment.replies.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Column(
                        children: [
                          _buildSingleCommentItem(context, parentComment, isParent: true),
                          Container(height: 8, color: const Color(0xFFF3F4F6)),
                          const Padding(
                            padding: EdgeInsets.only(left: 16, top: 12, bottom: 4),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text("全部回复", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF4B5563))),
                            ),
                          )
                        ],
                      );
                    }

                    final subComment = parentComment.replies[index - 1];
                    return _buildSingleCommentItem(context, subComment, isParent: false);
                  },
                ),
              ),
              Container(
                padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 12, top: 10, left: 16, right: 16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Color(0xFFF3F4F6), width: 0.5)),
                ),
                child: GestureDetector(
                  onTap: () => onReplyRequested(parentComment),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(20)),
                    child: Text("回复 @${parentComment.author.nickname}...", style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSingleCommentItem(BuildContext context, CommentModel comment, {required bool isParent}) {
    final isMe = comment.author.id == UserController.to.user.value?.id;
    final formattedTime = comment.createdAt.length > 16 ? comment.createdAt.substring(0, 16).replaceAll('T', ' ') : comment.createdAt;

    return InkWell(
      onTap: () => onReplyRequested(comment),
      onLongPress: () {
        _showIOSSheetMenu(context, comment);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(radius: 16, backgroundImage: NetworkImage(comment.author.avatar)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(comment.author.nickname, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF4B5563))),
                      if (isMe)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: themeColor.withOpacity(0.12), borderRadius: BorderRadius.circular(4)),
                          child: Text('我', style: TextStyle(fontSize: 10, color: themeColor, fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 13, color: Color(0xFF1F2937), height: 1.4),
                      children: [
                        if (!isParent && comment.replyToUser != null) ...[
                          const TextSpan(text: "回复 "),
                          TextSpan(text: "@${comment.replyToUser!.nickname} ", style: TextStyle(color: themeColor, fontWeight: FontWeight.bold)),
                        ],
                        TextSpan(text: comment.content),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(formattedTime, style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                      const SizedBox(width: 14),
                      Text("回复", style: TextStyle(fontSize: 11, color: themeColor, fontWeight: FontWeight.bold)),
                    ],
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  void _showIOSSheetMenu(BuildContext context, CommentModel comment) {
    final isMe = comment.author.id == UserController.to.user.value?.id;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFFF2F2F7),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (menuContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: Column(
                  children: [
                    _buildSubSheetActionItem(
                      icon: Icons.reply,
                      title: "回复",
                      onTap: () {
                        Navigator.pop(menuContext);
                        onReplyRequested(comment);
                      },
                    ),
                    const Divider(height: 0.5, indent: 16, endIndent: 16),
                    _buildSubSheetActionItem(
                      icon: Icons.copy,
                      title: "复制",
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: comment.content));
                        Navigator.pop(menuContext);
                        Fluttertoast.showToast(msg: "评论已复制");
                      },
                    ),
                  ],
                ),
              ),
              if (isMe)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                  child: _buildSubSheetActionItem(
                    icon: Icons.delete_outline,
                    title: "删除该条回复",
                    textColor: Colors.redAccent,
                    onTap: () {
                      Navigator.pop(menuContext);
                      onDeleteRequested(comment.id);
                    },
                  ),
                ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => Navigator.pop(menuContext),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 14),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                  alignment: Alignment.center,
                  child: const Text("取消", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSubSheetActionItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color textColor = Colors.black87,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: textColor == Colors.redAccent ? Colors.redAccent : Colors.grey),
            const SizedBox(width: 12),
            Text(title, style: TextStyle(fontSize: 15, color: textColor, fontWeight: FontWeight.w500)),
            const Spacer(),
            const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}

// 翻译模态层
class _AnimatedLanguageSheet extends StatefulWidget {
  final Map<String, String> languages;
  final Function(String) onLanguageSelected;

  const _AnimatedLanguageSheet({
    required this.languages,
    required this.onLanguageSelected,
  });

  @override
  State<_AnimatedLanguageSheet> createState() => _AnimatedLanguageSheetState();
}

class _AnimatedLanguageSheetState extends State<_AnimatedLanguageSheet> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.only(top: 20, bottom: 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                HugeIcon(icon: HugeIcons.strokeRoundedLanguageSkill, color: Colors.black87),
                SizedBox(width: 10),
                Text("选择目标翻译语言", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Divider(height: 1),
          SizedBox(
            height: 350,
            child: ListView.builder(
              itemCount: widget.languages.length,
              padding: const EdgeInsets.symmetric(vertical: 10),
              itemBuilder: (context, index) {
                final key = widget.languages.keys.elementAt(index);
                final name = widget.languages.values.elementAt(index);

                final animation = Tween<Offset>(
                  begin: const Offset(0, 0.5),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: _controller,
                    curve: Interval(index * 0.05, 0.5 + index * 0.05, curve: Curves.easeOutBack),
                  ),
                );

                final fadeAnim = Tween<double>(begin: 0, end: 1).animate(
                  CurvedAnimation(
                    parent: _controller,
                    curve: Interval(index * 0.05, 0.5 + index * 0.05),
                  ),
                );

                return AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return FadeTransition(
                      opacity: fadeAnim,
                      child: SlideTransition(
                        position: animation,
                        child: InkWell(
                          onTap: () => widget.onLanguageSelected(key),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(color: Colors.grey[100], shape: BoxShape.circle),
                                  child: Text(name[0], style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)),
                                ),
                                const SizedBox(width: 16),
                                Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                                const Spacer(),
                                Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey[300]),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// 轮播卡片设计
class _DetailedImageCarousel extends StatefulWidget {
  final List<String> images;
  const _DetailedImageCarousel({required this.images});

  @override
  State<_DetailedImageCarousel> createState() => _DetailedImageCarouselState();
}

class _DetailedImageCarouselState extends State<_DetailedImageCarousel> {
  int _currentIndex = 0;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.88);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 380,
      child: PageView.builder(
        controller: _pageController,
        itemCount: widget.images.length,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        physics: const BouncingScrollPhysics(),
        itemBuilder: (context, index) {
          final imageUrl = widget.images[index];
          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            margin: EdgeInsets.symmetric(
              horizontal: 6,
              vertical: _currentIndex == index ? 0 : 12,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        color: Colors.grey.shade100,
                        child: const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color.fromRGBO(44, 123, 109, 1.0),
                          ),
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.broken_image, color: Colors.grey, size: 40),
                      );
                    },
                  ),
                  Positioned(
                    top: 14,
                    right: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        "${index + 1}/${widget.images.length}",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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
}

// 被物理键盘顶起的输入底部弹窗
class _CommentInputSheet extends StatefulWidget {
  final String postId;
  final String? parentCommentId;
  final String? replyToUserId;
  final String? replyToNickname;
  final String? replyToAvatar;
  final String? replyToContent;
  final Color themeColor;
  final VoidCallback onSuccess;

  const _CommentInputSheet({
    required this.postId,
    this.parentCommentId,
    this.replyToUserId,
    this.replyToNickname,
    this.replyToAvatar,
    this.replyToContent,
    required this.themeColor,
    required this.onSuccess,
  });

  /// 提供一个静态方法，方便外部直接弹出该底部输入弹窗
  static Future<void> show(
      BuildContext context, {
        required String postId,
        String? parentCommentId,
        String? replyToUserId,
        String? replyToNickname,
        String? replyToAvatar,
        String? replyToContent,
        required Color themeColor,
        required VoidCallback onSuccess,
      }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // 使用标准的轻快过度，弹窗普通滑出
      transitionAnimationController: AnimationController(
        vsync: Navigator.of(context),
        duration: const Duration(milliseconds: 200),
        reverseDuration: const Duration(milliseconds: 150),
      ),
      builder: (context) => _CommentInputSheet(
        postId: postId,
        parentCommentId: parentCommentId,
        replyToUserId: replyToUserId,
        replyToNickname: replyToNickname,
        replyToAvatar: replyToAvatar,
        replyToContent: replyToContent,
        themeColor: themeColor,
        onSuccess: onSuccess,
      ),
    );
  }

  @override
  State<_CommentInputSheet> createState() => _CommentInputSheetState();
}

class _CommentInputSheetState extends State<_CommentInputSheet> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isSending = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;

    if (!UserController.to.isLoggedIn) {
      Fluttertoast.showToast(msg: "请登录后发布讨论");
      return;
    }

    setState(() => _isSending = true);

    try {
      final res = await HttpClient.instance.post(
        '/api-posts/${widget.postId}/comments',
        data: {
          'content': text,
          if (widget.parentCommentId != null) 'parent_comment_id': widget.parentCommentId,
          if (widget.replyToUserId != null) 'reply_to_user_id': widget.replyToUserId,
        },
      );
      if (res.respCode == 0) {
        Fluttertoast.showToast(msg: "讨论发布成功");
        widget.onSuccess();
        Navigator.pop(context);
      }
    } catch (e) {
      Fluttertoast.showToast(msg: "讨论发布异常");
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      // 随着键盘手动拉起，弹窗平稳被顶起（由于弹窗本身已静止，故没有重绘冲突，极为顺滑）
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(), // 消除物理弹性阻尼，保持反馈利落
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(width: 40),
                    const Text(
                      "回复",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.grey, size: 22),
                      onPressed: () => Navigator.pop(context),
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFF3F4F6)),

              // Quoted Parent Comment if exists
              if (widget.replyToNickname != null) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundImage: widget.replyToAvatar != null
                            ? NetworkImage(widget.replyToAvatar!)
                            : null,
                        backgroundColor: widget.themeColor.withOpacity(0.1),
                        child: widget.replyToAvatar == null
                            ? Icon(Icons.person, color: widget.themeColor, size: 18)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  widget.replyToNickname!,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Color(0xFF1F2937),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  "@${widget.replyToNickname!.toLowerCase()}",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.replyToContent ?? '',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF4B5563),
                                height: 1.4,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              "回复给 @${widget.replyToNickname}",
                              style: TextStyle(
                                fontSize: 11,
                                color: widget.themeColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(left: 38),
                  alignment: Alignment.centerLeft,
                  height: 12,
                  child: Container(
                    width: 2,
                    color: Colors.grey.shade200,
                  ),
                ),
              ],

              // Input TextField Box
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end, // 输入高度变高时，两端按钮保持对齐在最底部
                  children: [
                    if (widget.replyToNickname == null) ...[
                      Obx(() {
                        final avatarUrl = UserController.to.user.value?.avatar ?? '';
                        return CircleAvatar(
                          radius: 16,
                          backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                          backgroundColor: widget.themeColor.withOpacity(0.1),
                          child: avatarUrl.isEmpty ? Icon(Icons.person, color: widget.themeColor, size: 16) : null,
                        );
                      }),
                      const SizedBox(width: 12),
                    ] else ...[
                      Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        child: Icon(Icons.subdirectory_arrow_right_rounded, color: Colors.grey.shade400, size: 18),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9FAFB),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _controller,
                                focusNode: _focusNode,
                                maxLines: 5,
                                minLines: 1,
                                textInputAction: TextInputAction.send,
                                onSubmitted: (_) => _submit(), // 物理/虚拟键盘直接回车发送
                                style: const TextStyle(fontSize: 14, color: Color(0xFF1F2937)),
                                decoration: InputDecoration(
                                  hintText: widget.replyToNickname != null ? "写下您的回复..." : "写下您的看法...",
                                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // 使用 ValueListenableBuilder 局部刷新发送按钮，避免文字输入时引起整个对话框重绘
                            ValueListenableBuilder<TextEditingValue>(
                              valueListenable: _controller,
                              builder: (context, value, child) {
                                final isTextEmpty = value.text.trim().isEmpty;
                                return GestureDetector(
                                  onTap: (isTextEmpty || _isSending) ? null : _submit,
                                  child: AnimatedOpacity(
                                    duration: const Duration(milliseconds: 100),
                                    opacity: isTextEmpty ? 0.4 : 1.0,
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: isTextEmpty ? Colors.grey.shade300 : widget.themeColor,
                                        shape: BoxShape.circle,
                                      ),
                                      child: _isSending
                                          ? SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      )
                                          : const Icon(
                                        Icons.arrow_upward_rounded,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              SafeArea(top: false, child: Container()),
            ],
          ),
        ),
      ),
    );
  }
}
class CommentModel {
  final String id;
  final String postId;
  final String content;
  final String createdAt;
  final String? parentCommentId;
  final String? replyToUserId;
  final CommentAuthor author;
  final CommentAuthor? replyToUser;
  final RxList<CommentModel> replies;

  CommentModel({
    required this.id,
    required this.postId,
    required this.content,
    required this.createdAt,
    this.parentCommentId,
    this.replyToUserId,
    required this.author,
    this.replyToUser,
    List<CommentModel>? replies,
  }) : replies = (replies ?? <CommentModel>[]).obs;

  factory CommentModel.fromJson(Map<String, dynamic> json) {
    var subList = <CommentModel>[];
    if (json['replies'] != null) {
      json['replies'].forEach((v) {
        subList.add(CommentModel.fromJson(v));
      });
    }

    return CommentModel(
      id: json['id'] ?? '',
      postId: json['post_id'] ?? '',
      content: json['content'] ?? '',
      createdAt: json['created_at'] ?? '',
      parentCommentId: json['parent_comment_id'],
      replyToUserId: json['reply_to_user_id'],
      author: CommentAuthor.fromJson(json['author'] ?? {}),
      replyToUser: json['reply_to_user'] != null ? CommentAuthor.fromJson(json['reply_to_user']) : null,
      replies: subList,
    );
  }
}

class CommentAuthor {
  final String id;
  final String nickname;
  final String avatar;

  CommentAuthor({
    required this.id,
    required this.nickname,
    required this.avatar,
  });

  factory CommentAuthor.fromJson(Map<String, dynamic> json) {
    return CommentAuthor(
      id: json['id'] ?? '',
      nickname: json['nickname'] ?? '已注销用户',
      avatar: json['avatar'] ?? '',
    );
  }
}