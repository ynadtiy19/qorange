import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:omni_video_player/omni_video_player.dart';
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

  @override
  void onInit() {
    super.onInit();
    videoDetail.value = initialVideo;
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

  Future<void> _loadRelatedVideos(String author) async {
    try {
      final results = await _service.searchVideos(author, limit: 12);
      relatedVideos.assignAll(results.where((v) => v.videoId != initialVideo.videoId).toList());
    } catch (_) {}
  }

  @override
  void onClose() {
    omniController?.removeListener(_onPlayerUpdate);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.onClose();
  }
}