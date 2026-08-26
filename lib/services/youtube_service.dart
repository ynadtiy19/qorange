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
  });

  factory VideoStreamQualityModel.fromJson(Map<String, dynamic> json) {
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
    );
  }
}

class VideoDetailStreamResult {
  final String videoId;
  final String title;
  final String author;
  final String duration;
  final String thumbnail;
  final String rawVideoUrl;
  final String rawAudioUrl;
  final List<VideoStreamQualityModel> formatStreams;

  VideoDetailStreamResult({
    required this.videoId,
    required this.title,
    required this.author,
    required this.duration,
    required this.thumbnail,
    required this.rawVideoUrl,
    required this.rawAudioUrl,
    required this.formatStreams,
  });

  factory VideoDetailStreamResult.fromJson(Map<String, dynamic> json) {
    final rawStreams = json['format_streams'] as List? ?? [];
    final streams = rawStreams
        .map((s) => VideoStreamQualityModel.fromJson(s as Map<String, dynamic>))
        .toList();

    return VideoDetailStreamResult(
      videoId: json['video_id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      author: json['author']?.toString() ?? '',
      duration: json['duration']?.toString() ?? '',
      thumbnail: json['thumbnail']?.toString() ?? '',
      rawVideoUrl: json['raw_video_url']?.toString() ?? '',
      rawAudioUrl: json['raw_audio_url']?.toString() ?? '',
      formatStreams: streams,
    );
  }
}

class YouTubeService {
  static final YouTubeService _instance = YouTubeService._internal();
  factory YouTubeService() => _instance;
  YouTubeService._internal();

  /// 1. 列表搜索：请求 Zeabur 后端
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

  /// 2. 详情提取：直接请求 Dart Frog 的 /api-youtube/[id] 路由获取各画质直链
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