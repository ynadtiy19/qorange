// GET /api-users/profile (多维 Tab 数据静默重绘与高级卡片集成版)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:qorange/user_controller.dart';
import 'package:qorange/views/profile/setting_view.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../network/api_exception.dart';
import '../../network/http_client.dart';
import '../../network/auth_state_manager.dart';
import '../../network/secure_storage_manager.dart';
import '../post_detail/post_detail_view.dart';
import '../main/main_nav_view.dart';
import '../login/login_view.dart';
import '../wallet/wallet_view.dart';
import 'profile_edit_view.dart';

// 全局关系与数据状态同步触发信号
final RxInt globalProfileRefreshSignal = 0.obs;

/// 🌟 业务控制器层 (实现控制器与视图逻辑完全分离)
class ProfileController extends GetxController {
  final String? profileId;
  ProfileController({this.profileId});

  final rxProfile = Rxn<Map<String, dynamic>>();
  final rxIsLoading = true.obs;
  final rxActiveTab = 'published'.obs;
  final rxTabItems = <dynamic>[].obs;
  final rxIsLoadingTabItems = false.obs;

  @override
  void onInit() {
    super.onInit();
    loadProfile();
  }

  Future<void> loadProfile() async {
    final token = await SecureStorageManager.instance.getAccessToken();
    final isSessionAvailable = UserController.to.isLoggedIn || (token != null && token.isNotEmpty);

    if (profileId == null && !isSessionAvailable) {
      rxProfile.value = null;
      rxIsLoading.value = false;
      return;
    }

    try {
      final query = <String, dynamic>{};
      if (profileId != null) query['profile_id'] = profileId;
      query['tab'] = rxActiveTab.value;

      final res = await HttpClient.instance.get<Map<String, dynamic>>('/api-users/profile', queryParameters: query);
      if (res.datas != null) {
        rxProfile.value = res.datas!;
        rxIsLoading.value = false;
        await loadTabItemsData();
      }
    } catch (e) {
      rxIsLoading.value = false;
    }
  }

  // 🌟 核心改进点：每次切换 Tab 触发时，如果是前三个基本状态，将重新向后端拉取带 query 的社交页快照，实现独立分类刷新
  Future<void> loadTabItemsData() async {
    if (rxProfile.value == null) return;

    final tab = rxActiveTab.value;
    rxIsLoadingTabItems.value = true;

    try {
      if (tab == 'published' || tab == 'draft' || tab == 'unlisted') {
        // 重构对社交主页的请求，携带最新 Tab 过滤符
        final query = <String, dynamic>{};
        if (profileId != null) query['profile_id'] = profileId;
        query['tab'] = tab;

        final res = await HttpClient.instance.get<Map<String, dynamic>>('/api-users/profile', queryParameters: query);
        if (res.datas != null) {
          rxProfile.value = res.datas!;
          rxTabItems.value = res.datas!['posts'] ?? [];
        }
      } else if (tab == 'collects') {
        // 请求专属收藏夹接口
        final res = await HttpClient.instance.get<List<dynamic>>('/api-users/collects');
        if (rxActiveTab.value == 'collects') {
          rxTabItems.value = res.datas ?? [];
        }
      } else if (tab == 'history') {
        // 请求历史足迹接口
        final res = await HttpClient.instance.get<List<dynamic>>('/api-users/history');
        if (rxActiveTab.value == 'history') {
          rxTabItems.value = res.datas ?? [];
        }
      } else if (tab == 'shares') {
        // 请求收到的推荐卡片接口
        final res = await HttpClient.instance.get<List<dynamic>>('/api-shares', queryParameters: {'type': 'received'});
        if (rxActiveTab.value == 'shares') {
          rxTabItems.value = res.datas ?? [];
        }
      }
    } catch (e) {
      rxTabItems.clear();
    } finally {
      rxIsLoadingTabItems.value = false;
    }
  }

  Future<void> toggleFollow() async {
    if (!UserController.to.isLoggedIn) {
      Fluttertoast.showToast(msg: "请登录后关注");
      return;
    }
    try {
      final res = await HttpClient.instance.post<Map<String, dynamic>>(
        '/api-users/follow',
        data: {'target_user_id': rxProfile.value!['id']},
      );
      if (res.respCode == 0) {
        await loadProfile();
        globalProfileRefreshSignal.value++;
      }
    } catch (e) {
      if (e is ApiException) {
        Fluttertoast.showToast(msg: e.message);
      } else {
        Fluttertoast.showToast(msg: "关注异常: $e");
      }
    }
  }

