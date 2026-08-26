import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

/// 纯 Dart 实现的极速 HTTP/HTTPS (CONNECT) 代理服务器（硬件级流控与零 GC 优化）
class HttpProxyServer {
  final SSHClient sshClient;
  ServerSocket? _serverSocket;
  int? port;

  HttpProxyServer({required this.sshClient});

  Future<int> start() async {
    _serverSocket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    port = _serverSocket!.port;
    debugPrint("🟢 [HttpProxyServer] 高性能 HTTP 代理已监听: 127.0.0.1:$port");

    _serverSocket!.listen(_handleClient, onError: (e) {
      debugPrint("🔴 [HttpProxyServer] 监听异常: $e");
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

        // 🌟 性能核心 3：纯二进制高效查找 \r\n\r\n (13, 10, 13, 10)，不进行全量 UTF-8 字符解码
        final headerEnd = _findHeaderEnd(headerBuffer);
        if (headerEnd != -1) {
          final headerStr = ascii.decode(headerBuffer.sublist(0, headerEnd));
          final firstLine = headerStr.split('\n').first.trim();
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
              final leftover = headerBuffer.length > headerEnd ? headerBuffer.sublist(headerEnd) : <int>[];

              // 暂停当前流，防止与 TLS 握手并发产生竞争冲突
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
      onError: (_) => client.destroy(),
      onDone: () => client.destroy(),
      cancelOnError: true,
    );
  }

  /// 快速字节匹配 \r\n\r\n 或 \n\n
  int _findHeaderEnd(List<int> bytes) {
    final len = bytes.length;
    for (int i = 0; i < len - 1; i++) {
      if (bytes[i] == 10 && bytes[i + 1] == 10) {
        return i + 2;
      }
      if (i < len - 3 &&
          bytes[i] == 13 &&
          bytes[i + 1] == 10 &&
          bytes[i + 2] == 13 &&
          bytes[i + 3] == 10) {
        return i + 4;
      }
    }
    return -1;
  }

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

      // 重定向双向数据流
      sub.onData((data) {
        try {
          forwardChannel?.sink.add(data);
        } catch (_) {
          client.destroy();
          forwardChannel?.close();
        }
      });

      sub.onDone(() => forwardChannel?.close());
      sub.onError((_) {
        client.destroy();
        forwardChannel?.close();
      });

      sub.resume();

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
  }
}