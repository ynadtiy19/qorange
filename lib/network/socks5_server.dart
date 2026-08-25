// lib/network/socks5_server.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

/// 纯 Dart 实现的轻量级 SOCKS5 代理服务器
class Socks5Server {
  final SSHClient sshClient;
  ServerSocket? _serverSocket;
  int? port;

  Socks5Server({required this.sshClient});

  /// 启动监听本地回环地址的一个空闲端口
  Future<int> start() async {
    _serverSocket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    port = _serverSocket!.port;
    debugPrint("🟢 [Socks5Server] 本地 SOCKS5 服务已启动，监听端口: 127.0.0.1:$port");

    _serverSocket!.listen(_handleClientConnection, onError: (e) {
      debugPrint("🔴 [Socks5Server] 服务监听异常: $e");
    });

    return port!;
  }

  /// 处理客户端 SOCKS5 握手协议
  void _handleClientConnection(Socket client) async {
    try {
      final stream = client.asBroadcastStream();
      final iterator = StreamIterator(stream);

      // 1. 读取版本协商问候包 [VER, NMETHODS, METHODS...]
      if (!await iterator.moveNext()) return;
      Uint8List greeting = iterator.current;
      if (greeting.isEmpty || greeting[0] != 0x05) {
        client.destroy();
        return;
      }

      // 回复握手确认：选择无密码认证 [0x05, 0x00]
      client.add([0x05, 0x00]);
      await client.flush();

      // 2. 读取连接请求包 [VER, CMD, RSV, ATYP, DST.ADDR, DST.PORT]
      if (!await iterator.moveNext()) return;
      Uint8List request = iterator.current;
      if (request.length < 7 || request[0] != 0x05 || request[1] != 0x01) {
        // 只支持 CONNECT 命令 (CMD = 0x01)
        client.destroy();
        return;
      }

      int atyp = request[3];
      String targetHost = '';
      int targetPort = 0;
      int portStartIndex = 0;

      if (atyp == 0x01) {
        // IPv4 (4字节)
        targetHost = request.sublist(4, 8).join('.');
        portStartIndex = 8;
      } else if (atyp == 0x03) {
        // 域名 (1字节长度 + ASCII 字符串)
        int domainLength = request[4];
        targetHost = String.fromCharCodes(request.sublist(5, 5 + domainLength));
        portStartIndex = 5 + domainLength;
      } else if (atyp == 0x04) {
        // IPv6 (16字节)
        targetHost = request.sublist(4, 20).map((e) => e.toRadixString(16).padLeft(2, '0')).join(':');
        portStartIndex = 20;
      } else {
        client.destroy();
        return;
      }

      // 解析目标端口 (2字节大端序)
      final byteData = ByteData.sublistView(request, portStartIndex, portStartIndex + 2);
      targetPort = byteData.getUint16(0, Endian.big);

      // 3. 通过 SSH 协议向远端 Zeabur 发起动态转发通道 (direct-tcpip)
      final SSHForwardChannel forwardChannel = await sshClient.forwardLocal(targetHost, targetPort);

      // 回复客户端连接成功 [0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]
      client.add([0x05, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);
      await client.flush();

      // 4. 双向管道数据直通对接 (全双工流)
      client.listen(
            (data) => forwardChannel.sink.add(data),
        onDone: () => forwardChannel.sink.close(),
        onError: (_) => forwardChannel.sink.close(),
        cancelOnError: true,
      );

      forwardChannel.stream.listen(
            (data) => client.add(data),
        onDone: () => client.destroy(),
        onError: (_) => client.destroy(),
        cancelOnError: true,
      );
    } catch (e) {
      client.destroy();
    }
  }

  /// 停止服务
  Future<void> stop() async {
    await _serverSocket?.close();
    _serverSocket = null;
    port = null;
    debugPrint("🔌 [Socks5Server] 本地 SOCKS5 服务已关闭");
  }
}