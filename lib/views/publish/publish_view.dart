// lib/views/publish/publish_view.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:image_picker/image_picker.dart';

import '../../network/api_exception.dart';
import '../../network/http_client.dart';
import '../../services/api_service.dart';
import '../../user_controller.dart';
import '../../widgets/modern_emoji_picker.dart';
import '../../widgets/quill_custom_divider.dart';
import '../../widgets/quill_custom_video.dart';

class PublishView extends StatefulWidget {
  const PublishView({super.key});

  @override
  State<PublishView> createState() => _PublishViewState();
}

class _PublishViewState extends State<PublishView> with TickerProviderStateMixin {
  // 0: 深度文章, 1: 投票发布, 2: 图文说说 (默认聚焦于写想法)
  int _activeFormIndex = 2;

  // 键盘与表情面板无缝协同
  bool _isEmojiPanelVisible = false;
  // 🌟 核心：持久化健康键盘高度（默认 336），绝不在键盘关闭时塌陷或被覆盖为小值
  double _stableKeyboardHeight = 336.0;

  // 视频上传与进度状态
  bool _isUploadingVideo = false;
  double _videoUploadProgress = 0.0;

  // Quill 深度文章表单
  final TextEditingController _quillTitleController = TextEditingController();
  final TextEditingController _quillPriceController = TextEditingController();
  final quill.QuillController _quillController = quill.QuillController.basic();
  final ScrollController _quillScrollController = ScrollController();
  final TextEditingController _quillTagsController = TextEditingController();
  final FocusNode _quillEditorFocusNode = FocusNode();
  String _quillCategory = 'technology';
  String _quillStatus = 'published';

  // 投票发布表单
  final TextEditingController _pollQuestionController = TextEditingController();
  final FocusNode _pollFocusNode = FocusNode();
  final List<TextEditingController> _pollOptionControllers = [
    TextEditingController(text: 'poll_option_yes'.tr),
    TextEditingController(text: 'poll_option_no'.tr),
  ];
  String _pollStatus = 'published';

  // 图文说说表单
  final TextEditingController _shortContentController = TextEditingController();
  final TextEditingController _shortTagsController = TextEditingController();
  final FocusNode _shortFocusNode = FocusNode();
  final List<String> _shortImages = [];
  String _shortStatus = 'published';

  final List<String> _categories = [
    'aviation', 'blockchain', 'business', 'car', 'cryptocurrency',
    'data_science', 'education', 'finance', 'gamer', 'style',
    'restaurant', 'trading', 'technology', 'traveler', 'news'
  ];

  final Map<String, String> _categoryNameKeys = {
    'aviation': 'topic_aviation',
    'blockchain': 'topic_blockchain',
    'business': 'topic_business',
    'car': 'topic_car',
    'cryptocurrency': 'topic_cryptocurrency',
    'data_science': 'topic_data_science',
    'education': 'topic_education',
    'finance': 'topic_finance',
    'gamer': 'topic_gamer',
    'style': 'topic_style',
    'restaurant': 'topic_restaurant',
    'trading': 'topic_trading',
    'technology': 'topic_technology',
    'traveler': 'topic_traveler',
    'news': 'topic_news',
    'general': 'topic_general',
  };

  final Map<String, String> _statusNameKeys = {
    'published': 'status_published',
    'draft': 'status_draft',
    'unlisted': 'status_unlisted',
  };

  bool _isPublishing = false;
  final Color _primaryTeal = const Color.fromRGBO(44, 123, 109, 1.0);

  @override
  void initState() {
    super.initState();
    _quillEditorFocusNode.addListener(_onFocusChanged);
    _shortFocusNode.addListener(_onFocusChanged);
    _pollFocusNode.addListener(_onFocusChanged);
  }

  // 🌟 修复：移除插入 Emoji 时程序化更新光标导致的误关闭，支持用户连续多次点选 Emoji
  void _onFocusChanged() {
    // 空实现或仅保留基础状态，不再在获得光标时强行关闭 Emoji 面板
  }

  @override
  void dispose() {
    _quillTitleController.dispose();
    _quillPriceController.dispose();
    _quillController.dispose();
    _quillScrollController.dispose();
    _quillTagsController.dispose();
    _quillEditorFocusNode.dispose();

    _pollQuestionController.dispose();
    _pollFocusNode.dispose();
    for (final controller in _pollOptionControllers) {
      controller.dispose();
    }

    _shortContentController.dispose();
    _shortTagsController.dispose();
    _shortFocusNode.dispose();
    super.dispose();
  }

