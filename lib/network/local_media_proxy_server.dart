// lib/network/local_media_proxy_server.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class LocalMediaProxyServer {
  static final LocalMediaProxyServer instance = LocalMediaProxyServer._();
  LocalMediaProxyServer._();

  HttpServer? _server;
  int? localPort;
  HttpClient? _sharedClient;

  // 🌟 单次向上游拉取的最大分块限制为 2.5 MB（实现按需流式拉取，细水长流）
  static const int kMaxChunkSliceBytes = 2621440; // 2.5 MB

  HttpClient get _client {
    _sharedClient ??= HttpClient()
      ..badCertificateCallback = ((cert, host, port) => true)
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 60)
      ..maxConnectionsPerHost = 50
      ..autoUncompress = true;
    return _sharedClient!;
  }

  Future<int> start() async {
    if (_server != null) return localPort!;

    _sharedClient?.close(force: true);
    _sharedClient = null;

    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    localPort = _server!.port;
    debugPrint("🚀 [LocalMediaProxy] 本地流中继就绪: http://localhost:$localPort");

    _server!.listen(_handleRequest);
    return localPort!;
  }

  void _handleRequest(HttpRequest clientReq) async {
    final targetUrl = clientReq.uri.queryParameters['url'];
    if (targetUrl == null || targetUrl.isEmpty) {
      clientReq.response.statusCode = HttpStatus.badRequest;
      try {
        await clientReq.response.close();
      } catch (_) {}
      return;
    }

    try {
      final targetUri = Uri.parse(targetUrl);
      final upstreamReq = await _client.getUrl(targetUri);

      final clientRange = clientReq.headers.value(HttpHeaders.rangeHeader);
      final isVideoOrAudio = targetUrl.contains('videoplayback') ||
          targetUrl.contains('.mp4') ||
          targetUrl.contains('.webm') ||
          targetUrl.contains('.m4a');

      // 🌟 1. 核心机制：对音视频大文件启用 2.5MB 分块截断保护（细水长流）
      if (isVideoOrAudio && clientRange != null && clientRange.startsWith('bytes=')) {
        final rangeSpec = clientRange.replaceAll('bytes=', '').trim();
        final parts = rangeSpec.split('-');
        final startByte = int.tryParse(parts[0]) ?? 0;
        int? endByte = parts.length > 1 && parts[1].isNotEmpty ? int.tryParse(parts[1]) : null;

        // 如果客户端未指定结束字节（如 bytes=0-）或请求范围超过 2.5MB，强行截断为 2.5MB 小块
        if (endByte == null || (endByte - startByte) > kMaxChunkSliceBytes) {
          endByte = startByte + kMaxChunkSliceBytes - 1;
        }

        upstreamReq.headers.set(HttpHeaders.rangeHeader, 'bytes=$startByte-$endByte');
      } else if (clientRange != null) {
        upstreamReq.headers.set(HttpHeaders.rangeHeader, clientRange);
      }

      upstreamReq.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      );
      upstreamReq.headers.set(HttpHeaders.acceptHeader, '*/*');

      final upstreamResp = await upstreamReq.close();
      final contentType = upstreamResp.headers.contentType?.toString().toLowerCase() ?? '';
      final isM3u8 = targetUrl.contains('.m3u8') || contentType.contains('mpegurl');

      final mediaTag = _detectMediaType(targetUrl, contentType);

      // 🌟 2. 处理直播 HLS 清单递归重写
      if (isM3u8 && upstreamResp.statusCode == 200) {
        final m3u8RawContent = await upstreamResp.transform(utf8.decoder).join();
        final lines = m3u8RawContent.split('\n');
        final rewrittenLines = <String>[];
        int segmentCount = 0;

        final baseUrl = '${targetUri.scheme}://${targetUri.authority}';

        for (var line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty || trimmed.startsWith('#')) {
            rewrittenLines.add(line);
          } else {
            segmentCount++;
            String fullSegmentUrl = trimmed;
            if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
              if (trimmed.startsWith('/')) {
                fullSegmentUrl = '$baseUrl$trimmed';
              } else {
                final parentSegments = targetUri.pathSegments.take(targetUri.pathSegments.length - 1);
                final parentPath = parentSegments.isNotEmpty ? '/${parentSegments.join('/')}' : '';
                fullSegmentUrl = '$baseUrl$parentPath/$trimmed';
              }
            }
            rewrittenLines.add(buildPlayUrl(fullSegmentUrl));
          }
        }

        final rewrittenBody = utf8.encode(rewrittenLines.join('\n'));
        clientReq.response.statusCode = HttpStatus.ok;
        clientReq.response.headers.set(HttpHeaders.contentTypeHeader, 'application/vnd.apple.mpegurl; charset=utf-8');
        clientReq.response.headers.set(HttpHeaders.contentLengthHeader, rewrittenBody.length);

        debugPrint(
          "📥 [LocalMediaProxy] $mediaTag 中继成功 -> 状态: 200 | 切片数: $segmentCount 条 | 大小: ${_formatBytes(rewrittenBody.length)}",
        );

        clientReq.response.add(rewrittenBody);
        try {
          await clientReq.response.close();
        } catch (_) {}
        return;
      }

      // 🌟 3. 普通流直通推流
      clientReq.response.statusCode = upstreamResp.statusCode;

      upstreamResp.headers.forEach((name, values) {
        final lower = name.toLowerCase();
        if (lower != 'transfer-encoding' && lower != 'connection' && lower != 'keep-alive') {
          for (var v in values) {
            clientReq.response.headers.add(name, v);
          }
        }
      });

      if (upstreamResp.statusCode == 206) {
        clientReq.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      }

      final length = upstreamResp.contentLength;
      debugPrint(
        "📥 [LocalMediaProxy] $mediaTag 按需拉取 -> 状态: ${upstreamResp.statusCode} | 块大小: ${_formatBytes(length)} | 源站: ${targetUri.host}",
      );

      // 安全传输，自动捕获播放器由于跳帧/暂停导致的断流
      await clientReq.response.addStream(upstreamResp).catchError((_) {});
      try {
        await clientReq.response.close();
      } catch (_) {}
    } catch (_) {
      try {
        clientReq.response.statusCode = HttpStatus.badGateway;
        await clientReq.response.close();
      } catch (_) {}
    }
  }

  String buildPlayUrl(String remoteUrl) {
    if (localPort == null || remoteUrl.isEmpty) return remoteUrl;
    return 'http://localhost:$localPort/stream?url=${Uri.encodeComponent(remoteUrl)}';
  }

  String _detectMediaType(String url, String contentType) {
    final lowerUrl = url.toLowerCase();
    final lowerType = contentType.toLowerCase();

    if (lowerUrl.contains('.m3u8') || lowerType.contains('mpegurl')) {
      return '🔴 [HLS/直播清单]';
    }
    if (lowerUrl.contains('source=yt_live_broadcast') || lowerUrl.contains('.ts')) {
      return '⚡ [直播分片切片]';
    }
    if (lowerType.startsWith('image/') ||
        lowerUrl.contains('.jpg') ||
        lowerUrl.contains('.png') ||
        lowerUrl.contains('.webp') ||
        lowerUrl.contains('.jpeg')) {
      return '🖼️ [图片封面/头像]';
    }
    if (lowerType.startsWith('video/') || lowerUrl.contains('.mp4') || lowerUrl.contains('.webm')) {
      return '🎬 [视频流媒体]';
    }
    if (lowerType.startsWith('audio/') || lowerUrl.contains('.m4a') || lowerUrl.contains('.opus')) {
      return '🎵 [音频流媒体]';
    }
    return '📦 [通用数据流]';
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return 'Chunked分块流';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  Future<void> stop() async {
    _sharedClient?.close(force: true);
    _sharedClient = null;
    await _server?.close(force: true);
    _server = null;
    localPort = null;
    debugPrint("🔌 [LocalMediaProxy] 本地中继服务已释放");
  }
}