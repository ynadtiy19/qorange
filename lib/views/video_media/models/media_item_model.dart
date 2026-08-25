// lib/views/video_media/models/media_item_model.dart
import 'package:get/get.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class MediaItemModel {
  final String id;
  final String title;
  final String author;
  final String? authorAvatar;
  final String duration;
  final String thumbnailUrl;
  final int viewsCount;
  final String uploadDate;
  final String description;

  // 响应式下载与本地存储状态
  final RxBool isDownloaded = false.obs;
  final RxBool isDownloading = false.obs;
  final RxDouble downloadProgress = 0.0.obs;
  final RxString localFilePath = ''.obs;

  MediaItemModel({
    required this.id,
    required this.title,
    required this.author,
    this.authorAvatar,
    required this.duration,
    required this.thumbnailUrl,
    required this.viewsCount,
    required this.uploadDate,
    required this.description,
    String? localPath,
  }) {
    if (localPath != null && localPath.isNotEmpty) {
      localFilePath.value = localPath;
      isDownloaded.value = true;
    }
  }

  /// 🌟 完美适配 SearchVideo 实体（修复 views 属性报错）
  factory MediaItemModel.fromSearchVideo(SearchVideo video) {
    // 安全提取高清封面
    final String thumb = video.thumbnails.isNotEmpty
        ? video.thumbnails.last.url.toString()
        : 'https://img.youtube.com/vi/${video.id.value}/hqdefault.jpg';

    return MediaItemModel(
      id: video.id.value,
      title: video.title,
      author: video.author,
      duration: video.duration?.toString() ?? '03:45',
      thumbnailUrl: thumb,
      viewsCount: 0, // 🌟 修复：SearchVideo 实体无 views 属性，默认设为 0
      uploadDate: video.uploadDate ?? '热门推荐',
      description: video.description,
    );
  }

  /// 兼容旧版 Video 实体
  factory MediaItemModel.fromYoutubeVideo(Video video) {
    final dur = video.duration;
    final minutes = dur != null ? (dur.inMinutes).toString().padLeft(2, '0') : '00';
    final seconds = dur != null ? (dur.inSeconds % 60).toString().padLeft(2, '0') : '00';

    return MediaItemModel(
      id: video.id.value,
      title: video.title,
      author: video.author,
      duration: '$minutes:$seconds',
      thumbnailUrl: video.thumbnails.highResUrl,
      viewsCount: video.engagement.viewCount ?? 0,
      uploadDate: video.uploadDate != null
          ? "${video.uploadDate!.year}-${video.uploadDate!.month.toString().padLeft(2, '0')}-${video.uploadDate!.day.toString().padLeft(2, '0')}"
          : "近期发布",
      description: video.description,
    );
  }
}