// 替换 lib/views/main/main_nav_view.dart 文件

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../controllers/im_conversation_controller.dart';
import '../../services/notification_handler_service.dart';
import '../../user_controller.dart';
import '../community/community_discovery_view.dart';
import '../home/home_view.dart';
import '../im/im_conversation_list_view.dart';
import '../login/login_view.dart';
import '../profile/profile_view.dart';
import '../shop/shop_view.dart';
import '../video_media/views/media_discovery_view.dart'; // 🌟 引入影音大厅

class MainNavView extends StatefulWidget {
  const MainNavView({super.key});

  @override
  State<MainNavView> createState() => _MainNavViewState();
}

class _MainNavViewState extends State<MainNavView> {
  int _currentIndex = 0;
  Worker? _navUserWorker;

  final List<Widget> _pages = [
    const HomeView(),                 // 0. 首页观点
    const MediaDiscoveryView(),       // 1. 🌟 影音探索与播放大厅
    const CommunityDiscoveryView(),   // 2. 社群圈子
    const ImConversationListView(),   // 3. 消息通讯
    const ShopView(),                 // 4. 商店
    const ProfileView(),              // 5. 个人主页
  ];

  @override
  void initState() {
    super.initState();
    Get.put(ImConversationController());

    _navUserWorker = ever(UserController.to.user, (user) {
      if (mounted) setState(() {});
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
    // 拦截【消息（索引 3）】与【我的（索引 5）】
    if (index == 3 || index == 5) {
      if (!UserController.to.isLoggedIn) {
        final bool? loggedIn = await Get.to<bool>(
              () => const LoginView(),
          transition: Transition.rightToLeftWithFade,
        );

        if (loggedIn == true && mounted) {
          setState(() => _currentIndex = index);
        }
        return;
      }
    }
    if (mounted) {
      setState(() => _currentIndex = index);
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
            fontSize: 10,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 10,
          ),
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          items: [
            BottomNavigationBarItem(
              icon: const HugeIcon(icon: HugeIcons.strokeRoundedHome01, color: Colors.grey),
              activeIcon: const HugeIcon(icon: HugeIcons.strokeRoundedHome01, color: themeColor),
              label: 'nav_home'.tr,
            ),
            BottomNavigationBarItem(
              icon: const HugeIcon(icon: HugeIcons.strokeRoundedPlayList, color: Colors.grey),
              activeIcon: const HugeIcon(icon: HugeIcons.strokeRoundedPlayList, color: themeColor),
              label: '视频',
            ),
            BottomNavigationBarItem(
              icon: const HugeIcon(icon: HugeIcons.strokeRoundedUserGroup, color: Colors.grey),
              activeIcon: const HugeIcon(icon: HugeIcons.strokeRoundedUserGroup, color: themeColor),
              label: 'nav_community'.tr,
            ),
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
            BottomNavigationBarItem(
              icon: const HugeIcon(icon: HugeIcons.strokeRoundedShoppingBag01, color: Colors.grey),
              activeIcon: const HugeIcon(icon: HugeIcons.strokeRoundedShoppingBag01, color: themeColor),
              label: 'nav_shop'.tr,
            ),
            BottomNavigationBarItem(
              icon: const HugeIcon(icon: HugeIcons.strokeRoundedUser, color: Colors.grey),
              activeIcon: const HugeIcon(icon: HugeIcons.strokeRoundedUser, color: themeColor),
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