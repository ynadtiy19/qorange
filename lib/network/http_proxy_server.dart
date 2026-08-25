// lib/network/http_proxy_server.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

/// 纯 Dart 实现的标准 HTTP/HTTPS (CONNECT) 代理服务器
class HttpProxyServer {
  final SSHClient sshClient;
  ServerSocket? _serverSocket;
  int? port;

  HttpProxyServer({required this.sshClient});

  /// 启动监听本地回环地址
  Future<int> start() async {
    _serverSocket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    port = _serverSocket!.port;
    debugPrint("🟢 [HttpProxyServer] 本地 HTTP/HTTPS 代理已就绪，监听端口: 127.0.0.1:$port");

    _serverSocket!.listen(_handleClient, onError: (e) {
      debugPrint("🔴 [HttpProxyServer] 服务异常: $e");
    });

    return port!;
  }

  void _handleClient(Socket client) async {
    try {
      final stream = client.asBroadcastStream();
      final iterator = StreamIterator(stream);

      // 读取 HTTP/HTTPS CONNECT 头部
      if (!await iterator.moveNext()) {
        client.destroy();
        return;
      }

      final List<int> initialData = iterator.current;
      final String headerStr = utf8.decode(initialData, allowMalformed: true);
      final String firstLine = headerStr.split('\n').first.trim();
      final List<String> parts = firstLine.split(' ');

      if (parts.length < 2) {
        client.destroy();
        return;
      }

      final String method = parts[0].toUpperCase();
      final String target = parts[1];

      String host = '';
      int targetPort = 443;

      if (method == 'CONNECT') {
        // HTTPS 代理请求: CONNECT www.youtube.com:443 HTTP/1.1
        final hostParts = target.split(':');
        host = hostParts[0];
        targetPort = hostParts.length > 1 ? (int.tryParse(hostParts[1]) ?? 443) : 443;
      } else {
        // 普通 HTTP 请求: GET http://example.com/path HTTP/1.1
        final uri = Uri.tryParse(target);
        if (uri != null && uri.host.isNotEmpty) {
          host = uri.host;
          targetPort = uri.port != 0 ? uri.port : 80;
        }
      }

      if (host.isEmpty) {
        client.destroy();
        return;
      }

      // 🌟 通过 SSH 向 Zeabur 建立动态转发通道 (direct-tcpip)
      final SSHForwardChannel forwardChannel = await sshClient.forwardLocal(host, targetPort);

      if (method == 'CONNECT') {
        // 回复 200 Connection Established
        client.write("HTTP/1.1 200 Connection Established\r\n\r\n");
        await client.flush();
      } else {
        forwardChannel.sink.add(initialData);
      }

      // 🌟 双向流全双工管道
      client.listen(
            (chunk) => forwardChannel.sink.add(chunk),
        onError: (_) => forwardChannel.close(),
        onDone: () => forwardChannel.close(),
        cancelOnError: true,
      );

      forwardChannel.stream.listen(
            (chunk) => client.add(chunk),
        onError: (_) => client.destroy(),
        onDone: () => client.destroy(),
        cancelOnError: true,
      );
    } catch (e) {
      client.destroy();
    }
  }

  Future<void> stop() async {
    await _serverSocket?.close();
    _serverSocket = null;
    port = null;
    debugPrint("🔌 [HttpProxyServer] 本地代理已安全关闭");
  }
}