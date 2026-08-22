// PUT /api-users/profile (资料修改与本地/GIF 头像选取完全体)
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 🌟 新增：引入系统输入限制格式化器
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qorange/theme.dart';

import '../../network/api_exception.dart';
import '../../network/http_client.dart';
import '../../services/api_service.dart';

class ProfileEditView extends StatefulWidget {
  const ProfileEditView({super.key});

  @override
  State<ProfileEditView> createState() => _ProfileEditViewState();
}

class _ProfileEditViewState extends State<ProfileEditView> {
  final TextEditingController _nicknameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  final TextEditingController _avatarController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _websiteController = TextEditingController();

  // 学术/生活领域字典映射：值为多语言词条 key，展示时调用 .tr 取当前语言文案
  final Map<String, String> _topicMap = {
    'technology': 'topic_technology',
    'blockchain': 'topic_blockchain',
    'cryptocurrency': 'topic_cryptocurrency',
    'data_science': 'topic_data_science',
    'finance': 'topic_finance',
    'trading': 'topic_trading',
    'business': 'topic_business',
    'aviation': 'topic_aviation',
    'education': 'topic_education',
    'car': 'topic_car',
    'gamer': 'topic_gamer',
    'style': 'topic_style',
    'restaurant': 'topic_restaurant',
    'traveler': 'topic_traveler',
    'news': 'topic_news',
  };

