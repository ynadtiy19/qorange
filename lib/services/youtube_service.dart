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
  final bool isHls;

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
    this.isHls = false,
  });

  factory VideoStreamQualityModel.fromJson(Map<String, dynamic> json, {bool isHls = false}) {
    return VideoStreamQualityModel(
      itag: json['itag']?.toString() ?? '',
      quality: json['quality']?.toString() ?? '',
      qualityLabel: json['quality_label']?.toString() ?? json['qualityLabel']?.toString() ?? '360p',
      resolution: json['resolution']?.toString() ?? '',
      container: json['container']?.toString() ?? 'mp4',
      encoding: json['encoding']?.toString() ?? 'h264',
      fps: (json['fps'] as num?)?.toInt() ?? 30,
      size: json['size']?.toString() ?? '',
      bitrate: json['bitrate']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      isHls: isHls,
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
    required this.formatStreams,
    required this.adaptiveVideoStreams,
    required this.captions,
    required this.recommendedVideos,
  });

  factory VideoDetailStreamResult.fromJson(Map<String, dynamic> json) {
    final rawFormat = json['format_streams'] as List? ?? [];
    final formats = rawFormat
        .map((s) => VideoStreamQualityModel.fromJson(s as Map<String, dynamic>, isHls: false))
        .toList();

    final rawAdaptive = json['adaptive_video_streams'] as List? ?? [];
    final adaptives = rawAdaptive
        .map((s) => VideoStreamQualityModel.fromJson(s as Map<String, dynamic>, isHls: false))
        .toList();

    final rawCaps = json['captions'] as List? ?? [];
    final caps = rawCaps
        .map((c) => VideoCaptionModel.fromJson(c as Map<String, dynamic>))
        .toList();

    final rawRecs = json['recommended_videos'] as List? ?? [];
    final recs = rawRecs
        .map((r) => YouTubeVideoModel.fromJson(r as Map<String, dynamic>))
        .toList();

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

  Future<List<YouTubeVideoModel>> searchVideos(String query, {int limit = 15}) async {
    final res = await HttpClient.instance.get<dynamic>(
      '/api-youtube/search',
      queryParameters: {
        'q': query,
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