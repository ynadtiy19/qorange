import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../comment/agreement_webview_page.dart';
import '../main/main_nav_view.dart';

class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> {
  bool _showPrivacy = false;

  @override
  void initState() {
    super.initState();
    _checkPrivacy();
  }

  Future<void> _checkPrivacy() async {
    final prefs = await SharedPreferences.getInstance();
    final hasAgreed = prefs.getBool('has_agreed_privacy') ?? false;

    if (!hasAgreed) {
      setState(() {
        _showPrivacy = true;
      });
      Future.delayed(const Duration(milliseconds: 500), () {
        _showPrivacyDialog();
      });
    } else {
      _initSafeSDKsAndGo();
    }
  }

  /// 🌟 闪屏页平滑过渡到主页（版本检测移入 MainNavView 执行，彻底防止弹窗被销毁）
  void _initSafeSDKsAndGo() {
    _startAnimationAndGo();
  }

  void _startAnimationAndGo() {
    Future.delayed(const Duration(milliseconds: 2000), () {
      Get.off(
            () => const MainNavView(),
        transition: Transition.fadeIn,
        duration: const Duration(milliseconds: 800),
      );
    });
  }

  void _showPrivacyDialog() {
    Get.dialog(
      PopScope(
        canPop: false,
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'privacy_title'.tr,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black54,
                      height: 1.5,
                    ),
                    children: [
                      TextSpan(text: 'privacy_welcome'.tr),
                      // 🌟 1. 用户协议
                      TextSpan(
                        text: 'user_agreement'.tr,
                        style: const TextStyle(
                          color: Color(0xFF2C7B6D),
                          fontWeight: FontWeight.w600,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () {
                            HapticFeedback.lightImpact();
                            Get.to(
                                  () => const AgreementWebViewPage(),
                              arguments: {
                                'title': 'user_agreement'.tr,
                                'url': 'https://googlechat.zeabur.app/docs/user_agreement.html',
                              },
                            );
                          },
                      ),
                      TextSpan(text: ' ${'and'.tr} '),
                      // 🌟 2. 隐私政策
                      TextSpan(
                        text: 'privacy_policy'.tr,
                        style: const TextStyle(
                          color: Color(0xFF2C7B6D),
                          fontWeight: FontWeight.w600,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () {
                            HapticFeedback.lightImpact();
                            Get.to(
                                  () => const AgreementWebViewPage(),
                              arguments: {
                                'title': 'privacy_policy'.tr,
                                'url': 'https://googlechat.zeabur.app/docs/privacy_policy.html',
                              },
                            );
                          },
                      ),
                      TextSpan(text: 'privacy_desc'.tr),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          if (Platform.isAndroid) {
                            SystemNavigator.pop();
                          } else {
                            exit(0);
                          }
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.grey,
                        ),
                        child: Text('disagree'.tr),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setBool('has_agreed_privacy', true);
                          Get.back();
                          _initSafeSDKsAndGo();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text('agree_continue'.tr),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      barrierDismissible: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F6),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'images/qorange.png',
              width: 100,
              height: 100,
            ).animate().fade(duration: 800.ms).scale(curve: Curves.easeOutBack),

            const SizedBox(height: 20),

            Text(
              'app_name'.tr,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
                color: Colors.black87,
              ),
            )
                .animate()
                .fade(delay: 400.ms, duration: 600.ms)
                .slideY(begin: 0.5, end: 0),
          ],
        ),
      ),
    );
  }
}