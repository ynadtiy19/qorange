// lib/network/http_proxy_server.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

/// 纯 Dart 实现的高性能 HTTP/HTTPS (CONNECT) 代理服务器（完整数据流修复版）
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
      debugPrint("🔴 [HttpProxyServer] 服务监听异常: $e");
    });

    return port!;
  }

  void _handleClient(Socket client) {
    client.setOption(SocketOption.tcpNoDelay, true);

    bool isConnected = false;
    SSHForwardChannel? forwardChannel;
    final List<int> headerBuffer = [];

    client.listen(
          (data) async {
        if (!isConnected) {
          headerBuffer.addAll(data);
          final headerStr = utf8.decode(headerBuffer, allowMalformed: true);

          if (headerStr.contains('\r\n\r\n') || headerStr.contains('\n\n')) {
            final firstLine = headerStr.split('\n').first.trim();
            final parts = firstLine.split(' ');

            if (parts.length >= 2) {
              final method = parts[0].toUpperCase();
              final target = parts[1];

              String host = '';
              int targetPort = 443;

              if (method == 'CONNECT') {
                // HTTPS 请求: CONNECT i.ytimg.com:443 HTTP/1.1
                final hostParts = target.split(':');
                host = hostParts[0];
                targetPort = hostParts.length > 1 ? (int.tryParse(hostParts[1]) ?? 443) : 443;
              } else {
                // 普通 HTTP 请求
                final uri = Uri.tryParse(target);
                if (uri != null && uri.host.isNotEmpty) {
                  host = uri.host;
                  targetPort = uri.port != 0 ? uri.port : 80;
                }
              }

              if (host.isNotEmpty) {
                try {
                  forwardChannel = await sshClient.forwardLocal(host, targetPort);

                  if (method == 'CONNECT') {
                    client.write("HTTP/1.1 200 Connection Established\r\n\r\n");
                    await client.flush();
                  } else {
                    forwardChannel!.sink.add(Uint8List.fromList(headerBuffer));
                  }

                  isConnected = true;

                  // 🌟 核心修复：使用 client.close() 优雅关闭，确保图片数据包完整送达渲染树
                  forwardChannel!.stream.listen(
                        (Uint8List chunk) {
                      try {
                        client.add(chunk);
                      } catch (_) {}
                    },
                    onError: (_) {
                      client.destroy();
                      forwardChannel?.close();
                    },
                    onDone: () async {
                      try {
                        await client.flush();
                        await client.close(); // 优雅关闭，不丢弃尾部图片包
                      } catch (_) {
                        client.destroy();
                      }
                      forwardChannel?.close();
                    },
                    cancelOnError: true,
                  );
                  return;
                } catch (e) {
                  client.destroy();
                  forwardChannel?.close();
                  return;
                }
              }
            }
            client.destroy();
          }
        } else {
          try {
            forwardChannel?.sink.add(Uint8List.fromList(data));
          } catch (_) {
            client.destroy();
            forwardChannel?.close();
          }
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