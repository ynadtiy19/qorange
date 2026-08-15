import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:webview_flutter/webview_flutter.dart';

class AgreementWebViewPage extends StatefulWidget {
  const AgreementWebViewPage({super.key});

  @override
  State<AgreementWebViewPage> createState() => _AgreementWebViewPageState();
}

class _AgreementWebViewPageState extends State<AgreementWebViewPage> {
  late final WebViewController _controller;

  // 响应式状态管理
  final RxInt _loadingProgress = 0.obs;
  final RxBool _hasError = false.obs;
  final RxString _title = ''.obs;

  late final String _initialUrl;

  // 平台经典主色调
  static const Color _primaryTeal = Color(0xFF2C7B6D);
  static const Color _slateText = Color(0xFF1E293B);

  @override
  void initState() {
    super.initState();
    // 从 Get.arguments 中获取标题和网址
    final args = Get.arguments as Map<String, dynamic>? ?? {};
    _title.value = args['title']?.toString() ?? '协议详情';
    _initialUrl = args['url']?.toString() ?? 'https://googlechat.zeabur.app/docs/user_agreement.html';

    _initWebViewController();
  }

  void _initWebViewController() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF8FAFC))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            _loadingProgress.value = progress;
          },
          onPageStarted: (String url) {
            _hasError.value = false;
            _loadingProgress.value = 10;
          },
          onPageFinished: (String url) {
            _loadingProgress.value = 100;
          },
          onWebResourceError: (WebResourceError error) {
            _hasError.value = true;
          },
        ),
      )
      ..loadRequest(Uri.parse(_initialUrl));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _controller.canGoBack()) {
          await _controller.goBack();
        } else {
          Get.back();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          elevation: 0,
          scrolledUnderElevation: 0.5,
          backgroundColor: Colors.white,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19, color: _slateText),
            onPressed: () async {
              HapticFeedback.lightImpact();
              if (await _controller.canGoBack()) {
                await _controller.goBack();
              } else {
                Get.back();
              }
            },
          ),
          title: Obx(
                () => Text(
              _title.value,
              style: const TextStyle(
                color: _slateText,
                fontSize: 16.5,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 22, color: Color(0xFF64748B)),
              tooltip: '刷新',
              onPressed: () {
                HapticFeedback.selectionClick();
                _controller.reload();
              },
            ),
            const SizedBox(width: 4),
          ],
          // 优雅的顶部线性渐变加载进度条
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(2.5),
            child: Obx(() {
              final isFinished = _loadingProgress.value >= 100;
              return AnimatedOpacity(
                opacity: isFinished ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 250),
                child: LinearProgressIndicator(
                  value: _loadingProgress.value / 100.0,
                  minHeight: 2.5,
                  backgroundColor: Colors.transparent,
                  valueColor: const AlwaysStoppedAnimation<Color>(_primaryTeal),
                ),
              );
            }),
          ),
        ),
        body: Obx(() {
          if (_hasError.value) {
            return _buildErrorState();
          }
          return WebViewWidget(controller: _controller);
        }),
      ),
    );
  }

  /// 优雅的断网或加载失败占位视图
  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Icon(Icons.cloud_off_rounded, size: 32, color: Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 18),
            const Text(
              '页面加载未成功',
              style: TextStyle(color: _slateText, fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              '请检查网络状态或稍后重试',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                HapticFeedback.mediumImpact();
                _hasError.value = false;
                _controller.reload();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryTeal,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: const Text('重新加载', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            ),
          ],
        ),
      ),
    );
  }
}