  // 🌟 无感切换键盘与表情面板：高度恒定锁定，绝不跳动塌陷
  void _toggleEmojiPanel() {
    HapticFeedback.lightImpact();
    if (_isEmojiPanelVisible) {
      setState(() => _isEmojiPanelVisible = false);
      _requestActiveFocus();
    } else {
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => _isEmojiPanelVisible = true);
    }
  }

  void _requestActiveFocus() {
    if (_activeFormIndex == 0) {
      _quillEditorFocusNode.requestFocus();
    } else if (_activeFormIndex == 1) {
      _pollFocusNode.requestFocus();
    } else {
      _shortFocusNode.requestFocus();
    }
  }

  void _insertEmoji(String emoji) {
    if (_activeFormIndex == 0) {
      final index = _quillController.selection.baseOffset;
      final length = _quillController.selection.extentOffset - index;
      final safeIndex = index < 0 ? _quillController.document.length - 1 : index;
      _quillController.replaceText(safeIndex, math.max(0, length), emoji, null);
      _quillController.updateSelection(
        TextSelection.collapsed(offset: safeIndex + emoji.length),
        quill.ChangeSource.local,
      );
    } else if (_activeFormIndex == 2) {
      final text = _shortContentController.text;
      final selection = _shortContentController.selection;
      if (selection.start >= 0 && selection.end >= selection.start) {
        final newText = text.replaceRange(selection.start, selection.end, emoji);
        _shortContentController.text = newText;
        _shortContentController.selection =
            TextSelection.collapsed(offset: selection.start + emoji.length);
      } else {
        _shortContentController.text += emoji;
        _shortContentController.selection = TextSelection.collapsed(
            offset: _shortContentController.text.length);
      }
    } else if (_activeFormIndex == 1) {
      _pollQuestionController.text += emoji;
    }
  }

  void _handleBackspace() {
    HapticFeedback.lightImpact();
    if (_activeFormIndex == 0) {
      _safeDeleteQuillCharacter();
    } else if (_activeFormIndex == 2) {
      _safeDeleteTextCharacter(_shortContentController);
    } else if (_activeFormIndex == 1) {
      _safeDeleteTextCharacter(_pollQuestionController);
    }
  }

  void _safeDeleteTextCharacter(TextEditingController controller) {
    final text = controller.text;
    if (text.isEmpty) return;

    final selection = controller.selection;
    if (selection.isValid && selection.start != selection.end) {
      final start = math.min(selection.start, selection.end);
      final end = math.max(selection.start, selection.end);
      final newText = text.replaceRange(start, end, '');
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: start),
      );
      return;
    }

    final cursorOffset = (selection.isValid && selection.start >= 0)
        ? selection.start
        : text.length;

    if (cursorOffset <= 0) return;

    final textBefore = text.substring(0, cursorOffset);
    final textAfter = text.substring(cursorOffset);

    final charsBefore = textBefore.characters;
    if (charsBefore.isEmpty) return;

    final newTextBefore = charsBefore.skipLast(1).string;
    final newText = newTextBefore + textAfter;

    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newTextBefore.length),
    );
  }

  void _safeDeleteQuillCharacter() {
    final selection = _quillController.selection;
    if (!selection.isValid) return;

    if (selection.start != selection.end) {
      final start = math.min(selection.start, selection.end);
      final length = (selection.end - selection.start).abs();
      _quillController.replaceText(start, length, '', null);
      _quillController.updateSelection(
        TextSelection.collapsed(offset: start),
        quill.ChangeSource.local,
      );
      return;
    }

    final index = selection.baseOffset;
    if (index <= 0) return;

    final plainText = _quillController.document.toPlainText();
    final safeIndex = math.min(index, plainText.length);
    final textBefore = plainText.substring(0, safeIndex);

    final charsBefore = textBefore.characters;
    if (charsBefore.isEmpty) return;

    final lastGrapheme = charsBefore.last;
    final deleteLength = lastGrapheme.length;
    final startDeleteIndex = index - deleteLength;

    if (startDeleteIndex >= 0) {
      _quillController.replaceText(startDeleteIndex, deleteLength, '', null);
      _quillController.updateSelection(
        TextSelection.collapsed(offset: startDeleteIndex),
        quill.ChangeSource.local,
      );
    }
  }

  void _insertHashtag() {
    HapticFeedback.lightImpact();
    if (_activeFormIndex == 0) {
      final index = _quillController.selection.baseOffset;
      final safeIndex = index < 0 ? _quillController.document.length - 1 : index;
      _quillController.replaceText(safeIndex, 0, '#', null);
      _quillController.updateSelection(
        TextSelection.collapsed(offset: safeIndex + 1),
        quill.ChangeSource.local,
      );
    } else if (_activeFormIndex == 2) {
      _shortContentController.text += '#';
    }
  }

  void _insertNewlineAndAutoScroll() {
    HapticFeedback.lightImpact();
    if (_activeFormIndex == 0) {
      final index = _quillController.selection.baseOffset;
      final safeIndex = index < 0 ? _quillController.document.length - 1 : index;
      _quillController.replaceText(safeIndex, 0, '\n', null);
      _quillController.updateSelection(
        TextSelection.collapsed(offset: safeIndex + 1),
        quill.ChangeSource.local,
      );
      Future.delayed(const Duration(milliseconds: 60), () {
        if (_quillScrollController.hasClients) {
          _quillScrollController.animateTo(
            _quillScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
          );
        }
      });
    } else if (_activeFormIndex == 2) {
      _shortContentController.text += '\n';
    }
  }

  void _unfocusEditor() {
    HapticFeedback.lightImpact();
    FocusScope.of(context).unfocus();
    setState(() => _isEmojiPanelVisible = false);
  }

  void _insertDivider() {
    var index = _quillController.selection.baseOffset;
    final length = math.max(0, _quillController.selection.extentOffset - index);
    if (index < 0) index = _quillController.document.length - 1;

    bool prependNewline = false;
    if (index > 0) {
      final plainText = _quillController.document.toPlainText();
      if (index - 1 < plainText.length && plainText[index - 1] != '\n') {
        prependNewline = true;
      }
    }

    if (prependNewline) {
      _quillController.replaceText(index, length, '\n', null);
      index++;
    }
    _quillController.replaceText(
        index, length, quill.BlockEmbed.custom(const DividerBlockEmbed()), null);
    _quillController.replaceText(index + 1, 0, '\n', null);
    _quillController.updateSelection(
        TextSelection.collapsed(offset: index + 2), quill.ChangeSource.local);
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final xFile =
    await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (xFile == null) return;

    if (!mounted) return;
    Fluttertoast.showToast(msg: 'uploading_local_image'.tr);

    final url = await ApiService.uploadImage(File(xFile.path));
    if (url != null) {
      if (_activeFormIndex == 0) {
        _insertImageToEditor(url);
      } else {
        setState(() {
          _shortImages.add(url);
        });
      }
    } else {
      Fluttertoast.showToast(msg: 'image_upload_failed'.tr);
    }
  }

  void _insertImageToEditor(String url) {
    var index = _quillController.selection.baseOffset;
    final length = math.max(0, _quillController.selection.extentOffset - index);
    if (index < 0) index = _quillController.document.length - 1;
    _quillController.replaceText(index, length, quill.BlockEmbed.image(url), null);
    _quillController.replaceText(index + 1, 0, '\n', null);
    _quillController.updateSelection(
        TextSelection.collapsed(offset: index + 2), quill.ChangeSource.local);
  }

  void _pickGif() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                child: _GifSearchSheet(
                  scrollController: scrollController,
                  onGifSelected: (url) {
                    Navigator.pop(context);
                    if (_activeFormIndex == 0) {
                      _insertImageToEditor(url);
                    } else {
                      setState(() {
                        _shortImages.add(url);
                      });
                    }
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showCategorySelector() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            top: 16,
            bottom: MediaQuery.of(context).padding.bottom + 20,
            left: 20,
            right: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 18),
              Text(
                'select_target_circle'.tr,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 2.3,
                ),
                itemCount: _categories.length,
                itemBuilder: (context, index) {
                  final key = _categories[index];
                  final name = _categoryNameKeys.containsKey(key)
                      ? _categoryNameKeys[key]!.tr
                      : key;
                  final isSelected = _quillCategory == key;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _quillCategory = key);
                      Navigator.pop(context);
                    },
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? _primaryTeal.withOpacity(0.1)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? _primaryTeal : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        name,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                          color:
                          isSelected ? _primaryTeal : const Color(0xFF334155),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showStatusSelector() {
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
            bottom: MediaQuery.of(context).padding.bottom + 24,
            left: 24,
            right: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 20),
              Text(
                'set_publish_status'.tr,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 14),
              ..._statusNameKeys.entries.map((entry) {
                final currentStatus = _activeFormIndex == 0
                    ? _quillStatus
                    : (_activeFormIndex == 1 ? _pollStatus : _shortStatus);
                final isSelected = currentStatus == entry.key;
                return ListTile(
                  title: Text(
                    entry.value.tr,
                    style: TextStyle(
                      color: isSelected ? _primaryTeal : const Color(0xFF1E293B),
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                  trailing: isSelected
                      ? Icon(Icons.check_circle_rounded,
                      color: _primaryTeal, size: 20)
                      : null,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  onTap: () {
                    setState(() {
                      if (_activeFormIndex == 0) {
                        _quillStatus = entry.key;
                      } else if (_activeFormIndex == 1) {
                        _pollStatus = entry.key;
                      } else {
                        _shortStatus = entry.key;
                      }
                    });
                    Navigator.pop(context);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  void _toggleAttribute(quill.Attribute attribute) {
    final style = _quillController.getSelectionStyle();
    final currentAttr = style.attributes[attribute.key];
    if (currentAttr != null && currentAttr.value == attribute.value) {
      _quillController.formatSelection(quill.Attribute.clone(attribute, null));
    } else {
      _quillController.formatSelection(attribute);
    }
  }

  String extractPureText(quill.Document document) {
    final buffer = StringBuffer();
    for (final op in document.toDelta().toList()) {
      if (op.isInsert && op.data is String) {
        buffer.write(op.data);
      }
    }
    return buffer.toString().replaceAll(RegExp(r'\n+'), '\n').trim();
  }

  void _handlePublishSubmit() {
    FocusScope.of(context).unfocus();
    setState(() => _isEmojiPanelVisible = false);

    if (_activeFormIndex == 0) {
      _submitQuill();
    } else if (_activeFormIndex == 1) {
      _submitPoll();
    } else if (_activeFormIndex == 2) {
      _submitShort();
    }
  }

  Future<bool> _showExitConfirmDialog() async {
    final bool hasContent = _quillTitleController.text.isNotEmpty ||
        _quillController.document.length > 1 ||
        _shortContentController.text.isNotEmpty ||
        _shortImages.isNotEmpty ||
        _pollQuestionController.text.isNotEmpty;

    if (!_isUploadingVideo && !hasContent && !_isPublishing) {
      return true;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            _isUploadingVideo ? '视频正在上传' : '放弃本次编辑？',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          content: Text(
            _isUploadingVideo
                ? '视频正在压缩上传中，此时退出将中断上传任务，确定要退出吗？'
                : '当前内容尚未发布，退出后未保存的内容将会丢失。',
            style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('继续编辑', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('确认退出', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  Future<void> _pickAndUploadVideo() async {
    final picker = ImagePicker();
    final xFile = await picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 10),
    );
    if (xFile == null) return;

    setState(() {
      _isUploadingVideo = true;
      _videoUploadProgress = 0.0;
    });

    try {
      final fileBytes = await File(xFile.path).readAsBytes();

      final response = await HttpClient.instance.postBinary<Map<String, dynamic>>(
        '/api-system/upload-image',
        data: fileBytes,
        queryParameters: {
          'ext': 'mp4',
          'tag': 'quill_article',
        },
        onSendProgress: (int sent, int total) {
          if (total > 0 && mounted) {
            setState(() {
              _videoUploadProgress = sent / total;
            });
          }
        },
        sendTimeout: const Duration(minutes: 5),
        receiveTimeout: const Duration(minutes: 5),
      );

      final datas = response.datas;
      if (response.isSuccess && datas != null) {
        final String videoId = datas['id']?.toString() ?? '';
        final String videoUrl = datas['url']?.toString() ?? '';
        final String thumbnailUrl = datas['thumbnail_url']?.toString() ?? '';
        final user = UserController.to.user.value;

        var index = _quillController.selection.baseOffset;
        final length = math.max(0, _quillController.selection.extentOffset - index);
        if (index < 0) index = _quillController.document.length - 1;

        final videoData = {
          'id': videoId,
          'video_url': videoUrl,
          'thumbnail_url': thumbnailUrl,
          'caption': '',
          'author_id': user?.id ?? '',
          'author_nickname': user?.nickname ?? '创作者',
          'author_avatar': user?.avatar ?? '',
          'duration_sec': 0,
        };

        _quillController.replaceText(
          index,
          length,
          quill.BlockEmbed.custom(VideoBlockEmbed(videoData)),
          null,
        );
        _quillController.replaceText(index + 1, 0, '\n', null);
        _quillController.updateSelection(
          TextSelection.collapsed(offset: index + 2),
          quill.ChangeSource.local,
        );

        Fluttertoast.showToast(msg: "视频上传成功，点击视频边框可删除，点击底部可添加注解！");
      }
    } catch (e) {
      Fluttertoast.showToast(msg: "视频上传故障: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingVideo = false;
          _videoUploadProgress = 0.0;
        });
      }
    }
  }

  Future<void> _submitQuill() async {
    if (_quillTitleController.text.trim().isEmpty) {
      Fluttertoast.showToast(msg: 'please_enter_title'.tr);
      return;
    }

    final delta = _quillController.document.toDelta();
    final jsonContent = jsonEncode(delta.toJson());
    final plainText = extractPureText(_quillController.document);

    String? firstImage;
    for (final op in delta.toList()) {
      if (op.isInsert && op.data is Map) {
        final map = op.data as Map;
        if (map.containsKey('image')) {
          firstImage = map['image'].toString();
          break;
        }
      }
    }

    final priceRaw = _quillPriceController.text.trim();
    double priceValue = 0.0;
    if (priceRaw.isNotEmpty) {
      priceValue = double.tryParse(priceRaw) ?? 0.0;
      if (priceValue > 50.0) priceValue = 50.0;
      if (priceValue < 0.0) priceValue = 0.0;
    }
    final formattedPrice = priceValue.toStringAsFixed(2);

    _submitPost(
      postType: 'quill',
      title: _quillTitleController.text.trim(),
      content: jsonContent,
      plainText: plainText,
      tags: _parseTags(_quillTagsController.text),
      category: _quillCategory,
      thumbnail: firstImage ?? '',
      status: _quillStatus,
      price: formattedPrice,
    );
  }

  Future<void> _submitPoll() async {
    if (_pollQuestionController.text.trim().isEmpty) {
      Fluttertoast.showToast(msg: 'please_enter_poll_question'.tr);
      return;
    }
    final List<String> options = [];
    for (final c in _pollOptionControllers) {
      if (c.text.trim().isNotEmpty) {
        options.add(c.text.trim());
      }
    }
    if (options.length < 2) {
      Fluttertoast.showToast(msg: 'need_two_poll_options'.tr);
      return;
    }
    _submitPost(
      postType: 'poll',
      title: _pollQuestionController.text.trim(),
      content: 'poll_invite_text'
          .trParams({'question': _pollQuestionController.text.trim()}),
      plainText: 'poll_invite_text'
          .trParams({'question': _pollQuestionController.text.trim()}),
      pollQuestion: _pollQuestionController.text.trim(),
      pollOptions: options,
      category: 'news',
      status: _pollStatus,
    );
  }

  Future<void> _submitShort() async {
    if (_shortContentController.text.trim().isEmpty && _shortImages.isEmpty) {
      Fluttertoast.showToast(msg: 'say_something_or_image'.tr);
      return;
    }
    _submitPost(
      postType: 'short_post',
      title: '',
      content: _shortContentController.text.trim(),
      plainText: _shortContentController.text.trim(),
      tags: _parseTags(_shortTagsController.text),
      category: 'general',
      status: _shortStatus,
      thumbnail: _shortImages.isNotEmpty ? _shortImages.first : '',
      images: _shortImages,
    );
  }

  List<String> _parseTags(String raw) {
    if (raw.isEmpty) return [];
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Future<void> _submitPost({
    required String postType,
    String title = '',
    required dynamic content,
    String plainText = '',
    List<String> tags = const [],
    String category = 'general',
    String thumbnail = '',
    required String status,
    String? pollQuestion,
    List<String>? pollOptions,
    List<String>? images,
    String? price,
  }) async {
    setState(() => _isPublishing = true);
    try {
      final body = {
        'post_type': postType,
        'title': title,
        'content': content,
        'plain_text': plainText,
        'tags': tags,
        'category': category,
        'thumbnail': thumbnail,
        'status': status,
        if (pollQuestion != null) 'poll_question': pollQuestion,
        if (pollOptions != null) 'poll_options': pollOptions,
        if (images != null) 'images': images,
        if (price != null && price.isNotEmpty) 'price': price,
      };

      final res = await HttpClient.instance.post('/api-posts', data: body);
      if (res.respCode == 0) {
        Fluttertoast.showToast(msg: 'publish_success'.tr);
        Get.back(result: true);
      }
    } catch (e) {
      if (e is ApiException) {
        Fluttertoast.showToast(msg: e.message);
      } else {
        Fluttertoast.showToast(msg: 'publish_error'.tr);
      }
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeStatusKey = _activeFormIndex == 0
        ? _quillStatus
        : (_activeFormIndex == 1 ? _pollStatus : _shortStatus);

    // 🌟 1. 精准捕获键盘真实弹起高度并持久化锁定
    final double currentKeyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    if (currentKeyboardHeight > 180.0 && currentKeyboardHeight > _stableKeyboardHeight) {
      _stableKeyboardHeight = currentKeyboardHeight;
    }

    // 🌟 2. 预设两排紧凑搜索栏高度（搜索框 38px + 内外边距与分割线 + 横向候选条 54px ≈ 112px）
    const double compactSearchHeight = 112.0;

    // 🌟 3. 动态计算底栏高度：
    // - 当展开 Emoji 且键盘弹起（正在搜索 Emoji）时：高度 = 键盘高度 + 112px（刚好露出紧凑的两排搜索条）；
    // - 当展开 Emoji 且键盘收起（正常翻页浏览）时：高度 = _stableKeyboardHeight（完整多行大面板）；
    // - 当关闭 Emoji 时：高度 = currentKeyboardHeight（为文章正文输入法让位）。
    final double bottomPanelHeight = _isEmojiPanelVisible
        ? (currentKeyboardHeight > 180.0
        ? (currentKeyboardHeight + compactSearchHeight)
        : _stableKeyboardHeight)
        : currentKeyboardHeight;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldLeave = await _showExitConfirmDialog();
        if (shouldLeave && context.mounted) {
          Get.back();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        resizeToAvoidBottomInset: false, // 🌟 避免页面双重挤压抽搐
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            onPressed: () async {
              final shouldLeave = await _showExitConfirmDialog();
              if (shouldLeave && context.mounted) {
                Get.back();
              }
            },
            icon: const HugeIcon(
              icon: HugeIcons.strokeRoundedCancel01,
              color: Color(0xFF64748B),
              size: 22.0,
            ),
          ),
          title: Row(
            children: [
              if (_activeFormIndex == 0)
                GestureDetector(
                  onTap: _showCategorySelector,
                  child: Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _primaryTeal.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _categoryNameKeys[_quillCategory]?.tr ?? 'select_topic'.tr,
                          style: TextStyle(
                            fontSize: 12,
                            color: _primaryTeal,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 4),
                        HugeIcon(
                          icon: HugeIcons.strokeRoundedArrowDown01,
                          color: _primaryTeal,
                          size: 12.0,
                        ),
                      ],
                    ),
                  ),
                ),
              const Spacer(),
              GestureDetector(
                onTap: _showStatusSelector,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const HugeIcon(
                        icon: HugeIcons.strokeRoundedView,
                        color: Color(0xFF64748B),
                        size: 12.0,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _statusNameKeys[activeStatusKey]?.tr ?? 'status_published'.tr,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 14.0, left: 6),
              child: ElevatedButton(
                onPressed: _isPublishing ? null : _handlePublishSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryTeal,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _isPublishing
                    ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
                    : Text(
                  'publish'.tr,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              // 视频上传进度提示条
              if (_isUploadingVideo)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: _primaryTeal.withOpacity(0.08),
                    border: Border.all(color: _primaryTeal.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          value: _videoUploadProgress > 0 ? _videoUploadProgress : null,
                          color: _primaryTeal,
                          strokeWidth: 2,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _videoUploadProgress < 1.0
                            ? '正在上传视频 (${(_videoUploadProgress * 100).toInt()}%)...'
                            : '已完成传输，云端正在进行智能转码抽帧...',
                        style: TextStyle(
                          fontSize: 12,
                          color: _primaryTeal,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

              // 编辑器主视口
              Expanded(
                child: _isPublishing
                    ? Center(
                  child: CircularProgressIndicator(
                    color: _primaryTeal,
                    strokeWidth: 2.5,
                  ),
                )
                    : _buildActiveFormBody(),
              ),

              // 底部工具条
              _buildBottomActionToolbar(),

              // 🌟 固化高度底栏：无缝嵌入 Emoji 选择器
              SizedBox(
                height: bottomPanelHeight,
                child: _isEmojiPanelVisible
                    ? ModernEmojiPicker(
                  onEmojiSelected: _insertEmoji,
                  onBackspacePressed: _handleBackspace,
                )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveFormBody() {
    switch (_activeFormIndex) {
      case 0:
        return _buildQuillForm();
      case 1:
        return _buildPollForm();
      case 2:
      default:
        return _buildShortForm();
    }
  }

  Widget _buildQuillForm() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 6),
          child: TextField(
            controller: _quillTitleController,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
              letterSpacing: -0.5,
            ),
            decoration: InputDecoration(
              hintText: 'title'.tr,
              hintStyle: const TextStyle(
                color: Color(0xFFCBD5E1),
                fontWeight: FontWeight.w700,
              ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        const Divider(height: 1, color: Color(0xFFF1F5F9)),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 8),
            child: quill.QuillEditor(
              controller: _quillController,
              scrollController: _quillScrollController,
              focusNode: _quillEditorFocusNode,
              config: quill.QuillEditorConfig(
                placeholder: 'share_moment_hint'.tr,
                autoFocus: false,
                checkBoxReadOnly: false,
                padding: EdgeInsets.zero,
                expands: true,
                customStyles: const quill.DefaultStyles(
                  paragraph: quill.DefaultTextBlockStyle(
                    TextStyle(
                      fontSize: 16.5,
                      color: Color(0xFF1E293B),
                      height: 1.65,
                      fontFamily: 'ShantellSans',
                    ),
                    quill.HorizontalSpacing(0, 0),
                    quill.VerticalSpacing(0, 0),
                    quill.VerticalSpacing(0, 0),
                    null,
                  ),
                  placeHolder: quill.DefaultTextBlockStyle(
                    TextStyle(
                      fontSize: 16.5,
                      color: Color(0xFF94A3B8),
                      height: 1.65,
                      fontFamily: 'ShantellSans',
                    ),
                    quill.HorizontalSpacing(0, 0),
                    quill.VerticalSpacing(0, 0),
                    quill.VerticalSpacing(0, 0),
                    null,
                  ),
                ),
                embedBuilders: [
                  DividerEmbedBuilder(),
                  VideoEmbedBuilder(),
                  ...FlutterQuillEmbeds.editorBuilders(),
                ],
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _quillTagsController,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'tags_hint_tech'.tr,
                    hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                    border: InputBorder.none,
                    isDense: true,
                    prefixIcon: const Icon(Icons.tag_rounded, size: 14, color: Color(0xFF94A3B8)),
                    prefixIconConstraints: const BoxConstraints(minWidth: 20),
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 110,
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: TextField(
                  controller: _quillPriceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                  ],
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    hintText: 'price_hint'.tr,
                    hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                    border: InputBorder.none,
                    isDense: true,
                    prefixText: '¥ ',
                    prefixStyle: TextStyle(
                      color: _primaryTeal,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                  onChanged: (val) {
                    final p = double.tryParse(val) ?? 0.0;
                    if (p > 50.0) {
                      _quillPriceController.text = '50.00';
                      Fluttertoast.showToast(msg: 'price_limit_notice'.tr);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPollForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _pollQuestionController,
            focusNode: _pollFocusNode,
            maxLines: 3,
            minLines: 1,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            decoration: InputDecoration(
              hintText: 'poll_question_hint'.tr,
              hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 15),
              border: InputBorder.none,
            ),
          ),
          const Divider(height: 20, color: Color(0xFFF1F5F9)),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _pollOptionControllers.length + 1,
            itemBuilder: (context, index) {
              if (index == _pollOptionControllers.length) {
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: OutlinedButton.icon(
                    onPressed: () {
                      if (_pollOptionControllers.length >= 6) {
                        Fluttertoast.showToast(msg: '最多支持 6 个选项');
                        return;
                      }
                      setState(() {
                        _pollOptionControllers.add(TextEditingController());
                      });
                    },
                    icon: HugeIcon(
                      icon: HugeIcons.strokeRoundedPlusSignCircle,
                      color: _primaryTeal,
                      size: 16.0,
                    ),
                    label: Text(
                      'add_poll_option'.tr,
                      style: TextStyle(
                        color: _primaryTeal,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: _primaryTeal.withOpacity(0.3)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 10.0),
                child: Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _primaryTeal.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          color: _primaryTeal,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: TextField(
                          controller: _pollOptionControllers[index],
                          style: const TextStyle(fontSize: 13.5),
                          decoration: InputDecoration(
                            hintText: 'poll_option_hint'.tr,
                            hintStyle: const TextStyle(
                                fontSize: 12, color: Color(0xFF94A3B8)),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                          ),
                        ),
                      ),
                    ),
                    if (_pollOptionControllers.length > 2) ...[
                      const SizedBox(width: 6),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _pollOptionControllers.removeAt(index);
                          });
                        },
                        icon: const Icon(Icons.remove_circle_outline,
                            color: Colors.redAccent, size: 20),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildShortForm() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _shortContentController,
                  focusNode: _shortFocusNode,
                  maxLines: 8,
                  minLines: 3,
                  style: const TextStyle(
                    fontSize: 16.5,
                    height: 1.6,
                    color: Color(0xFF0F172A),
                  ),
                  decoration: InputDecoration(
                    hintText: 'share_moment_hint'.tr,
                    hintStyle: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 15,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(height: 12),
                if (_shortImages.isNotEmpty)
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      ..._shortImages.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final url = entry.value;
                        return Stack(
                          alignment: Alignment.topRight,
                          children: [
                            Container(
                              width: 86,
                              height: 86,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Image.network(url, fit: BoxFit.cover),
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _shortImages.removeAt(idx);
                                });
                              },
                              child: Container(
                                margin: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                padding: const EdgeInsets.all(3),
                                child: const Icon(Icons.close,
                                    size: 11, color: Colors.white),
                              ),
                            ),
                          ],
                        );
                      }),
                      if (_shortImages.length < 9)
                        GestureDetector(
                          onTap: _pickImage,
                          child: Container(
                            width: 86,
                            height: 86,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                  style: BorderStyle.solid),
                            ),
                            child: const Icon(
                              Icons.add_photo_alternate_outlined,
                              color: Color(0xFF94A3B8),
                              size: 24,
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
          ),
          child: Row(
            children: [
              const Icon(Icons.tag_rounded, size: 16, color: Color(0xFF94A3B8)),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _shortTagsController,
                  style: const TextStyle(fontSize: 12.5),
                  decoration: InputDecoration(
                    hintText: 'tags_hint_news'.tr,
                    hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomActionToolbar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
        border: const Border(top: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4),
            child: Row(
              children: [
                if (_activeFormIndex == 0)
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: '插入 #',
                            icon: const HugeIcon(
                              icon: HugeIcons.strokeRoundedHashtag,
                              color: Color(0xFF64748B),
                              size: 19.0,
                            ),
                            onPressed: _insertHashtag,
                          ),
                          IconButton(
                            tooltip: '换行并保持视野',
                            icon: const HugeIcon(
                              icon: HugeIcons.strokeRoundedSquareArrowMoveDownLeft,
                              color: Color(0xFF64748B),
                              size: 19.0,
                            ),
                            onPressed: _insertNewlineAndAutoScroll,
                          ),
                          IconButton(
                            tooltip: '取消焦点',
                            icon: const HugeIcon(
                              icon: HugeIcons.strokeRoundedCancelCircle,
                              color: Color(0xFF64748B),
                              size: 19.0,
                            ),
                            onPressed: _unfocusEditor,
                          ),
                          _vDivider(),
                          _buildFormatBtn(
                            icon: HugeIcons.strokeRoundedTextBold,
                            attr: quill.Attribute.bold,
                          ),
                          _buildFormatBtn(
                            icon: HugeIcons.strokeRoundedTextItalic,
                            attr: quill.Attribute.italic,
                          ),
                          _buildFormatBtn(
                            icon: HugeIcons.strokeRoundedHeading01,
                            attr: quill.Attribute.h1,
                          ),
                          _buildFormatBtn(
                            icon: HugeIcons.strokeRoundedHeading02,
                            attr: quill.Attribute.h2,
                          ),
                          _buildFormatBtn(
                            icon: HugeIcons.strokeRoundedQuoteUp,
                            attr: quill.Attribute.blockQuote,
                          ),
                          _buildFormatBtn(
                            icon: HugeIcons.strokeRoundedLeftToRightListBullet,
                            attr: quill.Attribute.ul,
                          ),
                          _buildFormatBtn(
                            icon: HugeIcons.strokeRoundedLeftToRightListNumber,
                            attr: quill.Attribute.ol,
                          ),
                          _buildFormatBtn(
                            icon: HugeIcons.strokeRoundedTextAlignCenter,
                            attr: quill.Attribute.centerAlignment,
                          ),
                          _vDivider(),
                          IconButton(
                            tooltip: '插入视频',
                            icon: const HugeIcon(
                              icon: HugeIcons.strokeRoundedVideo01,
                              color: Color(0xFF64748B),
                              size: 19.0,
                            ),
                            onPressed: _pickAndUploadVideo,
                          ),
                          IconButton(
                            tooltip: '插入图片',
                            icon: const HugeIcon(
                              icon: HugeIcons.strokeRoundedImage01,
                              color: Color(0xFF64748B),
                              size: 19.0,
                            ),
                            onPressed: _pickImage,
                          ),
                          IconButton(
                            tooltip: '插入 GIF',
                            icon: const HugeIcon(
                              icon: HugeIcons.strokeRoundedGif01,
                              color: Color(0xFF64748B),
                              size: 19.0,
                            ),
                            onPressed: _pickGif,
                          ),
                          IconButton(
                            tooltip: '分割线',
                            icon: const HugeIcon(
                              icon: HugeIcons.strokeRoundedMenu04,
                              color: Color(0xFF64748B),
                              size: 19.0,
                            ),
                            onPressed: _insertDivider,
                          ),
                        ],
                      ),
                    ),
                  )
                else if (_activeFormIndex == 2) ...[
                  IconButton(
                    tooltip: '添加图片',
                    icon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedImage01,
                      color: Color(0xFF64748B),
                      size: 20.0,
                    ),
                    onPressed: _pickImage,
                  ),
                  IconButton(
                    tooltip: '添加 GIF',
                    icon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedGif01,
                      color: Color(0xFF64748B),
                      size: 20.0,
                    ),
                    onPressed: _pickGif,
                  ),
                  IconButton(
                    tooltip: '插入 #',
                    icon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedHashtag,
                      color: Color(0xFF64748B),
                      size: 20.0,
                    ),
                    onPressed: _insertHashtag,
                  ),
                  const Spacer(),
                ] else ...[
                  const Spacer(),
                ],

                // 表情面板呼出键
                IconButton(
                  tooltip: '表情符号',
                  icon: HugeIcon(
                    icon: _isEmojiPanelVisible
                        ? HugeIcons.strokeRoundedKeyboard
                        : HugeIcons.strokeRoundedInLove,
                    color: _isEmojiPanelVisible
                        ? _primaryTeal
                        : const Color(0xFF64748B),
                    size: 21.0,
                  ),
                  onPressed: _toggleEmojiPanel,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),

          // 模式切换胶囊栏
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildPillButton(
                  index: 2,
                  icon: HugeIcons.strokeRoundedPencilEdit02,
                  text: 'tab_moment'.tr,
                  bgColor: const Color(0xFFE0F2FE),
                  textColor: const Color(0xFF0369A1),
                ),
                const SizedBox(width: 8),
                _buildPillButton(
                  index: 0,
                  icon: HugeIcons.strokeRoundedNote01,
                  text: 'tab_article'.tr,
                  bgColor: const Color(0xFFFEF3C7),
                  textColor: const Color(0xFFB45309),
                ),
                const SizedBox(width: 8),
                _buildPillButton(
                  index: 1,
                  icon: HugeIcons.strokeRoundedChatQuestion,
                  text: 'tab_ask'.tr,
                  bgColor: const Color(0xFFDCFCE7),
                  textColor: const Color(0xFF15803D),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormatBtn({
    required dynamic icon,
    required quill.Attribute attr,
  }) {
    return ListenableBuilder(
      listenable: _quillController,
      builder: (context, _) {
        final style = _quillController.getSelectionStyle();
        final isApplied = style.attributes.containsKey(attr.key) &&
            style.attributes[attr.key]!.value == attr.value;
        return IconButton(
          icon: HugeIcon(
            icon: icon,
            color: isApplied ? _primaryTeal : const Color(0xFF64748B),
            size: 19,
          ),
          onPressed: () => _toggleAttribute(attr),
        );
      },
    );
  }

  Widget _vDivider() => const VerticalDivider(
    indent: 14,
    endIndent: 14,
    width: 16,
    color: Color(0xFFE2E8F0),
  );

  Widget _buildPillButton({
    required int index,
    required dynamic icon,
    required String text,
    required Color bgColor,
    required Color textColor,
  }) {
    final isSelected = _activeFormIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() {
            _activeFormIndex = index;
            _isEmojiPanelVisible = false;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? bgColor : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? textColor.withOpacity(0.35)
                  : const Color(0xFFE2E8F0),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              HugeIcon(
                icon: icon,
                color: isSelected ? textColor : const Color(0xFF64748B),
                size: 15,
              ),
              const SizedBox(width: 5),
              Text(
                text,
                style: TextStyle(
                  color: isSelected ? textColor : const Color(0xFF475569),
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GifSearchSheet extends StatefulWidget {
  final ScrollController scrollController;
  final Function(String url) onGifSelected;

  const _GifSearchSheet({
    required this.scrollController,
    required this.onGifSelected,
  });

  @override
  State<_GifSearchSheet> createState() => _GifSearchSheetState();
}

class _GifSearchSheetState extends State<_GifSearchSheet> {
  final TextEditingController _searchC = TextEditingController();
  List<String> _gifs = [];
  bool _isLoading = false;
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _fetchGifs('');
  }

  @override
  void dispose() {
    _searchC.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _fetchGifs(String query) async {
    _searchFocus.unfocus();
    setState(() => _isLoading = true);
    final gifs = await ApiService.fetchIntercomGifs(query: query);
    if (mounted) {
      setState(() {
        _gifs = gifs;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          color: Colors.white,
          child: Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          child: TextField(
            controller: _searchC,
            focusNode: _searchFocus,
            textInputAction: TextInputAction.search,
            cursorColor: const Color(0xFF2C7B6D),
            style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
            onSubmitted: (value) => _fetchGifs(value),
            decoration: InputDecoration(
              hintText: 'search_gif_hint'.tr,
              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
              prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
              filled: true,
              fillColor: const Color(0xFFF1F5F9),
              contentPadding:
              const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward_rounded,
                    color: Color(0xFF2C7B6D), size: 20),
                onPressed: () => _fetchGifs(_searchC.text),
              ),
            ),
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(
            child: CircularProgressIndicator(
                strokeWidth: 2.5, color: Color(0xFF2C7B6D)),
          )
              : _gifs.isEmpty
              ? Center(
            child: Text('no_gif_found'.tr,
                style: TextStyle(color: Colors.grey[400])),
          )
              : GridView.builder(
            controller: widget.scrollController,
            padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            gridDelegate:
            const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.0,
            ),
            itemCount: _gifs.length,
            itemBuilder: (context, index) {
              final url = _gifs[index];
              return Material(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => widget.onGifSelected(url),
                  child: Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, err, stack) => const Center(
                      child: Icon(Icons.broken_image_rounded,
                          color: Colors.grey, size: 28),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
