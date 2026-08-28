// lib/controllers/youtube_player_controller.dart
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:video_player/video_player.dart';
import '../../../network/local_media_proxy_server.dart';
import '../../../services/youtube_service.dart';
import '../models/youtube_model.dart';

class YouTubePlayerController extends GetxController {
  final YouTubeVideoModel initialVideo;
  YouTubePlayerController({required this.initialVideo});

  final YouTubeService _service = YouTubeService();

  VideoPlayerController? videoPlayerController;
  Timer? _controlsTimer;

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
  final Rx<VideoDetailStreamResult?> streamDetail = Rx<VideoDetailStreamResult?>(null);

  final RxList<VideoStreamQualityModel> allAvailableStreams = <VideoStreamQualityModel>[].obs;

  final RxBool isLoading = true.obs;
  final RxBool isPlaying = false.obs;
  final RxBool isBuffering = false.obs;
  final RxBool isError = false.obs;
  final RxBool showControls = true.obs;
  final RxBool isFullScreen = false.obs;
  final RxBool isDescriptionExpanded = false.obs;

  final Rx<Duration> currentPosition = Duration.zero.obs;
  final Rx<Duration> totalDuration = Duration.zero.obs;
  final Rx<Duration> bufferedPosition = Duration.zero.obs;

  final RxString currentQualityLabel = 'Auto (HLS)'.obs;
  final RxDouble playbackSpeed = 1.0.obs;

  final RxBool isForwardingRipple = false.obs;
  final RxBool isRewindingRipple = false.obs;

  @override
  void onInit() {
    super.onInit();
    videoDetail.value = initialVideo;
    initVideoPlayer(initialVideo.videoId);
  }

  Future<void> initVideoPlayer(String videoId) async {
    if (videoId.isEmpty) return;
    try {
      isLoading.value = true;
      isError.value = false;

      final result = await _service.fetchVideoDetail(videoId);
      if (result == null) {
        isError.value = true;
        isLoading.value = false;
        return;
      }

      streamDetail.value = result;

      videoDetail.value = YouTubeVideoModel(
        videoId: videoId,
        title: result.title.isNotEmpty ? result.title : videoDetail.value.title,
        author: result.author.isNotEmpty ? result.author : videoDetail.value.author,
        duration: result.isLive ? 'LIVE' : (result.duration.isNotEmpty ? result.duration : videoDetail.value.duration),
        thumbnail: result.thumbnail.isNotEmpty ? result.thumbnail : videoDetail.value.thumbnail,
        views: result.viewCount.isNotEmpty ? '${result.viewCount}次观看' : videoDetail.value.views,
      );

      if (result.recommendedVideos.isNotEmpty) {
        relatedVideos.assignAll(result.recommendedVideos);
      } else {
        _loadFallbackRelatedVideos(result.author.isNotEmpty ? result.author : 'Trending');
      }

      final qualityOptions = <VideoStreamQualityModel>[];

      if (result.hlsUrl.isNotEmpty) {
        qualityOptions.add(VideoStreamQualityModel(
          itag: 'hls_auto',
          quality: 'auto',
          qualityLabel: 'Auto (最高画质+音频)',
          resolution: '1080p',
          container: 'HLS',
          encoding: 'h264+aac',
          fps: 60,
          size: '',
          bitrate: '',
          url: result.hlsUrl,
          isHls: true,
        ));
      }

      for (final s in result.formatStreams) {
        qualityOptions.add(s);
      }

      for (final s in result.adaptiveVideoStreams) {
        if (!qualityOptions.any((e) => e.qualityLabel == s.qualityLabel)) {
          qualityOptions.add(s);
        }
      }

      allAvailableStreams.assignAll(qualityOptions);

      String targetPlayUrl = result.hlsUrl;
      if (targetPlayUrl.isEmpty && result.formatStreams.isNotEmpty) {
        targetPlayUrl = result.formatStreams.first.url;
      }
      if (targetPlayUrl.isEmpty) {
        targetPlayUrl = result.rawVideoUrl;
      }

      if (targetPlayUrl.isEmpty) {
        isError.value = true;
        isLoading.value = false;
        return;
      }

      currentQualityLabel.value = result.hlsUrl.isNotEmpty ? 'Auto (1080p)' : '720p';

      final proxiedPlayUrl = LocalMediaProxyServer.instance.buildPlayUrl(targetPlayUrl);
      await _setupPlayerInstance(proxiedPlayUrl, Duration.zero);
    } catch (_) {
      isError.value = true;
    } finally {
      isLoading.value = false;
    }
  }

