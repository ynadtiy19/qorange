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
    final path = clientReq.uri.path;

    // 🌟 1. 核心特性：动态生成标准 MPEG-DASH (.mpd) 音画合流清单（解决 1080p/720p 画面+音频同步）
    if (path == '/manifest.mpd') {
      final vUrl = clientReq.uri.queryParameters['v_url'] ?? '';
      final aUrl = clientReq.uri.queryParameters['a_url'] ?? '';
      final vInit = clientReq.uri.queryParameters['v_init'] ?? '0-740';
      final vIndex = clientReq.uri.queryParameters['v_index'] ?? '741-1100';
      final aInit = clientReq.uri.queryParameters['a_init'] ?? '0-600';
      final aIndex = clientReq.uri.queryParameters['a_index'] ?? '601-900';
      final vBitrate = clientReq.uri.queryParameters['v_bitrate'] ?? '2500000';
      final aBitrate = clientReq.uri.queryParameters['a_bitrate'] ?? '130000';
      final vCodec = clientReq.uri.queryParameters['v_codec'] ?? 'avc1.640028';
      final aCodec = clientReq.uri.queryParameters['a_codec'] ?? 'mp4a.40.2';
      final width = clientReq.uri.queryParameters['w'] ?? '1920';
      final height = clientReq.uri.queryParameters['h'] ?? '1080';
      final duration = double.tryParse(clientReq.uri.queryParameters['dur'] ?? '3600') ?? 3600.0;

      if (vUrl.isEmpty) {
        clientReq.response.statusCode = HttpStatus.badRequest;
        await clientReq.response.close();
        return;
      }

      final proxiedVUrl = buildPlayUrl(vUrl);
      final hasAudio = aUrl.isNotEmpty;
      final proxiedAUrl = hasAudio ? buildPlayUrl(aUrl) : '';

      final mpdXml = '''<?xml version="1.0" encoding="UTF-8"?>
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011"
     profiles="urn:mpeg:dash:profile:isoff-on-demand:2011"
     type="static"
     mediaPresentationDuration="PT${duration.toStringAsFixed(3)}S"
     minBufferTime="PT2.0S">
  <Period>
    <AdaptationSet id="0" contentType="video" mimeType="video/mp4" subsegmentAlignment="true">
      <Representation id="video_track" bandwidth="$vBitrate" width="$width" height="$height" codecs="$vCodec">
        <BaseURL>$proxiedVUrl</BaseURL>
        <SegmentBase indexRange="$vIndex">
          <Initialization range="$vInit"/>
        </SegmentBase>
      </Representation>
    </AdaptationSet>
${hasAudio ? '''
    <AdaptationSet id="1" contentType="audio" mimeType="audio/mp4" subsegmentAlignment="true">
      <Representation id="audio_track" bandwidth="$aBitrate" codecs="$aCodec">
        <BaseURL>$proxiedAUrl</BaseURL>
        <SegmentBase indexRange="$aIndex">
          <Initialization range="$aInit"/>
        </SegmentBase>
      </Representation>
    </AdaptationSet>
''' : ''}
  </Period>
</MPD>''';

      final bodyBytes = utf8.encode(mpdXml);
      clientReq.response.statusCode = HttpStatus.ok;
      clientReq.response.headers.set(HttpHeaders.contentTypeHeader, 'application/dash+xml; charset=utf-8');
      clientReq.response.headers.set(HttpHeaders.contentLengthHeader, bodyBytes.length);
      clientReq.response.add(bodyBytes);
      try {
        await clientReq.response.close();
      } catch (_) {}
      debugPrint("🎬 [LocalMediaProxy] 成功动态合成 MPEG-DASH (.mpd) 音画合流清单 (画质: ${height}p)");
      return;
    }

    // 🌟 2. 处理常规视频/音频切片/直播流代理请求
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

      // 透传 Range 请求头（ExoPlayer 原生按需小块拉取的核心）
      final range = clientReq.headers.value(HttpHeaders.rangeHeader);
      if (range != null) {
        upstreamReq.headers.set(HttpHeaders.rangeHeader, range);
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

      // 直播 HLS M3U8 清单递归重写
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
        "📥 [LocalMediaProxy] $mediaTag 中继成功 -> 状态: ${upstreamResp.statusCode} | 长度: ${_formatBytes(length)}",
      );

      // 安全传输，忽略客户端 Range 关闭时的 Connection reset (errno 54 / 32)
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

  /// 🌟 构建本地 MPEG-DASH (.mpd) 音画双轨合流链接
  String buildDashManifestUrl({
    required String videoUrl,
    required String audioUrl,
    required String videoInit,
    required String videoIndex,
    required String audioInit,
    required String audioIndex,
    required String videoBitrate,
    required String audioBitrate,
    required String videoCodec,
    required String audioCodec,
    required String width,
    required String height,
    required double duration,
  }) {
    if (localPort == null) return videoUrl;

    final params = {
      'v_url': videoUrl,
      'a_url': audioUrl,
      'v_init': videoInit,
      'v_index': videoIndex,
      'a_init': audioInit,
      'a_index': audioIndex,
      'v_bitrate': videoBitrate,
      'a_bitrate': audioBitrate,
      'v_codec': videoCodec,
      'a_codec': audioCodec,
      'w': width,
      'h': height,
      'dur': duration.toString(),
    };

    final query = params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
    return 'http://localhost:$localPort/manifest.mpd?$query';
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