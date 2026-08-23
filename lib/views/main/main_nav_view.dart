// lib/views/main/main_nav_view.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../browser/atsign_browser_page.dart';
import '../../controllers/im_conversation_controller.dart';
import '../../services/notification_handler_service.dart';
import '../../user_controller.dart';
import '../community/community_discovery_view.dart';
import '../home/home_view.dart';
import '../im/im_conversation_list_view.dart';
import '../login/login_view.dart';
import '../profile/profile_view.dart';
import '../shop/shop_view.dart';

class MainNavView extends StatefulWidget {
  const MainNavView({super.key});

  @override
  State<MainNavView> createState() => _MainNavViewState();
}

class _MainNavViewState extends State<MainNavView> {
  int _currentIndex = 0;
  Worker? _navUserWorker;

  // 🌟 定义所有子页面（第 2 个为隐私浏览器，动态绑定当前登录用户的 Token）
  late final List<Widget> _pages;

  // 🌟 定义需要登录权限才能访问的 Tab 索引集合
  // 2: 隐私浏览, 3: 消息, 5: 我的
  static const Set<int> _protectedIndices = {2, 3, 5};

  @override
  void initState() {
    super.initState();
    Get.put(ImConversationController());

    // 找到 main_nav_view.dart 中的 _pages 初始化位置
    _pages = [
      const HomeView(),
      const CommunityDiscoveryView(),
      // 🌟 改为 const 无参构造，不再需要从 UserController 强读 token
      const AtsignBrowserPage(),
      const ImConversationListView(),
      const ShopView(),
      const ProfileView(),
    ];

    // 🌟 用户状态变动（如退出登录）时安全重置导航栏索引到首页，避免停留在需要权限的页面
    _navUserWorker = ever(UserController.to.user, (user) {
      if (mounted) {
        if (!UserController.to.isLoggedIn && _protectedIndices.contains(_currentIndex)) {
          setState(() {
            _currentIndex = 0; // 退出登录后自动切回首页
          });
        } else {
          setState(() {});
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Get.find<NotificationHandlerService>().checkForUpdate();
    });
  }

  @override
  void dispose() {
    _navUserWorker?.dispose();
    super.dispose();
  }

  void _onTap(int index) async {
    // 🌟 登录拦截器：对【隐私浏览(2)】、【消息(3)】与【我的(5)】统一拦截
    if (_protectedIndices.contains(index)) {
      if (!UserController.to.isLoggedIn) {
        final bool? loggedIn = await Get.to<bool>(
              () => const LoginView(),
          transition: Transition.rightToLeftWithFade,
        );

        // 用户在登录页成功登录后，才放行切换到目标 Tab
        if (loggedIn == true && mounted) {
          setState(() {
            _currentIndex = index;
          });
        }
        return;
      }
    }

    if (mounted) {
      setState(() {
        _currentIndex = index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const themeColor = Color.fromRGBO(44, 123, 109, 1.0);
    final imConvCtrl = Get.find<ImConversationController>();

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: Colors.grey.shade100,
              width: 1,
            ),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _onTap,
          backgroundColor: Colors.white,
          selectedItemColor: themeColor,
          unselectedItemColor: Colors.grey.shade400,
          showSelectedLabels: true,
          showUnselectedLabels: true,
          selectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 11,
          ),
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          items: [
            // 0: 首页
            BottomNavigationBarItem(
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedHome01,
                color: Colors.grey.shade400,
              ),
              activeIcon: const HugeIcon(
                icon: HugeIcons.strokeRoundedHome01,
                color: themeColor,
              ),
              label: 'nav_home'.tr,
            ),
            // 1: 社群
            BottomNavigationBarItem(
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedUserGroup,
                color: Colors.grey.shade400,
              ),
              activeIcon: const HugeIcon(
                icon: HugeIcons.strokeRoundedUserGroup,
                color: themeColor,
              ),
              label: 'nav_community'.tr,
            ),
            // 🌟 2: 新增 E2EE 代理浏览（需登录拦截）
            BottomNavigationBarItem(
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedGlobe02,
                color: Colors.grey.shade400,
              ),
              activeIcon: const HugeIcon(
                icon: HugeIcons.strokeRoundedGlobe02,
                color: themeColor,
              ),
              label: '浏览',
            ),
            // 3: 消息（带未读小红点）
            BottomNavigationBarItem(
              icon: Obx(() => _buildBadgeIcon(
                icon: HugeIcons.strokeRoundedBubbleChat,
                color: Colors.grey.shade400,
                unreadCount: imConvCtrl.totalUnreadCount.value,
              )),
              activeIcon: Obx(() => _buildBadgeIcon(
                icon: HugeIcons.strokeRoundedBubbleChat,
                color: themeColor,
                unreadCount: imConvCtrl.totalUnreadCount.value,
              )),
              label: '消息',
            ),
            // 4: 商城
            BottomNavigationBarItem(
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedShoppingBag01,
                color: Colors.grey.shade400,
              ),
              activeIcon: const HugeIcon(
                icon: HugeIcons.strokeRoundedShoppingBag01,
                color: themeColor,
              ),
              label: 'nav_shop'.tr,
            ),
            // 5: 我的
            BottomNavigationBarItem(
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedUser,
                color: Colors.grey.shade400,
              ),
              activeIcon: const HugeIcon(
                icon: HugeIcons.strokeRoundedUser,
                color: themeColor,
              ),
              label: 'nav_profile'.tr,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadgeIcon({
    required dynamic icon,
    required Color color,
    required int unreadCount,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        HugeIcon(icon: icon, color: color),
        if (unreadCount > 0)
          Positioned(
            right: -6,
            top: -3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Center(
                child: Text(
                  unreadCount > 99 ? '99+' : '$unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}