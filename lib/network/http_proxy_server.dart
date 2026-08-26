import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

/// 纯 Dart 实现的高性能 HTTP/HTTPS (CONNECT) 代理服务器（流控暂停防死锁修复版）
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

    final List<int> headerBuffer = [];
    StreamSubscription<Uint8List>? sub;

    sub = client.listen(
          (data) {
        headerBuffer.addAll(data);
        final headerStr = utf8.decode(headerBuffer, allowMalformed: true);

        int headerEnd = headerStr.indexOf('\r\n\r\n');
        int delimiterLen = 4;
        if (headerEnd == -1) {
          headerEnd = headerStr.indexOf('\n\n');
          delimiterLen = 2;
        }

        // 🌟 1. 成功匹配到完整的 HTTP 请求头
        if (headerEnd != -1) {
          final firstLine = headerStr.substring(0, headerEnd).split('\n').first.trim();
          final parts = firstLine.split(' ');

          if (parts.length >= 2) {
            final method = parts[0].toUpperCase();
            final target = parts[1];

            String host = '';
            int targetPort = 443;

            if (method == 'CONNECT') {
              final hostParts = target.split(':');
              host = hostParts[0];
              targetPort = hostParts.length > 1 ? (int.tryParse(hostParts[1]) ?? 443) : 443;
            } else {
              final uri = Uri.tryParse(target);
              if (uri != null && uri.host.isNotEmpty) {
                host = uri.host;
                targetPort = uri.port != 0 ? uri.port : 80;
              }
            }

            if (host.isNotEmpty) {
              final rawHeaderLen = utf8.encode(headerStr.substring(0, headerEnd + delimiterLen)).length;
              List<int> leftover = [];
              if (headerBuffer.length > rawHeaderLen) {
                leftover = headerBuffer.sublist(rawHeaderLen);
              }

              // 🌟 2. 极其关键：在建立 SSH 远端连接期间暂停客户端流监听，防止 TLS 数据包并发混乱
              sub?.pause();

              _establishTunnelAndBridge(
                client: client,
                sub: sub!,
                method: method,
                host: host,
                targetPort: targetPort,
                headerBuffer: headerBuffer,
                leftover: leftover,
              );
              return;
            }
          }
          client.destroy();
        }
      },
      onError: (_) {
        client.destroy();
      },
      onDone: () {
        client.destroy();
      },
      cancelOnError: true,
    );
  }

  /// 建立 SSH 通道并桥接双向数据流
  Future<void> _establishTunnelAndBridge({
    required Socket client,
    required StreamSubscription<Uint8List> sub,
    required String method,
    required String host,
    required int targetPort,
    required List<int> headerBuffer,
    required List<int> leftover,
  }) async {
    SSHForwardChannel? forwardChannel;
    try {
      forwardChannel = await sshClient.forwardLocal(host, targetPort);

      if (method == 'CONNECT') {
        client.write("HTTP/1.1 200 Connection Established\r\n\r\n");
        await client.flush();

        if (leftover.isNotEmpty) {
          forwardChannel.sink.add(Uint8List.fromList(leftover));
        }
      } else {
        forwardChannel.sink.add(Uint8List.fromList(headerBuffer));
      }

      // 🌟 3. 握手建立成功后，重定向数据流并恢复客户端流
      sub.onData((data) {
        try {
          forwardChannel?.sink.add(data);
        } catch (_) {
          client.destroy();
          forwardChannel?.close();
        }
      });

      sub.onDone(() {
        forwardChannel?.close();
      });

      sub.onError((_) {
        client.destroy();
        forwardChannel?.close();
      });

      // 恢复接收客户端后续数据
      sub.resume();

      // 🌟 4. 将远端 SSH 数据管道式回推给客户端
      forwardChannel.stream.listen(
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
            await client.close();
          } catch (_) {
            client.destroy();
          }
          forwardChannel?.close();
        },
        cancelOnError: true,
      );
    } catch (e) {
      client.destroy();
      forwardChannel?.close();
    }
  }

  Future<void> stop() async {
    await _serverSocket?.close();
    _serverSocket = null;
    port = null;
    debugPrint("🔌 [HttpProxyServer] 本地代理已安全关闭");
  }
}