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

    _serverSocket!.listen(_handleConnection, onError: (e) {
      debugPrint("🔴 [HttpProxyServer] 服务异常: $e");
    });

    return port!;
  }

  void _handleConnection(Socket client) async {
    bool isConnected = false;
    SSHForwardChannel? forwardChannel;

    try {
      final List<int> buffer = [];

      final subscription = client.listen(
        null,
        onError: (_) {
          client.destroy();
          forwardChannel?.close();
        },
        onDone: () {
          client.destroy();
          forwardChannel?.close();
        },
        cancelOnError: true,
      );

      subscription.onData((data) async {
        if (!isConnected) {
          buffer.addAll(data);
          final headerStr = utf8.decode(buffer, allowMalformed: true);

          // 判断是否已经读到 HTTP 头部的结尾 (\r\n\r\n)
          if (headerStr.contains('\r\n\r\n') || headerStr.contains('\n\n')) {
            final firstLine = headerStr.split('\n').first.trim();
            final parts = firstLine.split(' ');

            if (parts.length >= 2) {
              final method = parts[0].toUpperCase();
              final target = parts[1];

              String host = '';
              int targetPort = 80;

              if (method == 'CONNECT') {
                // HTTPS 请求：CONNECT www.youtube.com:443 HTTP/1.1
                final hostParts = target.split(':');
                host = hostParts[0];
                targetPort = hostParts.length > 1 ? (int.tryParse(hostParts[1]) ?? 443) : 443;
              } else {
                // 普通 HTTP 请求：GET http://example.com/path HTTP/1.1
                final uri = Uri.tryParse(target);
                if (uri != null && uri.host.isNotEmpty) {
                  host = uri.host;
                  targetPort = uri.port != 0 ? uri.port : 80;
                }
              }

              if (host.isNotEmpty) {
                try {
                  // 🌟 通过 SSH 向 Zeabur 建立动态转发通道
                  forwardChannel = await sshClient.forwardLocal(host, targetPort);

                  if (method == 'CONNECT') {
                    // 告知客户端 HTTPS 隧道已建立
                    client.write("HTTP/1.1 200 Connection Established\r\n\r\n");
                    await client.flush();
                  } else {
                    // 转发原始普通 HTTP 请求
                    forwardChannel!.sink.add(buffer);
                  }

                  isConnected = true;

                  // 🌟 双向全双工流直通管道
                  forwardChannel!.stream.listen(
                        (chunk) => client.add(chunk),
                    onError: (_) => client.destroy(),
                    onDone: () => client.destroy(),
                    cancelOnError: true,
                  );
                  return;
                } catch (e) {
                  client.destroy();
                  return;
                }
              }
            }
            client.destroy();
          }
        } else {
          // 已建立隧道后的后续加密数据直接灌入 SSH 管道
          forwardChannel?.sink.add(data);
        }
      });
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