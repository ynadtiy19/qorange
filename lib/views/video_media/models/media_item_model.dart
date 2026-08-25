// lib/views/video_media/models/media_item_model.dart
import 'package:get/get.dart';

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

  factory MediaItemModel.fromYoutubeVideo(dynamic video) {
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