// lib/controllers/youtube_player_controller.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../../network/local_media_proxy_server.dart';
import '../../../services/youtube_service.dart';
import '../models/youtube_model.dart';

class YouTubePlayerController extends GetxController {
  final YouTubeVideoModel initialVideo;
  YouTubePlayerController({required this.initialVideo});

  final YouTubeService _service = YouTubeService();

  late final Player player;
  late final VideoController playerVideoController;

  final List<StreamSubscription> _subscriptions = [];
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

  // 记录选中的唯一清晰度标签
  final RxString selectedStreamItag = ''.obs;
  final RxString currentQualityLabel = '360p'.obs;

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
  final RxDouble playbackSpeed = 1.0.obs;

  final RxBool isForwardingRipple = false.obs;
  final RxBool isRewindingRipple = false.obs;

  @override
  void onInit() {
    super.onInit();
    videoDetail.value = initialVideo;

    // 🌟 1. 配置播放器 16MB 滑动缓冲区
    player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 16 * 1024 * 1024,
      ),
    );
    playerVideoController = VideoController(player);

    _bindPlayerEvents();
    initVideoPlayer(initialVideo.videoId);
  }

  void _bindPlayerEvents() {
    _subscriptions.add(player.stream.playing.listen((playing) {
      isPlaying.value = playing;
      if (playing) {
        isLoading.value = false;
      }
    }));

    _subscriptions.add(player.stream.buffering.listen((buffering) {
      isBuffering.value = buffering;
    }));

    _subscriptions.add(player.stream.position.listen((pos) {
      currentPosition.value = pos;
    }));

    _subscriptions.add(player.stream.duration.listen((dur) {
      if (dur > Duration.zero) {
        totalDuration.value = dur;
      }
    }));

    _subscriptions.add(player.stream.buffer.listen((buf) {
      bufferedPosition.value = buf;
    }));

    _subscriptions.add(player.stream.error.listen((err) {
      if (err.isNotEmpty) {
        debugPrint("🔴 [MediaKit Error] $err");
      }
    }));
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

      // 🌟 2. 核心去重算法：每个分辨率（如 1080p, 720p, 480p）严格只保留 1 个最佳选项
      final Map<String, VideoStreamQualityModel> uniqueStreamsMap = {};

      // 优先存入复合流（360p 复合流自带音频）
      for (final s in result.formatStreams) {
        uniqueStreamsMap[s.qualityLabel] = s;
      }

      // 再存入高清流（若已有 WebM，优先替换为兼容性更好的 MP4）
      for (final s in result.adaptiveVideoStreams) {
        if (!uniqueStreamsMap.containsKey(s.qualityLabel)) {
          uniqueStreamsMap[s.qualityLabel] = s;
        } else {
          final existing = uniqueStreamsMap[s.qualityLabel]!;
          if (existing.container.toLowerCase() == 'webm' && s.container.toLowerCase() == 'mp4') {
            uniqueStreamsMap[s.qualityLabel] = s;
          }
        }
      }

      // 按照分辨率数字从高到低严格排序（2160p -> 1440p -> 1080p -> 720p -> 480p -> 360p）
      final sortedStreams = uniqueStreamsMap.values.toList()
        ..sort((a, b) {
          final hA = _parseHeightFromQuality(a.qualityLabel);
          final hB = _parseHeightFromQuality(b.qualityLabel);
          return hB.compareTo(hA);
        });

      allAvailableStreams.assignAll(sortedStreams);

      // 🌟 3. 启动播放
      if (result.isLive && result.hlsUrl.isNotEmpty) {
        final proxiedHls = LocalMediaProxyServer.instance.buildPlayUrl(result.hlsUrl);
        currentQualityLabel.value = 'LIVE';
        selectedStreamItag.value = 'live_hls';
        await player.setVolume(100.0);
        await player.open(Media(proxiedHls), play: true);
      } else if (allAvailableStreams.isNotEmpty) {
        // 默认优先启动 720p / 1080p 或 360p 复合流
        final defaultStream = allAvailableStreams.firstWhereOrNull((s) => s.qualityLabel.contains('720')) ??
            allAvailableStreams.firstWhereOrNull((s) => s.qualityLabel.contains('1080')) ??
            allAvailableStreams.first;
        await _playStreamWithAudio(defaultStream, Duration.zero);
      } else if (result.rawVideoUrl.isNotEmpty) {
        final proxiedUrl = LocalMediaProxyServer.instance.buildPlayUrl(result.rawVideoUrl);
        currentQualityLabel.value = '360p';
        selectedStreamItag.value = '18';
        await player.setVolume(100.0);
        await player.open(Media(proxiedUrl), play: true);
      }

      _startControlsTimer();
    } catch (_) {
      isError.value = true;
    } finally {
      isLoading.value = false;
    }
  }

  /// 🌟 核心播放逻辑：强行激活音量，双轨合流
  Future<void> _playStreamWithAudio(VideoStreamQualityModel stream, Duration startPos) async {
    selectedStreamItag.value = stream.itag;
    currentQualityLabel.value = stream.qualityLabel;

    final proxiedVideoUrl = LocalMediaProxyServer.instance.buildPlayUrl(stream.url);
    final rawAudio = streamDetail.value?.primaryAudioTrack?.url ?? (streamDetail.value?.rawAudioUrl ?? '');

    // 打开视频主轨道
    await player.open(
      Media(proxiedVideoUrl),
      play: true,
    );

    // 确保满格音量
    await player.setVolume(100.0);

    // 🌟 如果是高清分离画面轨，挂载独立立体声音轨
    if (stream.isAdaptive && rawAudio.isNotEmpty) {
      final proxiedAudioUrl = LocalMediaProxyServer.instance.buildPlayUrl(rawAudio);
      await player.setAudioTrack(
        AudioTrack.uri(proxiedAudioUrl, title: 'Main Stereo', language: 'en'),
      );
    }

    if (startPos > Duration.zero) {
      await player.seek(startPos);
    }

    if (playbackSpeed.value != 1.0) {
      await player.setRate(playbackSpeed.value);
    }
  }

  Future<void> switchQuality(VideoStreamQualityModel stream) async {
    final currentPos = currentPosition.value;
    isLoading.value = true;
    await _playStreamWithAudio(stream, currentPos);
    isLoading.value = false;
  }

  int _parseHeightFromQuality(String label) {
    if (label.contains('2160')) return 2160;
    if (label.contains('1440')) return 1440;
    if (label.contains('1080')) return 1080;
    if (label.contains('720')) return 720;
    if (label.contains('480')) return 480;
    if (label.contains('360')) return 360;
    if (label.contains('240')) return 240;
    if (label.contains('144')) return 144;
    return 360;
  }

  void setSpeed(double speed) {
    playbackSpeed.value = speed;
    player.setRate(speed);
  }

  void togglePlay() {
    player.playOrPause();
    if (isPlaying.value) {
      _startControlsTimer();
    } else {
      _cancelControlsTimer();
      showControls.value = true;
    }
  }

  void seekTo(Duration position) {
    player.seek(position);
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
    player.pause();
  }

  @override
  void onClose() {
    _cancelControlsTimer();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    player.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.onClose();
  }
}