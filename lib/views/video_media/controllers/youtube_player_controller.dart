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

  final RxString currentQualityLabel = '360p'.obs;
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

      // 1. 组装画质面板
      final qualityOptions = <VideoStreamQualityModel>[];

      for (final s in result.formatStreams) {
        qualityOptions.add(s);
      }
      for (final s in result.adaptiveVideoStreams) {
        if (!qualityOptions.any((e) => e.qualityLabel == s.qualityLabel)) {
          qualityOptions.add(s);
        }
      }

      allAvailableStreams.assignAll(qualityOptions);

      // 🌟 2. 核心启动策略：
      // 直播 -> 走 HLS (.m3u8)
      // 点播 -> 默认 360p 复合流秒开（0秒启动，100%有立体声）
      String targetPlayUrl = '';
      VideoFormat formatHint = VideoFormat.other;

      if (result.isLive && result.hlsUrl.isNotEmpty) {
        targetPlayUrl = LocalMediaProxyServer.instance.buildPlayUrl(result.hlsUrl);
        currentQualityLabel.value = 'LIVE';
        formatHint = VideoFormat.hls;
      } else if (result.formatStreams.isNotEmpty) {
        targetPlayUrl = LocalMediaProxyServer.instance.buildPlayUrl(result.formatStreams.first.url);
        currentQualityLabel.value = result.formatStreams.first.qualityLabel;
        formatHint = VideoFormat.other;
      } else if (result.adaptiveVideoStreams.isNotEmpty) {
        // 只有分片流时，生成本地 MPEG-DASH (.mpd) 合流清单（带上音频）
        final v = result.adaptiveVideoStreams.first;
        final a = result.primaryAudioTrack;
        targetPlayUrl = LocalMediaProxyServer.instance.buildDashManifestUrl(
          videoUrl: v.url,
          audioUrl: a?.url ?? result.rawAudioUrl,
          videoInit: v.init,
          videoIndex: v.index,
          audioInit: a?.init ?? '0-600',
          audioIndex: a?.index ?? '601-900',
          videoBitrate: v.bitrate,
          audioBitrate: a?.bitrate ?? '130000',
          videoCodec: 'avc1.640028',
          audioCodec: 'mp4a.40.2',
          width: v.width,
          height: v.height,
          duration: result.lengthSeconds.toDouble(),
        );
        currentQualityLabel.value = v.qualityLabel;
        formatHint = VideoFormat.dash;
      }

      if (targetPlayUrl.isEmpty) {
        isError.value = true;
        isLoading.value = false;
        return;
      }

      await _setupPlayerInstance(targetPlayUrl, Duration.zero, formatHint: formatHint);
    } catch (_) {
      isError.value = true;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _setupPlayerInstance(String url, Duration seekTo, {VideoFormat formatHint = VideoFormat.other}) async {
    final oldController = videoPlayerController;
    videoPlayerController = null;

    if (oldController != null) {
      oldController.removeListener(_playerListener);
      try {
        await oldController.pause();
        await oldController.dispose();
      } catch (_) {}
    }

    final newController = VideoPlayerController.networkUrl(
      Uri.parse(url),
      formatHint: formatHint,
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

  /// 🌟 切换清晰度（如果是 720p/1080p 分片流，自动生成 DASH 双轨合流清单，确保 100% 有立体声声音）
  Future<void> switchQuality(VideoStreamQualityModel stream) async {
    final currentPos = currentPosition.value;
    currentQualityLabel.value = stream.qualityLabel;
    isLoading.value = true;

    try {
      await videoPlayerController?.pause();
    } catch (_) {}

    String targetPlayUrl = '';
    VideoFormat formatHint = VideoFormat.other;

    if (stream.isAdaptive) {
      // 1080p / 720p / 480p 分片流：动态生成 MPEG-DASH (.mpd) 合流清单
      final a = streamDetail.value?.primaryAudioTrack;
      targetPlayUrl = LocalMediaProxyServer.instance.buildDashManifestUrl(
        videoUrl: stream.url,
        audioUrl: a?.url ?? (streamDetail.value?.rawAudioUrl ?? ''),
        videoInit: stream.init,
        videoIndex: stream.index,
        audioInit: a?.init ?? '0-600',
        audioIndex: a?.index ?? '601-900',
        videoBitrate: stream.bitrate,
        audioBitrate: a?.bitrate ?? '130000',
        videoCodec: 'avc1.640028',
        audioCodec: 'mp4a.40.2',
        width: stream.width,
        height: stream.height,
        duration: (streamDetail.value?.lengthSeconds ?? 3600).toDouble(),
      );
      formatHint = VideoFormat.dash;
    } else {
      // 360p 复合流直接播放
      targetPlayUrl = LocalMediaProxyServer.instance.buildPlayUrl(stream.url);
      formatHint = VideoFormat.other;
    }

    await _setupPlayerInstance(targetPlayUrl, currentPos, formatHint: formatHint);
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