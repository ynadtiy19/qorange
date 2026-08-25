// lib/network/http_proxy_server.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

/// 纯 Dart 实现的标准 HTTP/HTTPS (CONNECT) 代理服务器（单流无冲突版）
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

  void _handleClient(Socket client) {
    bool isConnected = false;
    SSHForwardChannel? forwardChannel;
    final List<int> headerBuffer = [];

    // 🌟 核心修复：全局仅订阅 client 一次，杜绝 Stream has already been listened to
    client.listen(
          (data) async {
        if (!isConnected) {
          headerBuffer.addAll(data);
          final headerStr = utf8.decode(headerBuffer, allowMalformed: true);

          // 寻找 HTTP 头部结束符
          if (headerStr.contains('\r\n\r\n') || headerStr.contains('\n\n')) {
            final firstLine = headerStr.split('\n').first.trim();
            final parts = firstLine.split(' ');

            if (parts.length >= 2) {
              final method = parts[0].toUpperCase();
              final target = parts[1];

              String host = '';
              int targetPort = 443;

              if (method == 'CONNECT') {
                // HTTPS 请求: CONNECT www.youtube.com:443 HTTP/1.1
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

              if (host.isNotEmpty) {
                try {
                  // 🌟 通过 SSH 动态转发连接目标主机
                  forwardChannel = await sshClient.forwardLocal(host, targetPort);

                  if (method == 'CONNECT') {
                    // 回复客户端 HTTPS 隧道就绪
                    client.write("HTTP/1.1 200 Connection Established\r\n\r\n");
                    await client.flush();
                  } else {
                    forwardChannel!.sink.add(headerBuffer);
                  }

                  isConnected = true;

                  // 远端数据向本地回传
                  forwardChannel!.stream.listen(
                        (chunk) => client.add(chunk),
                    onError: (_) => client.destroy(),
                    onDone: () => client.destroy(),
                    cancelOnError: true,
                  );
                  return;
                } catch (e) {
                  debugPrint("🔴 [HttpProxyServer] 转发通道建立失败 ($host:$targetPort): $e");
                  client.destroy();
                  return;
                }
              }
            }
            client.destroy();
          }
        } else {
          // 隧道已建立：后续数据帧（TLS ClientHello / 数据流）直通 SSH 管道
          forwardChannel?.sink.add(data);
        }
      },
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
  }

  Future<void> stop() async {
    await _serverSocket?.close();
    _serverSocket = null;
    port = null;
    debugPrint("🔌 [HttpProxyServer] 本地代理已安全关闭");
  }
}