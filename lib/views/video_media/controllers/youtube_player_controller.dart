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

  // 播放状态响应式变量
  final RxBool isLoading = true.obs;
  final RxBool isPlaying = false.obs;
  final RxBool isBuffering = false.obs;
  final RxBool isError = false.obs;
  final RxBool showControls = true.obs;
  final RxBool isFullScreen = false.obs;

  final Rx<Duration> currentPosition = Duration.zero.obs;
  final Rx<Duration> totalDuration = Duration.zero.obs;
  final Rx<Duration> bufferedPosition = Duration.zero.obs;

  final RxString currentQualityLabel = '720p'.obs;
  final RxDouble playbackSpeed = 1.0.obs;

  // 双击快进/快退动画反馈标记
  final RxBool isForwardingRipple = false.obs;
  final RxBool isRewindingRipple = false.obs;

  @override
  void onInit() {
    super.onInit();
    videoDetail.value = initialVideo;
    _loadRelatedVideos(initialVideo.author.isNotEmpty ? initialVideo.author : 'Trending');
    initVideoPlayer(initialVideo.videoId);
  }

  /// 初始化视频流媒体
  Future<void> initVideoPlayer(String videoId) async {
    if (videoId.isEmpty) return;
    try {
      isLoading.value = true;
      isError.value = false;

      // 1. 请求 Dart Frog 后端获取格式化直链
      final result = await _service.fetchVideoDetail(videoId);
      if (result == null || (result.rawVideoUrl.isEmpty && result.formatStreams.isEmpty)) {
        isError.value = true;
        isLoading.value = false;
        return;
      }

      streamDetail.value = result;

      // 同步标题与时长
      videoDetail.value = YouTubeVideoModel(
        videoId: videoId,
        title: result.title.isNotEmpty ? result.title : videoDetail.value.title,
        author: result.author.isNotEmpty ? result.author : videoDetail.value.author,
        duration: result.duration.isNotEmpty ? result.duration : videoDetail.value.duration,
        thumbnail: result.thumbnail.isNotEmpty ? result.thumbnail : videoDetail.value.thumbnail,
        views: videoDetail.value.views,
      );

      // 2. 匹配默认清晰度 (优先 720p，其次 360p 或第一项)
      VideoStreamQualityModel? defaultStream;
      if (result.formatStreams.isNotEmpty) {
        defaultStream = result.formatStreams.firstWhereOrNull((s) => s.qualityLabel.contains('720')) ??
            result.formatStreams.firstWhereOrNull((s) => s.qualityLabel.contains('360')) ??
            result.formatStreams.first;
      }

      final rawTargetUrl = defaultStream != null ? defaultStream.url : result.rawVideoUrl;
      currentQualityLabel.value = defaultStream?.qualityLabel ?? 'Default';

      // 3. 构建本地代理中继地址
      final proxiedPlayUrl = LocalMediaProxyServer.instance.buildPlayUrl(rawTargetUrl);

      // 4. 启动 video_player 原生播放
      await _setupPlayerInstance(proxiedPlayUrl, Duration.zero);
    } catch (_) {
      isError.value = true;
    } finally {
      isLoading.value = false;
    }
  }

  /// 实例化并监听 video_player
  Future<void> _setupPlayerInstance(String url, Duration seekTo) async {
    final oldController = videoPlayerController;
    oldController?.removeListener(_playerListener);

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
    await oldController?.dispose();

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

  /// 切换清晰度（保留当前播放进度）
  Future<void> switchQuality(VideoStreamQualityModel stream) async {
    final currentPos = currentPosition.value;
    currentQualityLabel.value = stream.qualityLabel;
    isLoading.value = true;

    final proxiedPlayUrl = LocalMediaProxyServer.instance.buildPlayUrl(stream.url);
    await _setupPlayerInstance(proxiedPlayUrl, currentPos);
    isLoading.value = false;
  }

  /// 切换播放速度
  void setSpeed(double speed) {
    playbackSpeed.value = speed;
    videoPlayerController?.setPlaybackSpeed(speed);
  }

  /// 播放/暂停
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

  /// 跳转进度
  void seekTo(Duration position) {
    videoPlayerController?.seekTo(position);
  }

  /// 双击快退 10 秒
  void rewind10Seconds() {
    final newPos = currentPosition.value - const Duration(seconds: 10);
    seekTo(newPos > Duration.zero ? newPos : Duration.zero);
    isRewindingRipple.value = true;
    Future.delayed(const Duration(milliseconds: 600), () => isRewindingRipple.value = false);
    _startControlsTimer();
  }

  /// 双击快进 10 秒
  void forward10Seconds() {
    final newPos = currentPosition.value + const Duration(seconds: 10);
    seekTo(newPos < totalDuration.value ? newPos : totalDuration.value);
    isForwardingRipple.value = true;
    Future.delayed(const Duration(milliseconds: 600), () => isForwardingRipple.value = false);
    _startControlsTimer();
  }

  /// 切换控制栏显隐
  void toggleControls() {
    showControls.value = !showControls.value;
    if (showControls.value && isPlaying.value) {
      _startControlsTimer();
    } else {
      _cancelControlsTimer();
    }
  }

  /// 切换横竖屏全屏
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

  Future<void> _loadRelatedVideos(String author) async {
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