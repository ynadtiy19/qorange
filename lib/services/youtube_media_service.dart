// lib/services/youtube_media_service.dart
import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YoutubeMediaService {
  final YoutubeExplode _yt = YoutubeExplode();

  /// 获取 YouTube 视频详情（标题、作者、封面等）
  Future<Video?> fetchVideoDetails(String videoUrlOrId) async {
    try {
      final video = await _yt.videos.get(videoUrlOrId);
      return video;
    } catch (e) {
      debugPrint("❌ [YouTube] 解析视频详情失败: $e");
      return null;
    }
  }

  /// 获取适合音频播放的最高音质音频流地址
  Future<String?> fetchAudioStreamUrl(String videoUrlOrId) async {
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoUrlOrId);
      // 提取最高码率纯音频轨道
      final audioStream = manifest.audioOnly.withHighestBitrate();
      return audioStream.url.toString();
    } catch (e) {
      debugPrint("❌ [YouTube] 获取音频流直链失败: $e");
      return null;
    }
  }

  void dispose() {
    _yt.close();
  }
}