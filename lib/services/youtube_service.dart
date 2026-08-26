// lib/services/youtube_service.dart
import '../network/http_client.dart';
import '../views/video_media/models/youtube_model.dart';

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
}