import 'dart:convert';
import 'dart:io';
import 'package:at_client/at_client.dart';

class AtsignProxyBridge {
  static HttpServer? _localServer;
  static int localPort = 0;
  static String? _userJwtToken;

  /// 启动本地微型代理中转站
  static Future<int> start({required String userJwtToken}) async {
    _userJwtToken = userJwtToken;
    if (_localServer != null) return localPort;

    // 随机绑定一个空闲端口
    _localServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    localPort = _localServer!.port;
    print('🚀 [ProxyBridge] 本地桥接代理服务已启动: http://127.0.0.1:$localPort');

    _localServer!.listen(_handleLocalRequest);
    return localPort;
  }

  static void updateToken(String token) {
    _userJwtToken = token;
  }

  static void _handleLocalRequest(HttpRequest req) async {
    // 客户端通过 http://127.0.0.1:PORT/proxy?url=https://example.com 访问
    final targetUrl = req.uri.queryParameters['url'];

    if (targetUrl == null || targetUrl.isEmpty) {
      req.response
        ..statusCode = HttpStatus.badRequest
        ..write('Missing "url" parameter')
        ..close();
      return;
    }

    try {
      final atClient = AtClientManager.getInstance().atClient;
      final rpcClient = AtRpcClient(
        atClient: atClient,
        baseNameSpace: 'atsign',
        domainNameSpace: 'at_rpc_secure_proxy',
        serverAtsign: '@absolute3140', // 你的后端服务 AtSign
      );

      // 读取请求体（如 POST 请求）
      final requestBytes = await req.expand((chunk) => chunk).toList();

      // 提取请求头
      final Map<String, String> headers = {};
      req.headers.forEach((key, values) {
        if (key != 'host' && key != 'connection') {
          headers[key] = values.join(';');
        }
      });

      // 封装为 AtSign 加密请求帧
      final reqPayload = {
        'version': '1.0',
        'action': 'HTTP_REQUEST',
        'session_id': 'sess_${DateTime.now().millisecondsSinceEpoch}',
        'auth': {'token': _userJwtToken ?? ''},
        'payload': {
          'method': req.method,
          'url': targetUrl,
          'headers': headers,
          'body_base64': requestBytes.isNotEmpty ? base64Encode(requestBytes) : null,
          'timeout_ms': 15000,
        }
      };

      // 🌟 物理走 AtSign E2EE 加密通道代请求
      final rpcResponse = await rpcClient.call(reqPayload);

      final payload = rpcResponse['payload'] as Map<String, dynamic>? ?? {};
      final int proxyCode = payload['proxy_code'] ?? -1;

      if (proxyCode == 0) {
        final int statusCode = payload['status_code'] ?? 200;
        final respHeaders = payload['headers'] as Map? ?? {};
        final String? bodyBase64 = payload['body_base64'];

        req.response.statusCode = statusCode;

        // 透传 Response Header
        respHeaders.forEach((k, v) {
          req.response.headers.set(k.toString(), v.toString());
        });

        // 输出响应二进制内容
        if (bodyBase64 != null && bodyBase64.isNotEmpty) {
          req.response.add(base64Decode(bodyBase64));
        }
      } else {
        req.response.statusCode = HttpStatus.badGateway;
        req.response.headers.contentType = ContentType.html;
        req.response.write('''
          <div style="font-family:sans-serif; text-align:center; padding:50px;">
            <h2>🛡️ 代理通道拦截</h2>
            <p style="color:#666;">错误码: $proxyCode | ${payload['proxy_msg']}</p>
          </div>
        ''');
      }
    } catch (e) {
      req.response
        ..statusCode = HttpStatus.internalServerError
        ..write('Proxy Bridge Error: $e');
    } finally {
      await req.response.close();
    }
  }

  static void stop() {
    _localServer?.close(force: true);
    _localServer = null;
  }
}