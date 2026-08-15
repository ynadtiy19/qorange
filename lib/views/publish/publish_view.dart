// GET /api-posts & POST /api-posts (Zhihu风格极简 bleed-to-edge 完全体发布流)
import 'dart:convert';
import 'dart:io';
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
import '../../widgets/modern_emoji_picker.dart';
import '../../widgets/quill_custom_divider.dart';
import '../../services/api_service.dart';

class PublishView extends StatefulWidget {
  const PublishView({super.key});

  @override
  State<PublishView> createState() => _PublishViewState();
}

class _PublishViewState extends State<PublishView> with SingleTickerProviderStateMixin {
  int _activeFormIndex = 2; // 0: 深度文章, 1: 投票发布, 2: 图文说说 (默认聚焦于图文说说写想法)


  // 🌟 追加：Quill 深度文章特有的付费价格控制器
  final TextEditingController _quillPriceController = TextEditingController();

  // Quill 深度文章表单
  final TextEditingController _quillTitleController = TextEditingController();
  final quill.QuillController _quillController = quill.QuillController.basic();
  final ScrollController _editorScrollC = ScrollController();
  final TextEditingController _quillTagsController = TextEditingController();
  String _quillCategory = "technology";
  String _quillStatus = "published";

  // 投票发布表单
  final TextEditingController _pollQuestionController = TextEditingController();
  final List<TextEditingController> _pollOptionControllers = [
    TextEditingController(text: 'poll_option_yes'.tr),
    TextEditingController(text: 'poll_option_no'.tr),
  ];
  String _pollStatus = "published";

  // 图文说说多图表单
  final TextEditingController _shortContentController = TextEditingController();
  final TextEditingController _shortTagsController = TextEditingController();
  final List<String> _shortImages = [];
  String _shortStatus = "published";

  final List<String> _categories = [
    'aviation', 'blockchain', 'business', 'car', 'cryptocurrency',
    'data_science', 'education', 'finance', 'gamer', 'style',
    'restaurant', 'trading', 'technology', 'traveler', 'news'
  ];

  // 目标领域映射：值为多语言词条 key，展示时调用 .tr 取当前语言文案
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

  // 发布状态映射：值同样为多语言词条 key
  final Map<String, String> _statusNameKeys = {
    'published': 'status_published',
    'draft': 'status_draft',
    'unlisted': 'status_unlisted',
  };

  bool _isPublishing = false;

  final FocusNode _editorFocusNode = FocusNode();

  @override
  void dispose() {
    _quillTitleController.dispose();
    _quillController.dispose();
    _editorScrollC.dispose();
    _quillTagsController.dispose();
    _pollQuestionController.dispose();
    for (var controller in _pollOptionControllers) {
      controller.dispose();
    }
    _shortContentController.dispose();
    _shortTagsController.dispose();
    super.dispose();
  }

