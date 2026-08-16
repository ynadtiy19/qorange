// lib/views/main/main_nav_view.dart
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

class MainNavView extends StatefulWidget {
  const MainNavView({super.key});

  @override
  State<MainNavView> createState() => _MainNavViewState();
}

class _MainNavViewState extends State<MainNavView> {
  int _currentIndex = 0;

  // 🌟 初始化 5 大核心主页（包含 IM 消息大厅）
  final List<Widget> _pages = [
    const HomeView(),                  // 0. 首页观点/saysay大厅
    const CommunityDiscoveryView(),    // 1. 社群发现大厅
    const ImConversationListView(),    // 2. 🌟 即时通讯消息列表
    const ShopView(),                  // 3. 商店
    const ProfileView(),               // 4. 个人主页
  ];

  @override
  void initState() {
    super.initState();
    // 注入会话未读数全局控制器
    Get.put(ImConversationController());

    // 页面完全呈现后触发版本检测
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Get.find<NotificationHandlerService>().checkForUpdate();
    });
  }

  void _onTap(int index) async {
    // 🌟 对【消息（索引 2）】与【我的（索引 4）】进行登录拦截保护
    if (index == 2 || index == 4) {
      if (!UserController.to.isLoggedIn) {
        final bool? loggedIn = await Get.to<bool>(
              () => const LoginView(),
          transition: Transition.rightToLeftWithFade,
        );

        if (loggedIn == true) {
          setState(() {
            _currentIndex = index;
          });
        }
        return;
      }
    }
    setState(() {
      _currentIndex = index;
    });
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
            // 0. 首页
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

            // 1. 社群
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

            // 2. 🌟 即时通讯消息（带动态小红点徽标）
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

            // 3. 商店
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

            // 4. 我的
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

  /// 🌟 优雅的自适应小红点徽标组件
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