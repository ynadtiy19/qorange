import 'dart:convert';
import 'dart:typed_data';
import 'package:at_client/at_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../network/secure_storage_manager.dart';

class AtsignBrowserPage extends StatefulWidget {
  final String initialUrl;

  const AtsignBrowserPage({
    super.key,
    this.initialUrl = 'https://news.ycombinator.com',
  });

  @override
  State<AtsignBrowserPage> createState() => _AtsignBrowserPageState();
}

class _AtsignBrowserPageState extends State<AtsignBrowserPage> {
  final TextEditingController _urlController = TextEditingController();
  InAppWebViewController? _webViewController;

  double _progress = 0.0;
  bool _isLoading = false;
  String _currentDisplayUrl = '';

  @override
  void initState() {
    super.initState();
    _currentDisplayUrl = widget.initialUrl;
    _urlController.text = widget.initialUrl;
  }

  void _navigateToUrl(String rawUrl) {
    String formattedUrl = rawUrl.trim();
    if (!formattedUrl.startsWith('http://') && !formattedUrl.startsWith('https://')) {
      formattedUrl = 'https://$formattedUrl';
    }
    _urlController.text = formattedUrl;
    _currentDisplayUrl = formattedUrl;
    _webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(formattedUrl)));
  }

  /// 🌟 核心拦截核心：网页里发出的任意主请求、图片、CSS、JS 全部由 Dart 接管走 AtSign
  Future<WebResourceResponse?> _handleInterceptedRequest(
      WebResourceRequest request,
      ) async {
    final targetUrl = request.url.toString();

    // 忽略非 HTTP/HTTPS 协议（如 data:, blob:, chrome:）
    if (!targetUrl.startsWith('http://') && !targetUrl.startsWith('https://')) {
      return null;
    }

    try {
      final token = await SecureStorageManager.instance.getAccessToken() ?? '';
      final atClient = AtClientManager.getInstance().atClient;
      final rpcClient = AtRpcClient(
        atClient: atClient,
        baseNameSpace: 'atsign',
        domainNameSpace: 'at_rpc_secure_proxy',
        serverAtsign: '@absolute3140',
      );

      // 将 WebView 产生的请求封装为 AtSign 加密包
      final reqPayload = {
        'version': '1.0',
        'action': 'HTTP_REQUEST',
        'session_id': 'sess_${DateTime.now().millisecondsSinceEpoch}',
        'auth': {'token': token},
        'payload': {
          'method': request.method ?? 'GET',
          'url': targetUrl,
          'headers': request.headers ?? {},
          'timeout_ms': 15000,
        }
      };

      // 🌟 物理走 AtSign 远端代理获取数据
      final rpcResponse = await rpcClient.call(reqPayload);
      final payload = (rpcResponse['payload'] is Map)
          ? Map<String, dynamic>.from(rpcResponse['payload'] as Map)
          : Map<String, dynamic>.from(rpcResponse);

      if (payload['proxy_code'] == 0) {
        final int statusCode = payload['status_code'] ?? 200;
        final respHeaders = Map<String, String>.from(payload['headers'] ?? {});
        final String? bodyBase64 = payload['body_base64'];

        if (bodyBase64 != null && bodyBase64.isNotEmpty) {
          final Uint8List dataBytes = base64Decode(bodyBase64);

          // 提取真实 Content-Type (如 text/html, image/png, text/css)
          String contentType = respHeaders['content-type'] ?? 'text/html';
          if (contentType.contains(';')) {
            contentType = contentType.split(';').first.trim();
          }

          // 🌟 将代理抓到的资源以原生响应流喂回给 WebView 渲染！
          return WebResourceResponse(
            contentType: contentType,
            contentEncoding: 'utf-8',
            data: dataBytes,
            statusCode: statusCode,
            reasonPhrase: 'OK',
            headers: respHeaders,
          );
        }
      }
    } catch (e) {
      debugPrint('🔴 [Proxy Intercept Error] 资源 $targetUrl 加载失败: $e');
    }

    // 失败时返回空响应，防止直连泄漏
    return WebResourceResponse(
      contentType: 'text/plain',
      data: Uint8List(0),
      statusCode: 502,
      reasonPhrase: 'Proxy Failed',
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopNavigationBar(),
            if (_isLoading)
              LinearProgressIndicator(
                value: _progress,
                minHeight: 2.5,
                backgroundColor: Colors.transparent,
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
              ),
            Expanded(
              child: InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(widget.initialUrl)),
                initialSettings: InAppWebViewSettings(
                  isInspectable: true,
                  // 🌟 启用原生网络拦截引擎
                  useShouldInterceptRequest: true,
                  mediaPlaybackRequiresUserGesture: false,
                  allowsInlineMediaPlayback: true,
                  cacheEnabled: true,
                ),
                onWebViewCreated: (controller) => _webViewController = controller,
                onLoadStart: (controller, url) {
                  setState(() {
                    _isLoading = true;
                    if (url != null) _urlController.text = url.toString();
                  });
                },
                onProgressChanged: (controller, progress) {
                  setState(() => _progress = progress / 100.0);
                },
                onLoadStop: (controller, url) {
                  setState(() {
                    _isLoading = false;
                    if (url != null) _urlController.text = url.toString();
                  });
                },
                // 🌟🌟 核心魔法：拦截 WebView 发起的所有请求并送入 AtSign 🌟🌟
                shouldInterceptRequest: (controller, request) async {
                  return await _handleInterceptedRequest(request);
                },
              ),
            ),
            _buildBottomControlDock(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopNavigationBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        border: Border(bottom: BorderSide(color: Color(0xFF334155), width: 0.8)),
      ),
      child: Row(
        children: [
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
                Text('E2EE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
              ],
            ),
          ),
          const SizedBox(width: 10),
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
                        hintText: '输入网址...',
                        hintStyle: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onSubmitted: (val) => _navigateToUrl(val),
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
          InkWell(
            onTap: () => _webViewController?.reload(),
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
              if (await _webViewController?.canGoBack() ?? false) {
                _webViewController?.goBack();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
            color: const Color(0xFF94A3B8),
            onPressed: () async {
              if (await _webViewController?.canGoForward() ?? false) {
                _webViewController?.goForward();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.home_rounded, size: 22),
            color: const Color(0xFF94A3B8),
            onPressed: () => _navigateToUrl(widget.initialUrl),
          ),
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
                Text('AtSign Proxy', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFCBD5E1))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}