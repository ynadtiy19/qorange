// lib/views/main/main_nav_view.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:qorange/theme.dart';

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

  final List<Widget> _pages = [
    const HomeView(),
    const CommunityDiscoveryView(),
    const ImConversationListView(),
    const ShopView(),
    const ProfileView(),
  ];

  @override
  void initState() {
    super.initState();
    Get.put(ImConversationController());

    // 🌟 用户状态变动时安全重置导航栏索引到首页或个人中心
    _navUserWorker = ever(UserController.to.user, (user) {
      if (mounted) {
        setState(() {});
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
    // 对【消息（索引 2）】与【我的（索引 4）】进行登录拦截保护
    if (index == 2 || index == 4) {
      if (!UserController.to.isLoggedIn) {
        final bool? loggedIn = await Get.to<bool>(
              () => const LoginView(),
          transition: Transition.rightToLeftWithFade,
        );

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
    final themeColor = AppColors.primary;
    final imConvCtrl = Get.find<ImConversationController>();

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: AppColors.divider,
              width: 1,
            ),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _onTap,
          backgroundColor: AppColors.surface,
          selectedItemColor: themeColor,
          unselectedItemColor: AppColors.textHint,
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
            BottomNavigationBarItem(
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedHome01,
                color: AppColors.textHint,
              ),
              activeIcon: const HugeIcon(
                icon: HugeIcons.strokeRoundedHome01,
                color: themeColor,
              ),
              label: 'nav_home'.tr,
            ),
            BottomNavigationBarItem(
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedUserGroup,
                color: AppColors.textHint,
              ),
              activeIcon: const HugeIcon(
                icon: HugeIcons.strokeRoundedUserGroup,
                color: themeColor,
              ),
              label: 'nav_community'.tr,
            ),
            BottomNavigationBarItem(
              icon: Obx(() => _buildBadgeIcon(
                icon: HugeIcons.strokeRoundedBubbleChat,
                color: AppColors.textHint,
                unreadCount: imConvCtrl.totalUnreadCount.value,
              )),
              activeIcon: Obx(() => _buildBadgeIcon(
                icon: HugeIcons.strokeRoundedBubbleChat,
                color: themeColor,
                unreadCount: imConvCtrl.totalUnreadCount.value,
              )),
              label: 'nav_messages'.tr,
            ),
            BottomNavigationBarItem(
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedShoppingBag01,
                color: AppColors.textHint,
              ),
              activeIcon: const HugeIcon(
                icon: HugeIcons.strokeRoundedShoppingBag01,
                color: themeColor,
              ),
              label: 'nav_shop'.tr,
            ),
            BottomNavigationBarItem(
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedUser,
                color: AppColors.textHint,
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