  void _openEmojiPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return ModernEmojiPicker(
          onEmojiSelected: (emoji) {
            Navigator.pop(context);
            _insertEmoji(emoji);
          },
        );
      },
    );
  }

  void _insertEmoji(String emoji) {
    if (_activeFormIndex == 0) {
      // 👉 Quill 编辑器
      final index = _quillController.selection.baseOffset;
      final length = _quillController.selection.extentOffset - index;

      _quillController.replaceText(index, length, emoji, null);
      _quillController.updateSelection(
        TextSelection.collapsed(offset: index + emoji.length),
        quill.ChangeSource.local,
      );
    } else if (_activeFormIndex == 2) {
      // 👉 short content
      final text = _shortContentController.text;
      final selection = _shortContentController.selection;

      final newText = text.replaceRange(
        selection.start,
        selection.end,
        emoji,
      );

      _shortContentController.text = newText;
      _shortContentController.selection = TextSelection.collapsed(
        offset: selection.start + emoji.length,
      );
    } else if (_activeFormIndex == 1) {
      // 👉 poll question
      final text = _pollQuestionController.text;
      _pollQuestionController.text = text + emoji;
    }
  }

  void _insertDivider() {
    var index = _quillController.selection.baseOffset;
    final length = _quillController.selection.extentOffset - index;
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
      _quillController.replaceText(index, 0, quill.BlockEmbed.custom(const DividerBlockEmbed()), null);
      _quillController.replaceText(index + 1, 0, '\n', null);
      _quillController.updateSelection(TextSelection.collapsed(offset: index + 2), quill.ChangeSource.local);
    } else {
      _quillController.replaceText(index, length, quill.BlockEmbed.custom(const DividerBlockEmbed()), null);
      _quillController.replaceText(index + 1, 0, '\n', null);
      _quillController.updateSelection(TextSelection.collapsed(offset: index + 2), quill.ChangeSource.local);
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
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
    final index = _quillController.selection.baseOffset;
    final length = _quillController.selection.extentOffset - index;
    _quillController.replaceText(index, length, quill.BlockEmbed.image(url), null);
    _quillController.replaceText(index + 1, 0, '\n', null);
    _quillController.updateSelection(TextSelection.collapsed(offset: index + 2), quill.ChangeSource.local);
  }

  void _pickGif() {
    showModalBottomSheet(
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

  // 升起精美的目标领域底层交互选择器代替下拉菜单
  void _showCategorySelector() {
    showModalBottomSheet(
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
            bottom: MediaQuery.of(context).padding.bottom + 24,
            left: 20,
            right: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 20),
              Text('select_target_circle'.tr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
              const SizedBox(height: 20),
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
                  final name = _categoryNameKeys.containsKey(key) ? _categoryNameKeys[key]!.tr : key;
                  final isSelected = _quillCategory == key;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _quillCategory = key);
                      Navigator.pop(context);
                    },
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFFE3F2FD) : const Color(0xFFF5F7FA),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? const Color(0xFF0066FF) : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        name,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? const Color(0xFF0066FF) : Colors.black87,
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

  // 状态发布选择器弹窗列表
  void _showStatusSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.only(top: 16, bottom: 40, left: 24, right: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 24),
              Text('set_publish_status'.tr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
              const SizedBox(height: 16),
              ..._statusNameKeys.entries.map((entry) {
                final currentStatus = _activeFormIndex == 0 ? _quillStatus : (_activeFormIndex == 1 ? _pollStatus : _shortStatus);
                final isSelected = currentStatus == entry.key;
                return ListTile(
                  title: Text(entry.value.tr, style: TextStyle(color: isSelected ? const Color(0xFF0066FF) : Colors.black87, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                  trailing: isSelected ? const Icon(Icons.check, color: Color(0xFF0066FF)) : null,
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
              }).toList(),
            ],
          ),
        );
      },
    );
  }

  void _showShortImageSourcePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.only(top: 12, bottom: 30, left: 24, right: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 24),
              Text('add_image'.tr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined, color: Colors.black87),
                title: Text('pick_from_album'.tr),
                onTap: () {
                  Navigator.pop(context);
                  _pickShortLocalImage();
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.gif_box_outlined, color: Colors.black87),
                title: Text('pick_fun_gif'.tr),
                onTap: () {
                  Navigator.pop(context);
                  _pickShortGifImage();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickShortLocalImage() async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (xFile == null) return;

    Fluttertoast.showToast(msg: 'uploading_moment_image'.tr);
    final url = await ApiService.uploadImage(File(xFile.path));
    if (url != null) {
      setState(() {
        _shortImages.add(url);
      });
      Fluttertoast.showToast(msg: 'image_added'.tr);
    } else {
      Fluttertoast.showToast(msg: 'image_upload_failed'.tr);
    }
  }

  void _pickShortGifImage() {
    showModalBottomSheet(
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
                    setState(() {
                      _shortImages.add(url);
                    });
                    Fluttertoast.showToast(msg: 'gif_added'.tr);
                  },
                ),
              ),
            );
          },
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
    if (_activeFormIndex == 0) {
      _submitQuill();
    } else if (_activeFormIndex == 1) {
      _submitPoll();
    } else if (_activeFormIndex == 2) {
      _submitShort();
    }
  }

  // 1. 📂 quill（深度富文本文章）参数构建
  Future<void> _submitQuill() async {
    if (_quillTitleController.text.trim().isEmpty) {
      Fluttertoast.showToast(msg: 'please_enter_title'.tr);
      return;
    }

    final delta = _quillController.document.toDelta();
    final jsonContent = jsonEncode(delta.toJson());
    final plainText = extractPureText(_quillController.document);

    // 扫描 Delta，抓取其中第一张含有 "image" 属性的 Cloudinary 链接
    String? firstImage;
    for (var op in delta.toList()) {
      if (op.isInsert && op.data is Map) {
        final map = op.data as Map;
        if (map.containsKey('image')) {
          firstImage = map['image'].toString();
          break;
        }
      }
    }

    // 🌟 自动格式化机制：提交时强制限制合法范围并自动保留两位小数点
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
      category: _quillCategory, // 用户选中的专业领域分类
      thumbnail: firstImage ?? '', // 如果没有插图，传空字符串
      status: _quillStatus,
      price: formattedPrice, // 🌟 传入文章付费价格参数
    );
  }

  // 3. 📂 poll（学术/日常投票）参数构建
  Future<void> _submitPoll() async {
    if (_pollQuestionController.text.isEmpty) {
      Fluttertoast.showToast(msg: 'please_enter_poll_question'.tr);
      return;
    }
    final List<String> options = [];
    for (var c in _pollOptionControllers) {
      if (c.text.isNotEmpty) {
        options.add(c.text);
      }
    }
    if (options.length < 2) {
      Fluttertoast.showToast(msg: 'need_two_poll_options'.tr);
      return;
    }
    _submitPost(
      postType: 'poll',
      title: _pollQuestionController.text, // 用户书写的投票议题作为 title
      content: 'poll_invite_text'.trParams({'question': _pollQuestionController.text}), // 固定拼装提示文本
      plainText: 'poll_invite_text'.trParams({'question': _pollQuestionController.text}),
      pollQuestion: _pollQuestionController.text, // poll_question 与 title 一致
      pollOptions: options, // 选项数组
      category: 'news', // 固定归类为 "news"
      status: _pollStatus,
    );
  }

  // 2. 📂 short_post（图文说说）参数构建
  Future<void> _submitShort() async {
    if (_shortContentController.text.isEmpty && _shortImages.isEmpty) {
      Fluttertoast.showToast(msg: 'say_something_or_image'.tr);
      return;
    }
    _submitPost(
      postType: 'short_post',
      title: '', // 说说无标题框，固定传空字符串 ""
      content: _shortContentController.text, // 说说正文内容
      plainText: _shortContentController.text,
      tags: _parseTags(_shortTagsController.text),
      category: 'general', // 固定归类为 "general"
      status: _shortStatus,
      thumbnail: _shortImages.isNotEmpty ? _shortImages.first : '', // 如果 images 不为空，抓取 images[0] 作为缩略图
      images: _shortImages, // 高清大图 URL 数组
    );
  }

  List<String> _parseTags(String raw) {
    if (raw.isEmpty) return [];
    return raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
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
    String? price, // 🌟 新增支持价格
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
        if (price != null && price.isNotEmpty) 'price': price, // 🌟 仅在价格非空时提交
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
      setState(() => _isPublishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Get.back(),
          icon: const HugeIcon(icon: HugeIcons.strokeRoundedCancel01, color: Colors.grey, size: 24.0),
        ),
        title: Row(
          children: [
            if (_activeFormIndex == 0)
              GestureDetector(
                onTap: _showCategorySelector,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F7FA),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _categoryNameKeys[_quillCategory]?.tr ?? 'select_topic'.tr,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black87,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const HugeIcon(
                        icon: HugeIcons.strokeRoundedArrowDown01,
                        color: Colors.grey,
                        size: 12.0,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _handlePublishSubmit,
            child: Text('publish'.tr, style: TextStyle(color: Color(0xFF0066FF), fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isPublishing
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF0066FF)))
                : _buildActiveFormBody(),
          ),
          _buildBottomActionToolbar(),
        ],
      ),
    );
  }

  Widget _buildActiveFormBody() {
    if (_activeFormIndex == 0) {
      return _buildQuillForm();
    } else if (_activeFormIndex == 1) {
      return _buildPollForm();
    } else {
      return _buildShortForm();
    }
  }

  // 1. 深度文章：无容器 Padding 阻碍，两端完全贴合设计
  Widget _buildQuillForm() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12),
                child: TextField(
                  controller: _quillTitleController,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1F2937), letterSpacing: -0.5),
                  decoration: InputDecoration(
                    hintText: 'title'.tr,
                    hintStyle: TextStyle(color: Color(0xFFD1D5DB)),
                    border: InputBorder.none,
                  ),
                ),
              ),
              const Divider(height: 1, color: Color(0xFFF3F4F6)),
              // 🌟 重点核心：无任何容器 Padding 限制，内容两端完美贴合
              Container(
                height: 350,
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12),
                child: quill.QuillEditor(
                  controller: _quillController,
                  scrollController: _editorScrollC,
                  focusNode: _editorFocusNode,
                  config: quill.QuillEditorConfig(
                    placeholder: 'share_moment_hint'.tr,
                    autoFocus: false,
                    checkBoxReadOnly: false,
                    padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 0),
                    expands: true,
                    customStyles: const quill.DefaultStyles(
                      paragraph: quill.DefaultTextBlockStyle(
                        TextStyle(fontSize: 17.0, color: Colors.black87, height: 1.6, fontFamily: 'ShantellSans'),
                        quill.HorizontalSpacing(0, 0),
                        quill.VerticalSpacing(0, 0),
                        quill.VerticalSpacing(0, 0),
                        null,
                      ),
                      placeHolder: quill.DefaultTextBlockStyle(
                        TextStyle(fontSize: 17.0, color: Color(0xFF9CA3AF), height: 1.6, fontFamily: 'ShantellSans'),
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
              const Divider(height: 1, color: Color(0xFFF3F4F6)),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  controller: _quillTagsController,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'tags_hint_tech'.tr,
                    hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFF3F4F6))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFF3F4F6))),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
              // 🌟 新增：付费阅读价格输入（仅在深度文章表单中展示，带限制与自动纠偏机制）
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
                child: TextField(
                  controller: _quillPriceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')), // 限制只能输入数字且最多两位小数
                  ],
                  style: const TextStyle(fontSize: 14),
                  onChanged: (value) {
                    if (value.isEmpty) return;
                    final double? parsed = double.tryParse(value);
                    if (parsed != null) {
                      if (parsed > 50.0) {
                        _quillPriceController.text = "50.00";
                        // 保持光标定位在文本最后一位
                        _quillPriceController.selection = TextSelection.fromPosition(
                          TextPosition(offset: _quillPriceController.text.length),
                        );
                        Fluttertoast.showToast(msg: 'price_limit_notice'.tr);
                      } else if (parsed < 0.0) {
                        _quillPriceController.text = "0.00";
                        _quillPriceController.selection = TextSelection.fromPosition(
                          TextPosition(offset: _quillPriceController.text.length),
                        );
                      }
                    }
                  },
                  decoration: InputDecoration(
                    hintText: 'price_hint'.tr,
                    hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
                    prefixIcon: const Icon(Icons.attach_money_rounded, color: Color(0xFF0066FF), size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFF3F4F6))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFF3F4F6))),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
        _EnhancedToolbar(
          controller: _quillController,
          onImageTap: _pickImage,
          onGifTap: _pickGif,
          onDividerTap: _insertDivider,
          onToggle: _toggleAttribute,
        ),
      ],
    );
  }

  // 2. 投票发布表单
  Widget _buildPollForm() {
    final themeColor = const Color(0xFF0066FF);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12),
          child: TextField(
            controller: _pollQuestionController,
            maxLines: 2,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              hintText: 'poll_question_hint'.tr,
              hintStyle: TextStyle(color: Color(0xFF9CA3AF), fontSize: 16, fontWeight: FontWeight.normal),
              border: InputBorder.none,
            ),
          ),
        ),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _pollOptionControllers.length + 1,
            itemBuilder: (context, index) {
              if (index == _pollOptionControllers.length) {
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _pollOptionControllers.add(TextEditingController());
                      });
                    },
                    icon: HugeIcon(icon: HugeIcons.strokeRoundedPlusSignCircle, color: themeColor, size: 20.0),
                    label: Text('add_poll_option'.tr, style: TextStyle(color: themeColor, fontWeight: FontWeight.bold)),
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: themeColor.withOpacity(0.1),
                      child: Text("${index + 1}", style: TextStyle(fontSize: 11, color: themeColor, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F7FA),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TextField(
                          controller: _pollOptionControllers[index],
                          decoration: InputDecoration(
                            hintText: 'poll_option_hint'.tr,
                            hintStyle: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                        ),
                      ),
                    ),
                    if (_pollOptionControllers.length > 2) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _pollOptionControllers.removeAt(index);
                          });
                        },
                        icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        )
      ],
    );
  }

  // 3. 图文说说表单：图片添加区像素级还原图示
  Widget _buildShortForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12),
                child: TextField(
                  controller: _shortContentController,
                  maxLines: 6,
                  style: const TextStyle(fontSize: 16, height: 1.5),
                  decoration: InputDecoration(
                    hintText: 'share_moment_hint'.tr,
                    hintStyle: TextStyle(color: Color(0xFF9CA3AF)),
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    ..._shortImages.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final url = entry.value;
                      return Stack(
                        alignment: Alignment.topRight,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(url, width: 90, height: 90, fit: BoxFit.cover),
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
                              decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                              padding: const EdgeInsets.all(3),
                              child: const Icon(Icons.close, size: 12, color: Colors.white),
                            ),
                          ),
                        ],
                      );
                    }).toList(),

                    // 🌟 像素级还原图示添加图片卡片
                    GestureDetector(
                      onTap: _showShortImageSourcePicker,
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F7FA),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            HugeIcon(icon: HugeIcons.strokeRoundedPlusSign, color: Color(0xFF9CA3AF), size: 24.0),
                            SizedBox(height: 8),
                            Text('image_video'.tr, style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: TextField(
                  controller: _shortTagsController,
                  decoration: InputDecoration(
                    hintText: 'tags_hint_news'.tr,
                    hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFF3F4F6))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFF3F4F6))),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        )
      ],
    );
  }

  // 🌟 参考图配色交互底栏完全体设计（拼色药丸指示器联动）
  Widget _buildBottomActionToolbar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade100, width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
            child: Row(
              children: [
                // 1. 使用 Expanded 让滚动区域占据剩余空间，保持右侧状态按钮固定
                if (_activeFormIndex == 0)
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(), // 增加横向滚动的物理回弹效果
                      child: Row(
                        children: [
                          IconButton(
                            icon: const HugeIcon(icon: HugeIcons.strokeRoundedHashtag, color: Color(0xFF9CA3AF), size: 22.0),
                            onPressed: () {
                              if (_activeFormIndex == 0) {
                                _quillController.replaceText(_quillController.selection.baseOffset, 0, '#', null);
                              } else if (_activeFormIndex == 2) {
                                _shortContentController.text += '#';
                              }
                            },
                          ),
                          IconButton(
                            icon: const HugeIcon(
                              icon: HugeIcons.strokeRoundedSquareArrowMoveDownLeft,
                              color: Color(0xFF9CA3AF),
                              size: 22,
                            ),
                            onPressed: () {
                              if (_activeFormIndex == 0) {
                                final index = _quillController.selection.baseOffset;
                                _quillController.replaceText(index, 0, '\n', null);
                                _quillController.updateSelection(
                                  TextSelection.collapsed(offset: index + 1),
                                  quill.ChangeSource.local,
                                );
                              } else if (_activeFormIndex == 2) {
                                _shortContentController.text += '\n';
                              }
                            },
                          ),
                          IconButton(
                            icon: const HugeIcon(
                              icon: HugeIcons.strokeRoundedCancelCircle,
                              color: Color(0xFF9CA3AF),
                              size: 22,
                            ),
                            onPressed: () {
                              FocusScope.of(context).unfocus();
                              _editorFocusNode.unfocus();
                            },
                          ),
                          IconButton(
                            icon: const HugeIcon(icon: HugeIcons.strokeRoundedChatQuestion, color: Color(0xFF9CA3AF), size: 22.0),
                            onPressed: () => setState(() => _activeFormIndex = 1),
                          ),
                          IconButton(
                            icon: const HugeIcon(icon: HugeIcons.strokeRoundedInLove, color: Color(0xFF9CA3AF), size: 22.0),
                            onPressed: _openEmojiPicker,
                          ),
                          IconButton(
                            icon: const HugeIcon(icon: HugeIcons.strokeRoundedMenuSquare, color: Color(0xFF9CA3AF), size: 22.0),
                            onPressed: _showStatusSelector,
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_activeFormIndex == 0) ...[const SizedBox(width: 8), // 2. 替换掉原本的 Spacer，用固定间距隔开左右两边
                  GestureDetector(
                    onTap: _showStatusSelector,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F7FA),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const HugeIcon(icon: HugeIcons.strokeRoundedSettings01, color: Colors.grey, size: 12.0),
                          const SizedBox(width: 4),
                          Text(
                            _statusNameKeys[_activeFormIndex == 0 ? _quillStatus : (_activeFormIndex == 1 ? _pollStatus : _shortStatus)]?.tr ?? 'filter_public'.tr,
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  )],

              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF3F4F6)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 提问题 (Pill 1) -> 指向投票
                _buildPillButton(
                  index: 1,
                  icon: HugeIcons.strokeRoundedChatQuestion,
                  text: 'tab_ask'.tr,
                  bgColor: const Color(0xFFE8F5E9),
                  textColor: const Color(0xFF2E7D32),
                ),
                // 写回答/想法 (Pill 2) -> 指向图文说说
                _buildPillButton(
                  index: 2,
                  icon: HugeIcons.strokeRoundedPencilEdit02,
                  text: 'tab_moment'.tr,
                  bgColor: const Color(0xFFE3F2FD),
                  textColor: const Color(0xFF1565C0),
                ),
                // 发文章 (Pill 3) -> 指向深度富文本
                _buildPillButton(
                  index: 0,
                  icon: HugeIcons.strokeRoundedNote01,
                  text: 'tab_article'.tr,
                  bgColor: const Color(0xFFFFF3E0),
                  textColor: const Color(0xFFE65100),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPillButton({
    required int index,
    required dynamic icon, // 使用 dynamic 保持与不同版本 HugeIcons 传参类型的最高兼容度
    required String text,
    required Color bgColor,
    required Color textColor,
  }) {
    final isSelected = _activeFormIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _activeFormIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? bgColor : const Color(0xFFF5F7FA),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? textColor.withOpacity(0.3) : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            HugeIcon(
              icon: icon,
              color: isSelected ? textColor : Colors.grey.shade600,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              text,
              style: TextStyle(
                color: isSelected ? textColor : Colors.grey.shade700,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
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
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: TextField(
            controller: _searchC,
            focusNode: _searchFocus,
            textInputAction: TextInputAction.search,
            cursorColor: Colors.blueAccent,
            style: const TextStyle(fontSize: 15, color: Color(0xFF2C3E50)),
            onSubmitted: (value) => _fetchGifs(value),
            decoration: InputDecoration(
              hintText: 'search_gif_hint'.tr,
              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
              prefixIcon: const Icon(Icons.search, size: 20, color: Colors.grey),
              filled: true,
              fillColor: const Color(0xFFF5F7FA),
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward, color: Colors.blueAccent, size: 22),
                onPressed: () => _fetchGifs(_searchC.text),
              ),
            ),
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 3, color: Colors.blueAccent))
              : _gifs.isEmpty
              ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.search, size: 48, color: Colors.grey),
                const SizedBox(height: 12),
                Text('no_gif_found'.tr, style: TextStyle(color: Colors.grey[400])),
              ],
            ),
          )
              : GridView.builder(
            controller: widget.scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
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
                  splashColor: Colors.blueAccent.withOpacity(0.1),
                  child: Image.network(
                    url,
                    fit: BoxFit.cover,
                    loadingBuilder: (ctx, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            value: loadingProgress.expectedTotalBytes != null
                                ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                : null,
                            color: Colors.blueAccent.withOpacity(0.5),
                          ),
                        ),
                      );
                    },
                    errorBuilder: (ctx, err, stack) => const Center(
                      child: Icon(Icons.broken_image_rounded, color: Colors.grey, size: 30),
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

class _EnhancedToolbar extends StatelessWidget {
  final quill.QuillController controller;
  final VoidCallback onImageTap;
  final VoidCallback onGifTap;
  final VoidCallback onDividerTap;
  final Function(quill.Attribute) onToggle;

  const _EnhancedToolbar({
    required this.controller,
    required this.onImageTap,
    required this.onGifTap,
    required this.onDividerTap,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, child) {
          return ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              _toolBtn(HugeIcons.strokeRoundedImage01, null, isAction: true, onTap: onImageTap),
              _toolBtn(HugeIcons.strokeRoundedGif01, null, isAction: true, onTap: onGifTap),
              _vDivider(),
              _toolBtn(HugeIcons.strokeRoundedMenu04, null, isAction: true, onTap: onDividerTap),
              _vDivider(),
              _toolBtn(HugeIcons.strokeRoundedTextBold, quill.Attribute.bold),
              _toolBtn(HugeIcons.strokeRoundedTextItalic, quill.Attribute.italic),
              _toolBtn(HugeIcons.strokeRoundedTextUnderline, quill.Attribute.underline),
              _vDivider(),
              _toolBtn(HugeIcons.strokeRoundedHeading01, quill.Attribute.h1),
              _toolBtn(HugeIcons.strokeRoundedHeading02, quill.Attribute.h2),
              _toolBtn(HugeIcons.strokeRoundedQuoteUp, quill.Attribute.blockQuote),
              _vDivider(),
              _toolBtn(HugeIcons.strokeRoundedLeftToRightListBullet, quill.Attribute.ul),
              _toolBtn(HugeIcons.strokeRoundedLeftToRightListNumber, quill.Attribute.ol),
              _toolBtn(HugeIcons.strokeRoundedTextAlignCenter, quill.Attribute.centerAlignment),
            ],
          );
        },
      ),
    );
  }

  Widget _vDivider() => const VerticalDivider(
    indent: 14,
    endIndent: 14,
    width: 24,
    color: Color(0xFFF0F0F0),
  );

  Widget _toolBtn(
      dynamic icon,
      quill.Attribute? attr, {
        bool isAction = false,
        VoidCallback? onTap,
      }) {
    bool isActive = false;

    if (attr != null && !isAction) {
      final style = controller.getSelectionStyle();
      final currentAttr = style.attributes[attr.key];

      if (currentAttr != null) {
        isActive = currentAttr.value == attr.value;
      }
    }

    return IconButton(
      onPressed: isAction
          ? onTap
          : (attr != null ? () => onToggle(attr) : null),
      icon: HugeIcon(
        icon: icon,
        color: isActive
            ? const Color(0xFF0066FF)
            : const Color(0xFF6B7280),
        size: 22,
      ),
    );
  }
}