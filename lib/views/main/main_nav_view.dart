import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../user_controller.dart';
import '../community/community_discovery_view.dart';
import '../home/home_view.dart';
import '../login/login_controller.dart';
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

  final List<Widget> _pages = [
    const HomeView(), // 1. 首页观点/saysay大厅
    const CommunityDiscoveryView(), // 2. 社群大厅发现大厅
    const ShopView(), // 3. 商店
    const ProfileView(), // 4. 个人主页
  ];

  void _onTap(int index) async {
    // 对“我的（索引 3）”进行拦截
    if (index == 3) {
      if (!UserController.to.isLoggedIn) {
        // 🌟 路由净化：直接推入页面，LoginView 的 GetBuilder 会自动完美装载控制器
        final bool? loggedIn = await Get.to<bool>(
              () => const LoginView(),
          transition: Transition.rightToLeftWithFade,
        );

        // 登录成功后直接流畅过渡到个人中心
        if (loggedIn == true) {
          setState(() {
            _currentIndex = 3;
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
            BottomNavigationBarItem(
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedHome01,
                color: Colors.grey.shade400,
              ),
              activeIcon: const HugeIcon(
                icon: HugeIcons.strokeRoundedHome01,
                color: themeColor,
              ),
              label: '首页',
            ),
            BottomNavigationBarItem(
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedUserGroup,
                color: Colors.grey.shade400,
              ),
              activeIcon: const HugeIcon(
                icon: HugeIcons.strokeRoundedUserGroup,
                color: themeColor,
              ),
              label: '社群',
            ),
            BottomNavigationBarItem(
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedShoppingBag01,
                color: Colors.grey.shade400,
              ),
              activeIcon: const HugeIcon(
                icon: HugeIcons.strokeRoundedShoppingBag01,
                color: themeColor,
              ),
              label: '商店',
            ),
            BottomNavigationBarItem(
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedUser,
                color: Colors.grey.shade400,
              ),
              activeIcon: const HugeIcon(
                icon: HugeIcons.strokeRoundedUser,
                color: themeColor,
              ),
              label: '我的',
            ),
          ],
        ),
      ),
    );
  }
}