  final List<String> _selectedTopics = [];
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentProfile();
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    _avatarController.dispose();
    _locationController.dispose();
    _websiteController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentProfile() async {
    try {
      final res = await HttpClient.instance.get<Map<String, dynamic>>('/api-users/profile-edit');
      if (res.datas != null) {
        final profile = res.datas!;
        setState(() {
          _nicknameController.text = profile['nickname'] ?? '';
          _usernameController.text = profile['username'] ?? '';
          _bioController.text = profile['bio'] ?? '';
          _avatarController.text = profile['avatar'] ?? '';
          _locationController.text = profile['location'] ?? '';
          _websiteController.text = profile['website'] ?? '';
          _selectedTopics.addAll(List<String>.from(profile['topics'] ?? []));
          _isLoading = false;
        });
      }
    } catch (e) {
      if (e is ApiException) {
        Fluttertoast.showToast(msg: e.message);
      } else {
        Fluttertoast.showToast(msg: 'load_profile_failed'.tr);
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    final String nickname = _nicknameController.text.trim();

    if (nickname.isEmpty) {
      Fluttertoast.showToast(msg: 'nickname_required'.tr);
      return;
    }

    // 🌟 核心改进：提交阶段强化校验逻辑，确保昵称字符长度严格在安全边界内
    if (nickname.length > 20) {
      Fluttertoast.showToast(msg: 'nickname_too_long'.tr);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final body = {
        'nickname': nickname,
        'username': _usernameController.text.trim(),
        'bio': _bioController.text.trim(),
        'avatar': _avatarController.text.trim(),
        'location': _locationController.text.trim(),
        'website': _websiteController.text.trim(),
        'topics': _selectedTopics,
      };

      final res = await HttpClient.instance.put('/api-users/profile', data: body);
      if (res.respCode == 0) {
        Fluttertoast.showToast(msg: 'update_success'.tr);
        Get.back();
      }
    } catch (e) {
      if (e is ApiException) {
        Fluttertoast.showToast(msg: e.message);
      } else {
        Fluttertoast.showToast(msg: 'update_profile_failed'.tr);
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  // 显示头像采集底层弹窗 (iOS 雅致软盒风格)
  void _showAvatarSourceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.only(top: 12, bottom: 30, left: 24, right: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 24),
              Text('change_avatar'.tr, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary)),
              const SizedBox(height: 16),
              ListTile(
                leading: Icon(Icons.photo_library_outlined, color: AppColors.textPrimary),
                title: Text('pick_from_gallery'.tr),
                onTap: () {
                  Navigator.pop(context);
                  _pickLocalAvatar();
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.gif_box_outlined, color: AppColors.textPrimary),
                title: Text('pick_animated_gif'.tr),
                onTap: () {
                  Navigator.pop(context);
                  _pickGifAvatar();
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.link_outlined, color: AppColors.textPrimary),
                title: Text('paste_image_url'.tr),
                onTap: () {
                  Navigator.pop(context);
                  _showManualUrlDialog();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // 1. 本地选取并上传
  Future<void> _pickLocalAvatar() async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (xFile == null) return;

    Fluttertoast.showToast(msg: 'uploading_avatar'.tr);
    final url = await ApiService.uploadImage(File(xFile.path));
    if (url != null) {
      setState(() {
        _avatarController.text = url;
      });
      Fluttertoast.showToast(msg: 'avatar_updated'.tr);
    } else {
      Fluttertoast.showToast(msg: 'avatar_upload_failed'.tr);
    }
  }

  // 2. GIF 选取
  void _pickGifAvatar() {
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
              decoration: BoxDecoration(color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                child: _GifSearchSheet(
                  scrollController: scrollController,
                  onGifSelected: (url) {
                    Navigator.pop(context);
                    setState(() {
                      _avatarController.text = url;
                    });
                    Fluttertoast.showToast(msg: 'gif_avatar_updated'.tr);
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  // 3. 手动 URL 输入
  void _showManualUrlDialog() {
    final textC = TextEditingController(text: _avatarController.text);
    Get.dialog(
      AlertDialog(
        title: Text('enter_image_url'.tr, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: textC,
          decoration: const InputDecoration(hintText: "https://example.com/avatar.png"),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: Text('cancel'.tr, style: const TextStyle(color: Colors.grey))),
          TextButton(
            onPressed: () {
              if (textC.text.trim().isNotEmpty) {
                setState(() {
                  _avatarController.text = textC.text.trim();
                });
                Get.back();
                Fluttertoast.showToast(msg: 'link_set_success'.tr);
              }
            },
            child: Text('ok'.tr, style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = AppColors.primary;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(backgroundColor: AppColors.surface, elevation: 0),
        body: Center(child: CircularProgressIndicator(color: themeColor, strokeWidth: 2)),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9FB),
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Get.back(),
          icon: Icon(Icons.close, color: AppColors.textPrimary),
        ),
        title: Text('edit_profile_title'.tr, style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
          _isSaving
              ? const Center(child: Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))))
              : Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: TextButton(
              onPressed: _saveProfile,
              child: Text('save'.tr, style: TextStyle(color: themeColor, fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 顶部渐变学术气场背景与可视化头像区
            Container(color: AppColors.surface,
              padding: const EdgeInsets.only(top: 24, bottom: 24),
              width: double.infinity,
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _showAvatarSourceSheet,
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: themeColor.withOpacity(0.2), width: 3),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5)),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 46,
                            backgroundImage: _avatarController.text.isNotEmpty ? NetworkImage(_avatarController.text) : null,
                            backgroundColor: AppColors.divider,
                            child: _avatarController.text.isEmpty ? const Icon(Icons.add_a_photo_outlined, size: 32, color: Colors.grey) : null,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                          child: const Icon(Icons.camera_alt, color: Colors.white, size: 14),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('tap_change_avatar'.tr, style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                ],
              ),
            ),

            // 基础信息区块
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('basic_info'.tr, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
                  const SizedBox(height: 10),
                  // 🌟 核心改进：为“昵称”输入框传参 maxLength: 20，强制进行本地物理键盘输入字符限制
                  _buildInputField(label: 'nickname'.tr, controller: _nicknameController, icon: HugeIcons.strokeRoundedUser, maxLength: 20),
                  _buildInputField(label: 'username_label'.tr, controller: _usernameController, icon: HugeIcons.strokeRoundedUserAccount),
                  _buildInputField(label: 'location_label'.tr, controller: _locationController, icon: HugeIcons.strokeRoundedLocation01),
                  _buildInputField(label: 'website_label'.tr, controller: _websiteController, icon: HugeIcons.strokeRoundedGlobal),
                  _buildInputField(label: 'bio_label'.tr, controller: _bioController, icon: HugeIcons.strokeRoundedBookOpen02, isMultiLine: true),

                  const SizedBox(height: 20),
                  Text('interests_categories'.tr, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
                  const SizedBox(height: 12),

                  // 纯中文美化芯片选择区 (Topics)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 10,
                      children: _topicMap.keys.map((topicKey) {
                        final topicLabel = _topicMap[topicKey]!.tr;
                        final isSelected = _selectedTopics.contains(topicKey);
                        return FilterChip(
                          label: Text(topicLabel, style: TextStyle(color: isSelected ? Colors.white : AppColors.textPrimary, fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                          selected: isSelected,
                          selectedColor: themeColor,
                          backgroundColor: const Color(0xFFF3F4F6),
                          checkmarkColor: Colors.white,
                          elevation: 0,
                          pressElevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide.none),
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _selectedTopics.add(topicKey);
                              } else {
                                _selectedTopics.remove(topicKey);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🌟 核心改进：添加 maxLength 可选入参，配合系统的 LengthLimitingTextInputFormatter，完美拦截多余字符输入
  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    required dynamic icon,
    bool isMultiLine = false,
    int? maxLength,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: TextField(
        controller: controller,
        maxLines: isMultiLine ? 4 : 1,
        maxLength: maxLength,
        inputFormatters: maxLength != null
            ? [LengthLimitingTextInputFormatter(maxLength)]
            : null,
        style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
          ),
          counterText: "", // 🌟 隐藏自带的 helper 计数，确保雅致的现代界面美学
          prefixIcon: Padding(
            padding: const EdgeInsets.all(12),
            child: HugeIcon(
              icon: icon,
              color: AppColors.textHint,
              size: 20,
            ),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
      ),
    );
  }
}

// ================= 内嵌 GIF 搜索面板 =================
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
          color: AppColors.surface,
          child: Center(
            child: Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.border,
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
              hintStyle: TextStyle(color: AppColors.textHint, fontSize: 14),
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
                Text('no_gif_found'.tr, style: TextStyle(color: AppColors.textHint)),
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
                color: AppColors.divider,
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