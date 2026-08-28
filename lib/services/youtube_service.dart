// lib/services/youtube_service.dart
import '../network/http_client.dart';
import '../views/video_media/models/youtube_model.dart';

class VideoStreamQualityModel {
  final String itag;
  final String quality;
  final String qualityLabel;
  final String resolution;
  final String container;
  final String encoding;
  final int fps;
  final String size;
  final String bitrate;
  final String url;
  final String clen;
  final String init;
  final String index;
  final String width;
  final String height;
  final bool isAdaptive;

  VideoStreamQualityModel({
    required this.itag,
    required this.quality,
    required this.qualityLabel,
    required this.resolution,
    required this.container,
    required this.encoding,
    required this.fps,
    required this.size,
    required this.bitrate,
    required this.url,
    this.clen = '',
    this.init = '0-740',
    this.index = '741-1100',
    this.width = '1280',
    this.height = '720',
    this.isAdaptive = false,
  });

  factory VideoStreamQualityModel.fromJson(Map<String, dynamic> json, {bool isAdaptive = false}) {
    return VideoStreamQualityModel(
      itag: json['itag']?.toString() ?? '',
      quality: json['quality']?.toString() ?? '',
      qualityLabel: json['quality_label']?.toString() ?? json['qualityLabel']?.toString() ?? '360p',
      resolution: json['resolution']?.toString() ?? '',
      container: json['container']?.toString() ?? 'mp4',
      encoding: json['encoding']?.toString() ?? 'h264',
      fps: (json['fps'] as num?)?.toInt() ?? 30,
      size: json['size']?.toString() ?? '',
      bitrate: json['bitrate']?.toString() ?? '2500000',
      url: json['url']?.toString() ?? '',
      clen: json['clen']?.toString() ?? '',
      init: json['init']?.toString() ?? '0-740',
      index: json['index']?.toString() ?? '741-1100',
      width: json['width']?.toString() ?? '1280',
      height: json['height']?.toString() ?? '720',
      isAdaptive: isAdaptive,
    );
  }
}

class AudioStreamQualityModel {
  final String itag;
  final String container;
  final String encoding;
  final String bitrate;
  final String init;
  final String index;
  final String url;

  AudioStreamQualityModel({
    required this.itag,
    required this.container,
    required this.encoding,
    required this.bitrate,
    required this.init,
    required this.index,
    required this.url,
  });

  factory AudioStreamQualityModel.fromJson(Map<String, dynamic> json) {
    return AudioStreamQualityModel(
      itag: json['itag']?.toString() ?? '',
      container: json['container']?.toString() ?? 'm4a',
      encoding: json['encoding']?.toString() ?? 'aac',
      bitrate: json['bitrate']?.toString() ?? '130000',
      init: json['init']?.toString() ?? '0-600',
      index: json['index']?.toString() ?? '601-900',
      url: json['url']?.toString() ?? '',
    );
  }
}

class VideoCaptionModel {
  final String label;
  final String languageCode;
  final String url;

  VideoCaptionModel({
    required this.label,
    required this.languageCode,
    required this.url,
  });

  factory VideoCaptionModel.fromJson(Map<String, dynamic> json) {
    return VideoCaptionModel(
      label: json['label']?.toString() ?? '',
      languageCode: json['language_code']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
    );
  }
}

class VideoDetailStreamResult {
  final String videoId;
  final String title;
  final String description;
  final String author;
  final String authorId;
  final bool authorVerified;
  final String authorAvatar;
  final String subCountText;
  final String duration;
  final int lengthSeconds;
  final bool isLive;
  final String viewCount;
  final String likeCount;
  final String publishedText;
  final String thumbnail;
  final String hlsUrl;
  final String rawVideoUrl;
  final String rawAudioUrl;
  final AudioStreamQualityModel? primaryAudioTrack;
  final List<VideoStreamQualityModel> formatStreams;
  final List<VideoStreamQualityModel> adaptiveVideoStreams;
  final List<VideoCaptionModel> captions;
  final List<YouTubeVideoModel> recommendedVideos;

  VideoDetailStreamResult({
    required this.videoId,
    required this.title,
    required this.description,
    required this.author,
    required this.authorId,
    required this.authorVerified,
    required this.authorAvatar,
    required this.subCountText,
    required this.duration,
    required this.lengthSeconds,
    required this.isLive,
    required this.viewCount,
    required this.likeCount,
    required this.publishedText,
    required this.thumbnail,
    required this.hlsUrl,
    required this.rawVideoUrl,
    required this.rawAudioUrl,
    required this.primaryAudioTrack,
    required this.formatStreams,
    required this.adaptiveVideoStreams,
    required this.captions,
    required this.recommendedVideos,
  });

