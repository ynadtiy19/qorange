// lib/models/youtube_model.dart

class YouTubeVideoModel {
  final String videoId;
  final String title;
  final String author;
  final String duration;
  final String views;
  final String thumbnail;
  final String? videoStreamUrl;
  final String? audioStreamUrl;
  final String? source;

  YouTubeVideoModel({
    required this.videoId,
    required this.title,
    required this.author,
    required this.duration,
    required this.views,
    required this.thumbnail,
    this.videoStreamUrl,
    this.audioStreamUrl,
    this.source,
  });

  factory YouTubeVideoModel.fromJson(Map<String, dynamic> json) {
    return YouTubeVideoModel(
      videoId: json['video_id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      author: (json['author'] ?? json['channel'])?.toString() ?? 'YouTube Creator',
      duration: json['duration']?.toString() ?? '00:00',
      views: json['views']?.toString() ?? '',
      thumbnail: json['thumbnail']?.toString() ?? '',
      videoStreamUrl: (json['stream_url'] ?? json['video_stream_url'])?.toString(),
      audioStreamUrl: json['audio_stream_url']?.toString(),
      source: json['source']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'video_id': videoId,
    'title': title,
    'author': author,
    'duration': duration,
    'views': views,
    'thumbnail': thumbnail,
    'stream_url': videoStreamUrl,
    'audio_stream_url': audioStreamUrl,
    'source': source,
  };
}