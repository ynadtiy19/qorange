import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../network/secure_storage_manager.dart';
import 'atsign_proxy_bridge.dart';

class AtsignBrowserPage extends StatefulWidget {
  final String initialUrl;

  // 🌟 移除 userJwtToken 必传参数，支持 const 构造
  const AtsignBrowserPage({
    super.key,
    this.initialUrl = 'https://news.ycombinator.com',
  });

  @override
  State<AtsignBrowserPage> createState() => _AtsignBrowserPageState();
}

class _AtsignBrowserPageState extends State<AtsignBrowserPage> {
  final TextEditingController _urlController = TextEditingController();
  late final WebViewController _webViewController;

  double _progress = 0.0;
  bool _isLoading = false;
  String _currentDisplayUrl = '';
  int _localProxyPort = 0;

  @override
  void initState() {
    super.initState();
    _currentDisplayUrl = widget.initialUrl;
    _urlController.text = widget.initialUrl;

    // 1. 初始化 webview_flutter 控制器及其代理拦截配置
    _initWebViewController();

    // 2. 启动本地 AtSign 桥接代理服务
    _initBridge();
  }

  void _initWebViewController() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0F172A))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            setState(() {
              _progress = progress / 100.0;
            });
          },
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('WebView 资源加载异常: ${error.description}');
          },
          // 🌟 核心拦截：拦截网页内部的所有点击跳转，强制重新打包送入 AtSign 代理桥
          onNavigationRequest: (NavigationRequest request) {
            final uriStr = request.url;
            // 如果不是请求本机的代理端口，说明是网页内的外部超链接或重定向
            if (!uriStr.startsWith('http://127.0.0.1')) {
              _loadUrl(uriStr);
              return NavigationDecision.prevent; // 阻止直接发起无代理请求
            }
            return NavigationDecision.navigate;
          },
        ),
      );
  }

  // 🌟 核心改动：直接从 SecureStorageManager 读取有效 Token
  Future<void> _initBridge() async {
    final token = await SecureStorageManager.instance.getAccessToken() ?? '';

    final port = await AtsignProxyBridge.start(userJwtToken: token);
    setState(() {
      _localProxyPort = port;
    });
    _loadUrl(widget.initialUrl);
  }

  /// 将真实网址封装为本地代理中转 URL
  void _loadUrl(String rawUrl) {
    String formattedUrl = rawUrl.trim();
    if (!formattedUrl.startsWith('http://') && !formattedUrl.startsWith('https://')) {
      formattedUrl = 'https://$formattedUrl';
    }

    _urlController.text = formattedUrl;
    _currentDisplayUrl = formattedUrl;

    if (_localProxyPort > 0) {
      final proxiedUri = Uri.parse(
        'http://127.0.0.1:$_localProxyPort/proxy?url=${Uri.encodeComponent(formattedUrl)}',
      );
      _webViewController.loadRequest(proxiedUri);
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // 深空灰底色
      body: SafeArea(
        child: Column(
          children: [
            // 🌟 1. 顶部极客风/Safari 感浮动地址栏
            _buildTopNavigationBar(),

            // 🌟 2. 细线加载进度条 (带有呼吸发光感)
            if (_isLoading)
              LinearProgressIndicator(
                value: _progress,
                minHeight: 2.5,
                backgroundColor: Colors.transparent,
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
              ),

            // 🌟 3. 主 WebView 渲染视口
            Expanded(
              child: _localProxyPort == 0
                  ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF2C7B6D)),
              )
                  : WebViewWidget(
                controller: _webViewController,
              ),
            ),

            // 🌟 4. 底部浏览控制坞 (Bottom Action Dock)
            _buildBottomControlDock(),
          ],
        ),
      ),
    );
  }

  /// 顶部精美地址栏组件
  Widget _buildTopNavigationBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        border: Border(bottom: BorderSide(color: Color(0xFF334155), width: 0.8)),
      ),
      child: Row(
        children: [
          // E2EE 加密盾牌徽章
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.shield_outlined, size: 13, color: Color(0xFF10B981)),
                SizedBox(width: 4),
                Text(
                  'E2EE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF10B981),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // 核心胶囊地址输入框
          Expanded(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF475569), width: 0.8),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  const Icon(Icons.lock_rounded, size: 14, color: Color(0xFF94A3B8)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _urlController,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.go,
                      style: const TextStyle(fontSize: 13, color: Color(0xFFF8FAFC)),
                      decoration: const InputDecoration(
                        hintText: '输入网址或搜索内容...',
                        hintStyle: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onSubmitted: (val) => _loadUrl(val),
                    ),
                  ),
                  if (_urlController.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.cancel, size: 15, color: Color(0xFF64748B)),
                      onPressed: () => _urlController.clear(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  const SizedBox(width: 10),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),

          // 刷新 / 停止按钮
          InkWell(
            onTap: () {
              if (_isLoading) {
                _webViewController.reload();
              } else {
                _loadUrl(_currentDisplayUrl);
              }
            },
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(
                _isLoading ? Icons.close : Icons.refresh_rounded,
                size: 20,
                color: const Color(0xFF94A3B8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 底部控制底栏
  Widget _buildBottomControlDock() {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        border: Border(top: BorderSide(color: Color(0xFF334155), width: 0.8)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            color: const Color(0xFF94A3B8),
            onPressed: () async {
              if (await _webViewController.canGoBack()) {
                _webViewController.goBack();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
            color: const Color(0xFF94A3B8),
            onPressed: () async {
              if (await _webViewController.canGoForward()) {
                _webViewController.goForward();
              }
            },
          ),
          // 快捷主页
          IconButton(
            icon: const Icon(Icons.home_rounded, size: 22),
            color: const Color(0xFF94A3B8),
            onPressed: () => _loadUrl(widget.initialUrl),
          ),
          // 代理计费与通道状态指示
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: const Row(
              children: [
                Icon(Icons.bolt_rounded, size: 13, color: Color(0xFFF59E0B)),
                SizedBox(width: 4),
                Text(
                  'AtSign Proxy',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFCBD5E1),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}