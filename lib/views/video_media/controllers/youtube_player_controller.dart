// lib/modules/youtube/controllers/youtube_player_controller.dart
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:omni_video_player/omni_video_player.dart';
import '../../../network/app_http_overrides.dart';
import '../../../network/local_media_proxy_server.dart';
import '../../../services/youtube_service.dart';
import '../models/youtube_model.dart';

class YouTubePlayerController extends GetxController {
  final YouTubeVideoModel initialVideo;
  YouTubePlayerController({required this.initialVideo});

  final YouTubeService _service = YouTubeService();

  OmniPlaybackController? omniController;

  final Rx<YouTubeVideoModel> videoDetail = Rx<YouTubeVideoModel>(
    YouTubeVideoModel(
      videoId: '',
      title: '',
      author: '',
      duration: '',
      thumbnail: '',
      views: '',
    ),
  );

  final RxList<YouTubeVideoModel> relatedVideos = <YouTubeVideoModel>[].obs;
  final RxBool isPlaying = false.obs;
  final RxBool isFullScreen = false.obs;
  final RxString currentVideoUrl = ''.obs;

  @override
  void onInit() {
    super.onInit();
    videoDetail.value = initialVideo;
    AppHttpOverrides.enableProxy();
    LocalMediaProxyServer.instance.start();

    final vid = initialVideo.videoId.isNotEmpty ? initialVideo.videoId : 'dQw4w9WgXcQ';
    currentVideoUrl.value = 'https://www.youtube.com/watch?v=$vid';

    _loadRelatedVideos(initialVideo.author.isNotEmpty ? initialVideo.author : 'Trending');
  }

  void onControllerCreated(OmniPlaybackController controller) {
    omniController = controller..addListener(_onPlayerUpdate);
  }

  void _onPlayerUpdate() {
    if (omniController != null) {
      isPlaying.value = omniController!.isPlaying;
    }
  }

  void togglePlayPause() {
    if (omniController == null) return;
    if (omniController!.isPlaying) {
      omniController!.pause();
    } else {
      omniController!.play();
    }
  }

  void playNewVideo(YouTubeVideoModel video) {
    videoDetail.value = video;
    final vid = video.videoId.isNotEmpty ? video.videoId : 'dQw4w9WgXcQ';
    currentVideoUrl.value = 'https://www.youtube.com/watch?v=$vid';
    _loadRelatedVideos(video.author);
  }

  Future<void> _loadRelatedVideos(String author) async {
    try {
      final results = await _service.searchVideos(author, limit: 12);
      relatedVideos.assignAll(results.where((v) => v.videoId != videoDetail.value.videoId).toList());
    } catch (_) {}
  }

  @override
  void onClose() {
    AppHttpOverrides.disableProxy();
    omniController?.removeListener(_onPlayerUpdate);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.onClose();
  }
}