  Future<void> logout() async {
    try {
      await AuthStateManager.instance.logout();
      await UserController.to.clearUserInfo();
      Fluttertoast.showToast(msg: "已安全登出");
      Get.offAll(() => const MainNavView());
    } catch (e) {
      if (e is ApiException) {
        Fluttertoast.showToast(msg: e.message);
      } else {
        Fluttertoast.showToast(msg: "退出异常");
      }
    }
  }
}

/// 🌟 声明式视图层 (极佳视觉细节还原设计版)
class ProfileView extends StatefulWidget {
  final String? profileId;
  const ProfileView({super.key, this.profileId});

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> with TickerProviderStateMixin {
  late ProfileController _controller;
  TabController? _tabController;

  Worker? _userWorker;
  Worker? _relationWorker;

  @override
  void initState() {
    super.initState();
    _controller = Get.put(ProfileController(profileId: widget.profileId), tag: widget.profileId);

    // 监听用户登录状态
    _userWorker = ever(UserController.to.user, (_) {
      if (mounted) {
        _controller.rxIsLoading.value = true;
        _controller.loadProfile();
      }
    });

    // 监听全局同步信号
    _relationWorker = ever(globalProfileRefreshSignal, (_) {
      if (mounted) {
        _controller.loadProfile();
      }
    });

    // 动态重组 Tab 长度
    ever(_controller.rxProfile, (profile) {
      if (profile != null && mounted) {
        final isMe = profile['is_me'] ?? false;
        final tabCount = isMe ? 6 : 1;
        if (_tabController == null || _tabController!.length != tabCount) {
          _tabController?.dispose();
          _tabController = TabController(length: tabCount, vsync: this);
          _tabController!.addListener(_handleTabChange);
        }
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _userWorker?.dispose();
    _relationWorker?.dispose();
    Get.delete<ProfileController>(tag: widget.profileId);
    super.dispose();
  }


  // 解析并格式化注册时间 (如将 ISO-8601 解析为 "2026年5月" 格式)
  String _getJoinedDateString(dynamic createdAt) {
    if (createdAt == null) return "加入于 2026年5月";
    try {
      final dateTime = DateTime.parse(createdAt.toString());
      // 采用更具本土人文气息的格式：xxxx年xx月
      return "加入于 ${dateTime.year}年${dateTime.month}月";
    } catch (_) {
      return "加入于 2026年5月"; // 解析失败时的友好降级
    }
  }


  void _handleTabChange() {
    if (_tabController != null && !_tabController!.indexIsChanging) {
      final tabs = ['published', 'draft', 'unlisted', 'collects', 'history', 'shares'];
      if (_tabController!.index < tabs.length) {
        _controller.rxActiveTab.value = tabs[_tabController!.index];
        _controller.loadTabItemsData();
      }
    }
  }

  Future<void> _launchURL(String urlString) async {
    if (urlString.isEmpty) return;
    final formattedUrl = urlString.startsWith('http') ? urlString : 'https://$urlString';
    final Uri url = Uri.parse(formattedUrl);
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        Fluttertoast.showToast(msg: "无法打开链接: $urlString");
      }
    } catch (e) {
      Fluttertoast.showToast(msg: "解析错误: $e");
    }
  }

  void _showFullBioBottomSheet(String bio) {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("个人简介", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                IconButton(
                  onPressed: () => Get.back(),
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedCancel01, color: Colors.grey, size: 20),
                )
              ],
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Text(bio, style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.6)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = const Color.fromRGBO(44, 123, 109, 1.0);

    return Obx(() {
      if (_controller.rxIsLoading.value) {
        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(backgroundColor: Colors.white, elevation: 0),
          body: Center(child: CircularProgressIndicator(color: themeColor, strokeWidth: 2)),
        );
      }

      final profile = _controller.rxProfile.value;
      if (profile == null) {
        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            title: const Text("我的空间", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  HugeIcon(icon: HugeIcons.strokeRoundedUser, color: Colors.grey.shade300, size: 72.0),
                  const SizedBox(height: 16),
                  const Text("登录后开启您的学习空间", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
                  const SizedBox(height: 8),
                  Text(
                    "在这里，与数万创作者分享有深度、有态度的行业见解",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500, height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: 160,
                    height: 44,
                    child: ElevatedButton(
                      onPressed: () => Get.to(() => const LoginView()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: themeColor,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text("登录 / 注册", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      final isMe = profile['is_me'] ?? false;
      final topFollowed = profile['top_followed_users'] as List? ?? [];
      final bioText = profile['bio'] != null && profile['bio'].toString().isNotEmpty ? profile['bio'].toString() : "暂无个人简介...";
      final website = profile['website'] as String? ?? '';
      final location = profile['location'] as String? ?? '';
      final handleText = "@${profile['username'] ?? ''}";

      return Scaffold(
        backgroundColor: Colors.white,
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 60, left: 24, right: 24, bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // 🌟 核心改进一：将左侧区域使用 Expanded 包裹，使其自适应吸收除右侧图标外的剩余空间
                          Expanded(
                            child: Row(
                              children: [
                                CircleAvatar(radius: 18, backgroundImage: NetworkImage(profile['avatar'] ?? '')),
                                const SizedBox(width: 10),
                                // 🌟 核心改进二：将文本 Column 使用 Expanded 包裹，使内部 Text 可以获得确切的宽度限制
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        profile['nickname'] ?? '匿名作者',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                                        maxLines: 1, // 🌟 限制为单行展示
                                        overflow: TextOverflow.ellipsis, // 🌟 超长时尾部展示省略号
                                      ),
                                      Text(
                                        handleText,
                                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                                        maxLines: 1, // 🌟 限制为单行展示
                                        overflow: TextOverflow.ellipsis, // 🌟 超长时尾部展示省略号
                                      ),
                                    ],
                                  ),
                                )
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isMe) ...[
                                IconButton(
                                  onPressed: () => Get.to(() => const WalletView()),
                                  icon: HugeIcon(icon: HugeIcons.strokeRoundedWallet02, color: Colors.grey.shade700, size: 20),
                                ),
                                IconButton(
                                  onPressed: () => Get.to(() => const SettingView()),
                                  icon: HugeIcon(icon: HugeIcons.strokeRoundedSettings01, color: Colors.grey.shade700, size: 20),
                                ),
                                IconButton(
                                  onPressed: _controller.logout,
                                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedLogout01, color: Colors.redAccent, size: 20),
                                ),
                              ]
                            ],
                          )
                        ],
                      ),
                      const SizedBox(height: 32),
                      Center(
                        child: Column(
                          children: [
                            CircleAvatar(radius: 40, backgroundImage: NetworkImage(profile['avatar'] ?? '')),
                            const SizedBox(height: 14),
                            Text(profile['nickname'] ?? '匿名作者', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87)),
                            const SizedBox(height: 4),
                            Text(handleText, style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
                            const SizedBox(height: 18),
                            SizedBox(
                              width: 220,
                              height: 40,
                              child: isMe
                                  ? ElevatedButton.icon(
                                onPressed: () => Get.to(() => const ProfileEditView())?.then((_) => _controller.loadProfile()),
                                icon: const HugeIcon(icon: HugeIcons.strokeRoundedPencilEdit02, color: Colors.white, size: 16),
                                label: const Text("编辑个人资料", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0066FF),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                ),
                              )
                                  : ElevatedButton(
                                onPressed: _controller.toggleFollow,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: profile['is_following'] ? Colors.grey.shade100 : themeColor,
                                  foregroundColor: profile['is_following'] ? Colors.black87 : Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                ),
                                child: Text(profile['is_following'] ? "已关注" : "关注TA", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF9FAFB),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  HugeIcon(icon: HugeIcons.strokeRoundedUserGroup, color: Colors.grey.shade500, size: 16),
                                  const SizedBox(width: 6),
                                  Text("${profile['following_count'] ?? 0}", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
                                  const SizedBox(width: 4),
                                  Text("关注中", style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                                  const SizedBox(width: 16),
                                  Container(width: 1, height: 12, color: Colors.grey.shade300),
                                  const SizedBox(width: 16),
                                  HugeIcon(icon: HugeIcons.strokeRoundedUserMultiple, color: Colors.grey.shade500, size: 16),
                                  const SizedBox(width: 6),
                                  Text("${profile['followers_count'] ?? 0}", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
                                  const SizedBox(width: 4),
                                  Text("关注者", style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            bioText,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.5),
                          ),
                          if (bioText.length > 50)
                            GestureDetector(
                              onTap: () => _showFullBioBottomSheet(bioText),
                              child: Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Text("查看更多...", style: TextStyle(fontSize: 12, color: themeColor, fontWeight: FontWeight.bold)),
                              ),
                            )
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          HugeIcon(
                            icon: HugeIcons.strokeRoundedSettings01,
                            color: Colors.grey.shade500,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "兴趣 / 风格",
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      /// 🌟 topics 标签流
                      if ((profile['topics'] as List?) != null && (profile['topics'] as List).isNotEmpty)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: (profile['topics'] as List)
                              .map((t) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color.fromRGBO(44, 123, 109, 0.08),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color.fromRGBO(44, 123, 109, 0.15),
                              ),
                            ),
                            child: Text(
                              t.toString(),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color.fromRGBO(44, 123, 109, 1),
                              ),
                            ),
                          ))
                              .toList(),
                        )
                      else
                        Text(
                          "暂无兴趣标签",
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                        ),
                      const SizedBox(height: 10),

                      // 🌟 无限换行蓝色超链接 (一行容不下自动换行)
                      if (website.isNotEmpty)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const HugeIcon(icon: HugeIcons.strokeRoundedLink01, color: Colors.blueAccent, size: 16),
                            const SizedBox(width: 8),
                            Flexible(
                              child: GestureDetector(
                                onTap: () => _launchURL(website),
                                child: Text(
                                  website,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.blueAccent,
                                    decoration: TextDecoration.underline,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const HugeIcon(icon: HugeIcons.strokeRoundedCalendar01, color: Colors.grey, size: 16),
                          const SizedBox(width: 8),
                          // 🌟 动态调用时间计算
                          Text(
                            _getJoinedDateString(profile['created_at']),
                            style: const TextStyle(fontSize: 13, color: Color(0xFF52525B)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (location.isNotEmpty)
                        Row(
                          children: [
                            HugeIcon(icon: HugeIcons.strokeRoundedLocation01, color: Colors.grey.shade500, size: 16),
                            const SizedBox(width: 8),
                            Text("$location", style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                          ],
                        ),

                      if (topFollowed.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        const Text("共同关注的创作者", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black54)),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 40,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: topFollowed.length,
                            itemBuilder: (context, index) {
                              final f = topFollowed[index];
                              return Padding(
                                padding: const EdgeInsets.only(right: 10.0),
                                child: GestureDetector(
                                  onTap: () => Get.to(() => ProfileView(profileId: f['id'])),
                                  child: Container(
                                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.grey.shade200, width: 1.5)),
                                    child: CircleAvatar(radius: 16, backgroundImage: NetworkImage(f['avatar'] ?? '')),
                                  ),
                                ),
                              );
                            },
                          ),
                        )
                      ],

                      // 5. 靠左侧水平对齐 Tab 栏设计 (自适应请求)
                      if (isMe && _tabController != null) ...[
                        const SizedBox(height: 24),
                        TabBar(
                          controller: _tabController,
                          isScrollable: true,
                          tabAlignment: TabAlignment.start, // 🌟 强制选项卡水平左对齐靠拢
                          labelColor: themeColor,
                          unselectedLabelColor: Colors.grey.shade400,
                          indicatorColor: themeColor,
                          indicatorWeight: 3,
                          indicatorSize: TabBarIndicatorSize.label,
                          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 14),
                          tabs: const [
                            Tab(text: "已发布"),
                            Tab(text: "草稿箱"),
                            Tab(text: "私密/未列入"),
                            Tab(text: "我的收藏"),
                            Tab(text: "浏览历史"),
                            Tab(text: "我收到的分享"),
                          ],
                        )
                      ],
                    ],
                  ),
                ),
              ),
            ];
          },
          body: Obx(() {
            if (_controller.rxIsLoadingTabItems.value) {
              return Center(child: CircularProgressIndicator(color: themeColor, strokeWidth: 2));
            }

            final items = _controller.rxTabItems;
            return ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: items.length,
              separatorBuilder: (c, i) => const SizedBox(height: 12), // 🌟 采用间距取代普通的低质感 Divider
              itemBuilder: (context, index) {
                final dynamic item = items[index];

                if (_controller.rxActiveTab.value == 'history') {
                  final post = item['post'] ?? {};
                  final viewTime = item['viewed_at'] != null ? item['viewed_at'].toString().substring(0, 10) : '';
                  return _buildAestheticPostCard(post, datePrefix: "浏览于: $viewTime", cardIcon: HugeIcons.strokeRoundedClock01);
                } else if (_controller.rxActiveTab.value == 'shares') {
                  final post = item['post'] ?? {};
                  final sender = item['sender'] ?? {};
                  final shareTime = item['shared_at'] != null ? item['shared_at'].toString().substring(0, 10) : '';

                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade100, width: 0.8),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(radius: 12, backgroundImage: NetworkImage(sender['avatar'] ?? '')),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "${sender['nickname'] ?? '用户'} 推荐于 $shareTime",
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildAestheticPostCard(post, showLeftBorder: true),
                      ],
                    ),
                  );
                } else {
                  return _buildAestheticPostCard(item);
                }
              },
            );
          }),
        ),
      );
    });
  }

  // 🌟 修改后：个人主页高质感、大面积轻拟物列表卡片（深度对接 50 字 content_min 快照）
  Widget _buildAestheticPostCard(dynamic postData, {String? datePrefix, bool showLeftBorder = false, List<List<dynamic>>? cardIcon}) {
    final themeColor = const Color.fromRGBO(44, 123, 109, 1.0);
    if (postData == null || postData['id'] == null) return const SizedBox.shrink();

    final type = postData['post_type'] ?? 'quill';
    final titleStr = postData['title'] ?? '';

    // 🌟 核心改进：全面换用 50 字 content_min 快照，避免加载重度 Delta 原文数据
    final contentMin = postData['content_min'] ?? '';

    // 如果大标题为空（例如图文说说），自适应采用 50 字正文快照作为粗体大字展示
    final mainHeading = titleStr.isNotEmpty ? titleStr : contentMin;
    final hasSubtitle = titleStr.isNotEmpty && contentMin.isNotEmpty;

    final createTime = postData['created_at'] != null ? postData['created_at'].toString().substring(0, 10) : '';
    final thumbnail = postData['thumbnail'] as String? ?? '';
    final category = postData['category'] as String? ?? 'general';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: showLeftBorder ? themeColor.withOpacity(0.15) : Colors.grey.shade100, width: showLeftBorder ? 1.5 : 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.015),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Get.to(() => PostDetailView(postId: postData['id'])),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 分类微型高亮微标签
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: themeColor.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            category.toUpperCase(),
                            style: TextStyle(fontSize: 10, color: themeColor, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // 帖子大字粗体标题（或说说快照）
                        Text(
                          mainHeading,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Colors.black87, height: 1.35),
                        ),

                        // 副标题展示（仅在有标题且有正文快照时呈现，形成双层精致版面）
                        if (hasSubtitle) ...[
                          const SizedBox(height: 6),
                          Text(
                            contentMin,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500, height: 1.3),
                          ),
                        ],
                        const SizedBox(height: 12),

                        // 底部说明条
                        Row(
                          children: [
                            HugeIcon(
                              icon: cardIcon ?? HugeIcons.strokeRoundedCalendar01,
                              color: Colors.grey.shade400,
                              size: 13.0,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              datePrefix ?? "发布时间: $createTime",
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),

                  // 精致缩略图
                  if (thumbnail.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        thumbnail,
                        width: 70,
                        height: 70,
                        fit: BoxFit.cover,
                        errorBuilder: (c, e, s) => Container(
                          width: 70,
                          height: 70,
                          color: themeColor.withOpacity(0.05),
                          child: HugeIcon(icon: HugeIcons.strokeRoundedNote01, color: themeColor.withOpacity(0.3), size: 24.0),
                        ),
                      ),
                    )
                  else
                    Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        color: themeColor.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: HugeIcon(icon: HugeIcons.strokeRoundedNote01, color: themeColor.withOpacity(0.2), size: 24.0),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}