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

  // 🌟 核心修复：使用唯一 itag 记录当前选中的画质，杜绝多选
  final RxString selectedStreamItag = ''.obs;
  final RxString currentQualityLabel = '1080p'.obs;

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

    player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 32 * 1024 * 1024,
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

      // 🌟 1. 组装清晰度列表并去重
      final qualityOptions = <VideoStreamQualityModel>[];

      for (final s in result.adaptiveVideoStreams) {
        qualityOptions.add(s);
      }
      for (final s in result.formatStreams) {
        if (!qualityOptions.any((e) => e.qualityLabel == s.qualityLabel)) {
          qualityOptions.add(s);
        }
      }

      allAvailableStreams.assignAll(qualityOptions);

      // 🌟 2. 启动播放
      if (result.isLive && result.hlsUrl.isNotEmpty) {
        final proxiedHls = LocalMediaProxyServer.instance.buildPlayUrl(result.hlsUrl);
        currentQualityLabel.value = 'LIVE';
        selectedStreamItag.value = 'live_hls';
        await player.setVolume(100.0);
        await player.open(Media(proxiedHls), play: true);
      } else if (allAvailableStreams.isNotEmpty) {
        final preferred = allAvailableStreams.firstWhereOrNull((s) => s.qualityLabel.contains('1080')) ??
            allAvailableStreams.firstWhereOrNull((s) => s.qualityLabel.contains('720')) ??
            allAvailableStreams.first;
        await _playStreamWithAudio(preferred, Duration.zero);
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

  /// 🌟 核心：确保 100% 音量与音轨挂载生效
  Future<void> _playStreamWithAudio(VideoStreamQualityModel stream, Duration startPos) async {
    selectedStreamItag.value = stream.itag;
    currentQualityLabel.value = stream.qualityLabel;

    final proxiedVideoUrl = LocalMediaProxyServer.instance.buildPlayUrl(stream.url);
    final rawAudio = streamDetail.value?.primaryAudioTrack?.url ?? (streamDetail.value?.rawAudioUrl ?? '');

    // 确保默认音量为 100%
    await player.setVolume(100.0);

    // 打开视频轨
    await player.open(
      Media(proxiedVideoUrl),
      play: true,
    );

    // 🌟 如果是分离轨且有音轨，挂载独立音轨并激活
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