  factory VideoDetailStreamResult.fromJson(Map<String, dynamic> json) {
    final rawFormat = json['format_streams'] as List? ?? [];
    final formats = rawFormat
        .map((s) => VideoStreamQualityModel.fromJson(s as Map<String, dynamic>, isAdaptive: false))
        .toList();

    final rawAdaptive = json['adaptive_video_streams'] as List? ?? [];
    final adaptives = rawAdaptive
        .map((s) => VideoStreamQualityModel.fromJson(s as Map<String, dynamic>, isAdaptive: true))
        .toList();

    final rawCaps = json['captions'] as List? ?? [];
    final caps = rawCaps
        .map((c) => VideoCaptionModel.fromJson(c as Map<String, dynamic>))
        .toList();

    final rawRecs = json['recommended_videos'] as List? ?? [];
    final recs = rawRecs
        .map((r) => YouTubeVideoModel.fromJson(r as Map<String, dynamic>))
        .toList();

    AudioStreamQualityModel? primaryAudio;
    if (json['primary_audio_track'] != null && json['primary_audio_track'] is Map) {
      primaryAudio = AudioStreamQualityModel.fromJson(json['primary_audio_track'] as Map<String, dynamic>);
    }

    return VideoDetailStreamResult(
      videoId: json['video_id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      author: json['author']?.toString() ?? '',
      authorId: json['author_id']?.toString() ?? '',
      authorVerified: json['author_verified'] == true,
      authorAvatar: json['author_avatar']?.toString() ?? '',
      subCountText: json['sub_count_text']?.toString() ?? '',
      duration: json['duration']?.toString() ?? '',
      lengthSeconds: (json['length_seconds'] as num?)?.toInt() ?? 0,
      isLive: json['is_live'] == true,
      viewCount: json['view_count']?.toString() ?? '',
      likeCount: json['like_count']?.toString() ?? '',
      publishedText: json['published_text']?.toString() ?? '',
      thumbnail: json['thumbnail']?.toString() ?? '',
      hlsUrl: json['hls_url']?.toString() ?? '',
      rawVideoUrl: json['raw_video_url']?.toString() ?? '',
      rawAudioUrl: json['raw_audio_url']?.toString() ?? '',
      primaryAudioTrack: primaryAudio,
      formatStreams: formats,
      adaptiveVideoStreams: adaptives,
      captions: caps,
      recommendedVideos: recs,
    );
  }
}

class YouTubeService {
  static final YouTubeService _instance = YouTubeService._internal();
  factory YouTubeService() => _instance;
  YouTubeService._internal();

  /// 🌟 1. 搜索接口：支持分页（page）与条数限制（limit）
  Future<List<YouTubeVideoModel>> searchVideos(String query, {int page = 1, int limit = 20}) async {
    final res = await HttpClient.instance.get<dynamic>(
      '/api-youtube/search',
      queryParameters: {
        'q': query,
        'page': page,
        'limit': limit,
      },
    );

    if (res.respCode == 0 && res.datas != null) {
      if (res.datas is List) {
        final list = res.datas as List;
        return list
            .map((item) => YouTubeVideoModel.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    }
    return [];
  }

  /// 🌟 2. 热门发现接口：获取实时全球 Trending 推荐流
  Future<List<YouTubeVideoModel>> fetchTrendingVideos({String type = 'default'}) async {
    final res = await HttpClient.instance.get<dynamic>(
      '/api-youtube/trending',
      queryParameters: {
        'type': type,
      },
    );

    if (res.respCode == 0 && res.datas != null) {
      if (res.datas is List) {
        final list = res.datas as List;
        return list
            .map((item) => YouTubeVideoModel.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    }
    return [];
  }

  /// 🌟 3. 详情提取接口
  Future<VideoDetailStreamResult?> fetchVideoDetail(String videoId) async {
    final res = await HttpClient.instance.get<dynamic>(
      '/api-youtube/$videoId',
      queryParameters: {
        'mode': 'all',
      },
    );

    if (res.respCode == 0 && res.datas != null && res.datas is Map<String, dynamic>) {
      return VideoDetailStreamResult.fromJson(res.datas as Map<String, dynamic>);
    }
    return null;
  }
}