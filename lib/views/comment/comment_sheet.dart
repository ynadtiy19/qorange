import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import '../../network/api_exception.dart';
import '../../network/http_client.dart';
import '../../user_controller.dart';

class CommentSheet extends StatefulWidget {
  final String postId;
  final int postType; // 区分帖子或文章
  const CommentSheet({super.key, required this.postId, required this.postType});

  @override
  State<CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends State<CommentSheet> {
  final TextEditingController _commentController = TextEditingController();
  List<dynamic> _comments = [];
  bool _isLoading = true;
  String? _parentCommentId;
  String? _replyToUserId;
  String _hintText = "写下你的高见...";

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    try {
      final res = await HttpClient.instance.get<List<dynamic>>('/api-posts/${widget.postId}/comments');
      if (res.datas != null) {
        setState(() {
          _comments = res.datas!;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _submitComment() async {
    if (!UserController.to.isLoggedIn) {
      Fluttertoast.showToast(msg: "请登录后评论");
      return;
    }
    if (_commentController.text.trim().isEmpty) {
      return;
    }

    try {
      final body = {
        'content': _commentController.text,
        if (_parentCommentId != null) 'parent_comment_id': _parentCommentId,
        if (_replyToUserId != null) 'reply_to_user_id': _replyToUserId,
      };

      final res = await HttpClient.instance.post('/api-posts/${widget.postId}/comments', data: body);
      if (res.respCode == 0) {
        Fluttertoast.showToast(msg: "评论已同步");
        _commentController.clear();
        setState(() {
          _parentCommentId = null;
          _replyToUserId = null;
          _hintText = "写下你的高见...";
        });
        _loadComments();
      }
    } catch (e) {
      if (e is ApiException) {
        Fluttertoast.showToast(msg: e.message);
      } else {
        Fluttertoast.showToast(msg: "发布评论异常");
      }
    }
  }

  void _prepareReply(dynamic comment, String? parentId) {
    setState(() {
      _parentCommentId = parentId ?? comment['id'];
      _replyToUserId = comment['author']['id'];
      _hintText = "回复 @${comment['author']['nickname']}:";
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = const Color.fromRGBO(44, 123, 109, 1.0);
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            height: 50,
            alignment: Alignment.center,
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
            child: const Text("全部高能讨论", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ),
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: themeColor))
                : _comments.isEmpty
                ? const Center(child: Text("暂无讨论，快来抢沙发"))
                : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _comments.length,
              itemBuilder: (context, index) {
                final comment = _comments[index];
                return _buildCommentItem(comment, true, themeColor);
              },
            ),
          ),
          Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 12,
              top: 10,
              left: 16,
              right: 16,
            ),
            decoration: BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.grey.shade100))),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: _commentController,
                      decoration: InputDecoration(hintText: _hintText, border: InputBorder.none, hintStyle: TextStyle(color: Colors.grey.shade400)),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _submitComment,
                  icon: Icon(Icons.send, color: themeColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentItem(dynamic comment, bool isParent, Color themeColor) {
    final author = comment['author'] ?? {};
    final replies = comment['replies'] as List? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(radius: 14, backgroundImage: NetworkImage(author['avatar'] ?? '')),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(author['nickname'] ?? '用户', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 4),
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(color: Colors.black87, fontSize: 13, height: 1.4),
                        children: [
                          if (comment['reply_to_user'] != null) ...[
                            const TextSpan(text: "回复 "),
                            TextSpan(
                              text: "@${comment['reply_to_user']['nickname']} ",
                              style: TextStyle(color: themeColor, fontWeight: FontWeight.bold),
                            ),
                          ],
                          TextSpan(text: comment['content'] ?? ''),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          comment['created_at'] != null ? comment['created_at'].toString().substring(11, 16) : '',
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
                        ),
                        const SizedBox(width: 16),
                        GestureDetector(
                          onTap: () => _prepareReply(comment, isParent ? comment['id'] : comment['parent_comment_id']),
                          child: const Text("回复", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (isParent && replies.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 36.0),
            child: Column(
              children: replies.map((reply) => _buildCommentItem(reply, false, themeColor)).toList(),
            ),
          ),
      ],
    );
  }
}