  /// 🌟 关键修复：实例化前立即静音并销毁旧播放器，彻底杜绝声音叠加
  Future<void> _setupPlayerInstance(String url, Duration seekTo) async {
    final oldController = videoPlayerController;
    videoPlayerController = null; // 立即切断引用

    if (oldController != null) {
      oldController.removeListener(_playerListener);
      try {
        await oldController.pause(); // 🌟 立即暂停，旧音频瞬间停止！
        await oldController.dispose(); // 🌟 立即从底层释放 ExoPlayer 实例
      } catch (_) {}
    }

    final newController = VideoPlayerController.networkUrl(
      Uri.parse(url),
      httpHeaders: {
        'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      },
    );

    await newController.initialize();
    await newController.setPlaybackSpeed(playbackSpeed.value);

    if (seekTo > Duration.zero) {
      await newController.seekTo(seekTo);
    }

    await newController.play();
    newController.addListener(_playerListener);

    videoPlayerController = newController;
    _startControlsTimer();
  }

  void _playerListener() {
    final ctrl = videoPlayerController;
    if (ctrl == null || !ctrl.value.isInitialized) return;

    isPlaying.value = ctrl.value.isPlaying;
    isBuffering.value = ctrl.value.isBuffering;
    currentPosition.value = ctrl.value.position;
    totalDuration.value = ctrl.value.duration;

    if (ctrl.value.buffered.isNotEmpty) {
      bufferedPosition.value = ctrl.value.buffered.last.end;
    }
  }

  /// 切换清晰度（记录进度 ➡️ 立即静音旧画面 ➡️ 载入新清晰度续播）
  Future<void> switchQuality(VideoStreamQualityModel stream) async {
    final currentPos = currentPosition.value;
    currentQualityLabel.value = stream.qualityLabel;
    isLoading.value = true;

    // 立即暂停当前画面
    try {
      await videoPlayerController?.pause();
    } catch (_) {}

    final targetUrl = stream.isHls
        ? stream.url
        : (stream.url.isNotEmpty ? stream.url : (streamDetail.value?.hlsUrl ?? ''));

    final proxiedPlayUrl = LocalMediaProxyServer.instance.buildPlayUrl(targetUrl);
    await _setupPlayerInstance(proxiedPlayUrl, currentPos);
    isLoading.value = false;
  }

  void setSpeed(double speed) {
    playbackSpeed.value = speed;
    videoPlayerController?.setPlaybackSpeed(speed);
  }

  void togglePlay() {
    final ctrl = videoPlayerController;
    if (ctrl == null) return;
    if (ctrl.value.isPlaying) {
      ctrl.pause();
      _cancelControlsTimer();
      showControls.value = true;
    } else {
      ctrl.play();
      _startControlsTimer();
    }
  }

  void seekTo(Duration position) {
    videoPlayerController?.seekTo(position);
  }

  void rewind10Seconds() {
    final newPos = currentPosition.value - const Duration(seconds: 10);
    seekTo(newPos > Duration.zero ? newPos : Duration.zero);
    isRewindingRipple.value = true;
    Future.delayed(const Duration(milliseconds: 600), () => isRewindingRipple.value = false);
    _startControlsTimer();
  }

  void forward10Seconds() {
    final newPos = currentPosition.value + const Duration(seconds: 10);
    seekTo(newPos < totalDuration.value ? newPos : totalDuration.value);
    isForwardingRipple.value = true;
    Future.delayed(const Duration(milliseconds: 600), () => isForwardingRipple.value = false);
    _startControlsTimer();
  }

  void toggleControls() {
    showControls.value = !showControls.value;
    if (showControls.value && isPlaying.value) {
      _startControlsTimer();
    } else {
      _cancelControlsTimer();
    }
  }

  void toggleFullScreen() {
    isFullScreen.value = !isFullScreen.value;
    if (isFullScreen.value) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  void toggleDescription() {
    isDescriptionExpanded.value = !isDescriptionExpanded.value;
  }

  void _startControlsTimer() {
    _cancelControlsTimer();
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (isPlaying.value) {
        showControls.value = false;
      }
    });
  }

  void _cancelControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = null;
  }

  Future<void> _loadFallbackRelatedVideos(String author) async {
    try {
      final results = await _service.searchVideos(author, limit: 12);
      relatedVideos.assignAll(results.where((v) => v.videoId != initialVideo.videoId).toList());
    } catch (_) {}
  }

  void stopPlayback() {
    videoPlayerController?.pause();
  }

  @override
  void onClose() {
    _cancelControlsTimer();
    videoPlayerController?.removeListener(_playerListener);
    videoPlayerController?.dispose();
    videoPlayerController = null;
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.onClose();
  }
}