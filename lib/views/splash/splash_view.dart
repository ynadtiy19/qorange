import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
                const Text(
                  "服务协议与隐私政策",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                RichText(
                  text: const TextSpan(
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black54,
                      height: 1.5,
                    ),
                    children: [
                      TextSpan(text: "欢迎使用 青橙！在您使用前，请仔细阅读"),
                      TextSpan(
                        text: "《用户协议》",
                        style: TextStyle(color: Colors.blueAccent),
                      ),
                      TextSpan(text: "和"),
                      TextSpan(
                        text: "《隐私政策》",
                        style: TextStyle(color: Colors.blueAccent),
                      ),
                      TextSpan(text: "。我们将严格按照政策要求保护您的个人信息安全。"),
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
                        child: const Text("不同意"),
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
                        child: const Text("同意并继续"),
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

            const Text(
              "青橙",
              style: TextStyle(
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