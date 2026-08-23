// lib/browser/atsign_browser_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_client/at_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  static const String fromAtsign = '@gemini2banana';
  static const String toAtsign = '@absolute3140';
  static const String nameSpace = 'atsign';
  static const String _historyStorageKey = 'browser_history_records_v2';

  // 🌟 钛金极简配色定义
  static const Color cBg = Color(0xFF0D0F14);        // 纯粹深空黑底
  static const Color cBarBg = Color(0xFF161922);     // 顶底栏曜石灰
  static const Color cInputBg = Color(0xFF202430);   // 输入框胶囊暗底
  static const Color cBorder = Color(0xFF2C3242);    // 微弱精细边框
  static const Color cAccent = Color(0xFF3B82F6);    // 极客冰蓝强调色
  static const Color cTextMain = Color(0xFFFFFFFF);  // 纯白高对比文字
  static const Color cTextMuted = Color(0xFF8C96A8); // 高级钛金灰提示字

  final TextEditingController _urlController = TextEditingController();
  final FocusNode _urlFocusNode = FocusNode();
  InAppWebViewController? _webViewController;
  StreamSubscription? _proxySub;

  final Map<String, Completer<WebResourceResponse>> _pendingRequests = {};
  List<Map<String, String>> _historyList = [];

  double _progress = 0.0;
  bool _isLoading = false;
  String _currentDisplayUrl = '';
  bool _canGoBack = false;
  bool _canGoForward = false;

  @override
  void initState() {
    super.initState();
    _currentDisplayUrl = widget.initialUrl;
    _urlController.text = widget.initialUrl;

    _loadHistoryFromStorage();
    _initResponseListener();
  }

  @override
  void dispose() {
    _proxySub?.cancel();
    _urlController.dispose();
    _urlFocusNode.dispose();
    super.dispose();
  }

  // =========================================================
  // 1. 历史记录管理
  // =========================================================
  Future<void> _loadHistoryFromStorage() async {
    try {
      final jsonStr = await SecureStorageManager.instance.getString(_historyStorageKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(jsonStr);
        if (mounted) {
          setState(() {
            _historyList = decoded.map((e) => Map<String, String>.from(e as Map)).toList();
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _saveHistoryItem(String url, {String? title}) async {
    if (url.isEmpty || url.startsWith('about:')) return;
    try {
      final cleanUrl = url.trim();
      _historyList.removeWhere((item) => item['url'] == cleanUrl);
      _historyList.insert(0, {
        'url': cleanUrl,
        'title': (title != null && title.isNotEmpty) ? title : _extractDomain(cleanUrl),
        'time': DateTime.now().toIso8601String(),
      });

      if (_historyList.length > 30) {
        _historyList = _historyList.sublist(0, 30);
      }

      await SecureStorageManager.instance.saveString(
        _historyStorageKey,
        jsonEncode(_historyList),
      );
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _deleteHistoryItem(int index) async {
    try {
      _historyList.removeAt(index);
      await SecureStorageManager.instance.saveString(
        _historyStorageKey,
        jsonEncode(_historyList),
      );
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _clearAllHistory() async {
    try {
      _historyList.clear();
      await SecureStorageManager.instance.delete(_historyStorageKey);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  String _extractDomain(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.isNotEmpty ? uri.host : url;
    } catch (_) {
      return url;
    }
  }

  // =========================================================
  // 2. AtSign 代理回包监听与请求处理
  // =========================================================
  void _initResponseListener() {
    final atClient = AtClientManager.getInstance().atClient;
    const regex = 'proxy_resp_.*\\.$nameSpace@';

    _proxySub = atClient.notificationService
        .subscribe(regex: regex, shouldDecrypt: true)
        .listen((notification) {
      final jsonVal = notification.value;
      if (jsonVal == null || jsonVal.isEmpty) return;

      try {
        final data = jsonDecode(jsonVal) as Map<String, dynamic>;
        final String? reqId = data['req_id']?.toString();

        if (reqId != null && _pendingRequests.containsKey(reqId)) {
          final completer = _pendingRequests.remove(reqId)!;
          final int statusCode = data['status_code'] ?? 200;
          final String contentType = data['content_type'] ?? 'text/html';
          final String bodyBase64 = data['body_base64'] ?? '';
          final headers = Map<String, String>.from(data['headers'] ?? {});

          final Uint8List responseBytes =
          bodyBase64.isNotEmpty ? base64Decode(bodyBase64) : Uint8List(0);

          String cleanMime = contentType.split(';').first.trim();

          completer.complete(
            WebResourceResponse(
              contentType: cleanMime,
              contentEncoding: 'utf-8',
              data: responseBytes,
              statusCode: statusCode,
              reasonPhrase: 'OK',
              headers: headers,
            ),
          );
        }
      } catch (e) {
        debugPrint('🔴 解析响应异常: $e');
      }
    });
  }

  Future<WebResourceResponse?> _handleInterceptedRequest(
      WebResourceRequest request,
      ) async {
    final targetUrl = request.url.toString();
    if (!targetUrl.startsWith('http://') && !targetUrl.startsWith('https://')) {
      return null;
    }

    try {
      final token = await SecureStorageManager.instance.getAccessToken() ?? '';
      final atClient = AtClientManager.getInstance().atClient;

      final String reqId =
          'req_${DateTime.now().millisecondsSinceEpoch}_${_pendingRequests.length}';
      final String uniqueSuffix = '${DateTime.now().microsecondsSinceEpoch}';
      final String keyName = 'proxy_req_${reqId}_$uniqueSuffix';

      final payload = {
        'req_id': reqId,
        'token': token,
        'url': targetUrl,
        'method': request.method ?? 'GET',
        'headers': request.headers ?? {},
      };

      final metaData = Metadata()..ttr = -1;
      final key = AtKey()
        ..key = keyName
        ..sharedBy = fromAtsign
        ..sharedWith = toAtsign
        ..namespace = nameSpace
        ..metadata = metaData;

      final completer = Completer<WebResourceResponse>();
      _pendingRequests[reqId] = completer;

      await atClient.notificationService.notify(
        NotificationParams.forUpdate(key, value: jsonEncode(payload)),
        checkForFinalDeliveryStatus: false,
        waitForFinalDeliveryStatus: false,
      );

      return await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          _pendingRequests.remove(reqId);
          return WebResourceResponse(
            contentType: 'text/plain',
            data: Uint8List(0),
            statusCode: 504,
            reasonPhrase: 'Gateway Timeout',
          );
        },
      );
    } catch (e) {
      debugPrint('🔴 发送代理请求异常: $e');
      return WebResourceResponse(
        contentType: 'text/plain',
        data: Uint8List(0),
        statusCode: 502,
        reasonPhrase: 'Proxy Failed',
      );
    }
  }

  void _navigateToUrl(String rawUrl) {
    _urlFocusNode.unfocus();
    String formattedUrl = rawUrl.trim();
    if (formattedUrl.isEmpty) return;

    if (!formattedUrl.startsWith('http://') && !formattedUrl.startsWith('https://')) {
      if (formattedUrl.contains('.') && !formattedUrl.contains(' ')) {
        formattedUrl = 'https://$formattedUrl';
      } else {
        formattedUrl = 'https://www.google.com/search?q=${Uri.encodeComponent(formattedUrl)}';
      }
    }

    _urlController.text = formattedUrl;
    _currentDisplayUrl = formattedUrl;
    _saveHistoryItem(formattedUrl);
    _webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(formattedUrl)));
  }

  // =========================================================
  // 3. 全新现代极简 UI 设计
  // =========================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: SafeArea(
        child: Column(
          children: [
            // 🌟 1. 钛金极简质感顶部栏
            _buildTopAppBar(),

            // 🌟 2. 极细冰蓝加载线
            _buildLoadingProgress(),

            // 🌟 3. 主 WebView
            Expanded(
              child: InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(widget.initialUrl)),
                initialSettings: InAppWebViewSettings(
                  isInspectable: true,
                  useShouldInterceptRequest: true,
                  mediaPlaybackRequiresUserGesture: false,
                  allowsInlineMediaPlayback: true,
                  cacheEnabled: true,
                  transparentBackground: true,
                ),
                onWebViewCreated: (controller) => _webViewController = controller,
                onLoadStart: (controller, url) {
                  if (mounted) {
                    setState(() {
                      _isLoading = true;
                      if (url != null) {
                        final u = url.toString();
                        _urlController.text = u;
                        _currentDisplayUrl = u;
                      }
                    });
                  }
                },
                onTitleChanged: (controller, title) {
                  if (title != null && title.isNotEmpty) {
                    _saveHistoryItem(_currentDisplayUrl, title: title);
                  }
                },
                onProgressChanged: (controller, progress) {
                  if (mounted) setState(() => _progress = progress / 100.0);
                },
                onLoadStop: (controller, url) async {
                  final canBack = await controller.canGoBack();
                  final canFwd = await controller.canGoForward();
                  if (mounted) {
                    setState(() {
                      _isLoading = false;
                      _canGoBack = canBack;
                      _canGoForward = canFwd;
                      if (url != null) {
                        final u = url.toString();
                        _urlController.text = u;
                        _currentDisplayUrl = u;
                      }
                    });
                  }
                },
                shouldInterceptRequest: (controller, request) async {
                  return await _handleInterceptedRequest(request);
                },
              ),
            ),

            // 🌟 4. 底部微质感控制栏
            _buildBottomControlBar(),
          ],
        ),
      ),
    );
  }

  /// 重新打造的极简高质感顶部输入栏
  Widget _buildTopAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: cBarBg,
        border: Border(bottom: BorderSide(color: cBorder, width: 0.8)),
      ),
      child: Row(
        children: [
          // 🛡️ 钛金质感 E2EE 胶囊（摒弃荧光绿）
          Material(
            color: cInputBg,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _showSecurityDialog,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cBorder, width: 0.8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shield_outlined, size: 13, color: cAccent),
                    SizedBox(width: 4),
                    Text(
                      'E2EE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: cTextMain,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // 🔍 彻底清除原生白底的纯净暗色输入胶囊
          Expanded(
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                color: cInputBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _urlFocusNode.hasFocus ? cAccent : cBorder,
                  width: _urlFocusNode.hasFocus ? 1.2 : 0.8,
                ),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 10),
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 15,
                    color: _urlFocusNode.hasFocus ? cAccent : cTextMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _urlController,
                      focusNode: _urlFocusNode,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.go,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w400,
                        color: cTextMain, // 纯白高对比输入字
                      ),
                      cursorColor: cAccent,
                      decoration: const InputDecoration(
                        isDense: true,
                        filled: false, // 🌟 彻底禁用可能导致白块的默认背景填充
                        hintText: '搜索或输入网址...',
                        hintStyle: TextStyle(
                          fontSize: 13,
                          color: cTextMuted, // 舒适可见的钛灰占位字
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                      onSubmitted: (val) => _navigateToUrl(val),
                    ),
                  ),
                  if (_urlController.text.isNotEmpty)
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          _urlController.clear();
                          setState(() {});
                        },
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(Icons.close_rounded, size: 15, color: cTextMuted),
                        ),
                      ),
                    ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),

          // 🔄 刷新 / 停止按钮
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                HapticFeedback.lightImpact();
                if (_isLoading) {
                  _webViewController?.stopLoading();
                } else {
                  _webViewController?.reload();
                }
              },
              child: Padding(
                padding: const EdgeInsets.all(7),
                child: Icon(
                  _isLoading ? Icons.close_rounded : Icons.refresh_rounded,
                  size: 20,
                  color: cTextMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 细线加载指示
  Widget _buildLoadingProgress() {
    if (!_isLoading) return const SizedBox(height: 2);
    return SizedBox(
      height: 2,
      child: LinearProgressIndicator(
        value: _progress,
        backgroundColor: Colors.transparent,
        valueColor: const AlwaysStoppedAnimation<Color>(cAccent),
      ),
    );
  }

  /// 底部控制底栏
  Widget _buildBottomControlBar() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: cBarBg,
        border: Border(top: BorderSide(color: cBorder, width: 0.8)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildNavButton(
            icon: Icons.arrow_back_ios_new_rounded,
            isEnabled: _canGoBack,
            onTap: () async {
              if (await _webViewController?.canGoBack() ?? false) {
                _webViewController?.goBack();
              }
            },
          ),
          _buildNavButton(
            icon: Icons.arrow_forward_ios_rounded,
            isEnabled: _canGoForward,
            onTap: () async {
              if (await _webViewController?.canGoForward() ?? false) {
                _webViewController?.goForward();
              }
            },
          ),
          _buildNavButton(
            icon: Icons.home_outlined,
            isEnabled: true,
            onTap: () => _navigateToUrl(widget.initialUrl),
          ),
          _buildNavButton(
            icon: Icons.history_rounded,
            isEnabled: true,
            onTap: _showHistoryBottomSheet,
          ),
          _buildNavButton(
            icon: Icons.share_outlined,
            isEnabled: true,
            onTap: () {
              if (_currentDisplayUrl.isNotEmpty) {
                Clipboard.setData(ClipboardData(text: _currentDisplayUrl));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('已复制: $_currentDisplayUrl'),
                    duration: const Duration(seconds: 2),
                    backgroundColor: cInputBg,
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNavButton({
    required IconData icon,
    required bool isEnabled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: isEnabled
            ? () {
          HapticFeedback.selectionClick();
          onTap();
        }
            : null,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            icon,
            size: 19,
            color: isEnabled ? cTextMain : const Color(0xFF4B5565),
          ),
        ),
      ),
    );
  }

  // =========================================================
  // 4. 历史记录抽屉与安全态势弹窗
  // =========================================================
  void _showHistoryBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.65,
          decoration: const BoxDecoration(
            color: cBarBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(top: BorderSide(color: cBorder, width: 1)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF4B5565),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.history_rounded, size: 18, color: cAccent),
                        SizedBox(width: 8),
                        Text(
                          '访问历史',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: cTextMain,
                          ),
                        ),
                      ],
                    ),
                    if (_historyList.isNotEmpty)
                      TextButton.icon(
                        onPressed: () {
                          _clearAllHistory();
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.delete_outline, size: 15, color: Color(0xFFF43F5E)),
                        label: const Text(
                          '清空',
                          style: TextStyle(fontSize: 12.5, color: Color(0xFFF43F5E)),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(color: cBorder, height: 1),

              Expanded(
                child: _historyList.isEmpty
                    ? const Center(
                  child: Text('暂无历史记录', style: TextStyle(color: cTextMuted, fontSize: 13.5)),
                )
                    : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: _historyList.length,
                  separatorBuilder: (_, __) => const Divider(color: cBorder, indent: 52),
                  itemBuilder: (context, index) {
                    final item = _historyList[index];
                    final url = item['url'] ?? '';
                    final title = item['title'] ?? url;

                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          Navigator.pop(context);
                          _navigateToUrl(url);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: cInputBg,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Icon(Icons.public, size: 16, color: cAccent),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w500,
                                        color: cTextMain,
                                      ),
                                    ),
                                    Text(
                                      url,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: cTextMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, size: 15, color: cTextMuted),
                                onPressed: () => _deleteHistoryItem(index),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSecurityDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: cBarBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.shield_outlined, color: cAccent, size: 20),
              SizedBox(width: 8),
              Text(
                'AtSign E2EE 隧道保护中',
                style: TextStyle(color: cTextMain, fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: const Text(
            '• 传输加密：流量全程经过 AtSign 非对称双密钥端到端加密。\n'
                '• 零端口暴露：无需开放代理端口，杜绝流量特征嗅探。\n'
                '• 防火墙保护：原生拦截内网渗透与恶意追踪代码。',
            style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 12.5, height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('我知道了', style: TextStyle(color: cAccent, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }
}