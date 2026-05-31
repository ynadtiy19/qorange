import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../user_controller.dart';
import '../home/home_view.dart';
import '../login/login_view.dart';
import '../profile/profile_view.dart';
import '../shop/shop_view.dart'; // 🌟 引入新商店页面

class MainNavView extends StatefulWidget {
  const MainNavView({super.key});

  @override
  State<MainNavView> createState() => _MainNavViewState();
}

class _MainNavViewState extends State<MainNavView> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const HomeView(), // 首页列表
    const ShopView(), // 🌟 细节精美交互舒爽的商店页面
    const ProfileView(), // 个人主页
  ];

  void _onTap(int index) {
    if (index == 2) { // 将"我的"检查迁移至索引 2
      if (!UserController.to.isLoggedIn) {
        Get.to(
              () => const LoginView(),
          transition: Transition.rightToLeftWithFade,
        );
        return;
      }
    }
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
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
          selectedItemColor: const Color.fromRGBO(44, 123, 109, 1.0),
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
                color: Color.fromRGBO(44, 123, 109, 1.0),
              ),
              label: '首页',
            ),
            BottomNavigationBarItem(
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedShoppingBag01, // 🌟 使用精美商店图标
                color: Colors.grey.shade400,
              ),
              activeIcon: HugeIcon(
                icon: HugeIcons.strokeRoundedShoppingBag01,
                color: const Color.fromRGBO(44, 123, 109, 1.0),
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
                color: Color.fromRGBO(44, 123, 109, 1.0),
              ),
              label: '我的',
            ),
          ],
        ),
      ),
    );
  }
}