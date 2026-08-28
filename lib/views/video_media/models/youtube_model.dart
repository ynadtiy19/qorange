// lib/models/youtube_model.dart

class YouTubeVideoModel {
  final String videoId;
  final String title;
  final String author;
  final String authorId;
  final bool authorVerified;
  final String authorAvatar;
  final String duration;
  final int lengthSeconds;
  final bool isLive;
  final String views;
  final String thumbnail;
  final String publishedText;
  final String description;
  final String? videoStreamUrl;
  final String? audioStreamUrl;
  final String? source;

  YouTubeVideoModel({
    required this.videoId,
    required this.title,
    required this.author,
    this.authorId = '',
    this.authorVerified = false,
    this.authorAvatar = '',
    required this.duration,
    this.lengthSeconds = 0,
    this.isLive = false,
    required this.views,
    required this.thumbnail,
    this.publishedText = '',
    this.description = '',
    this.videoStreamUrl,
    this.audioStreamUrl,
    this.source,
  });

  factory YouTubeVideoModel.fromJson(Map<String, dynamic> json) {
    final vId = json['video_id']?.toString() ?? json['videoId']?.toString() ?? '';
    final lengthSec = (json['length_seconds'] as num?)?.toInt() ?? 0;
    final live = json['is_live'] == true || (json['duration']?.toString().toUpperCase() == 'LIVE');

    return YouTubeVideoModel(
      videoId: vId,
      title: json['title']?.toString() ?? '',
      author: (json['author'] ?? json['channel'])?.toString() ?? 'YouTube Creator',
      authorId: json['author_id']?.toString() ?? json['authorId']?.toString() ?? '',
      authorVerified: json['author_verified'] == true || json['authorVerified'] == true,
      authorAvatar: json['author_avatar']?.toString() ?? json['authorAvatar']?.toString() ?? '',
      duration: live ? 'LIVE' : (json['duration']?.toString() ?? '00:00'),
      lengthSeconds: lengthSec,
      isLive: live,
      views: json['views']?.toString() ?? json['view_count']?.toString() ?? '0 views',
      thumbnail: json['thumbnail']?.toString() ?? (vId.isNotEmpty ? 'https://i.ytimg.com/vi/$vId/hqdefault.jpg' : ''),
      publishedText: json['published_text']?.toString() ?? json['publishedText']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      videoStreamUrl: (json['stream_url'] ?? json['video_stream_url'])?.toString(),
      audioStreamUrl: json['audio_stream_url']?.toString(),
      source: json['source']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'video_id': videoId,
    'title': title,
    'author': author,
    'author_id': authorId,
    'author_verified': authorVerified,
    'author_avatar': authorAvatar,
    'duration': duration,
    'length_seconds': lengthSeconds,
    'is_live': isLive,
    'views': views,
    'thumbnail': thumbnail,
    'published_text': publishedText,
    'description': description,
    'stream_url': videoStreamUrl,
    'audio_stream_url': audioStreamUrl,
    'source': source,
  };
}