// lib/views/video_media/controllers/media_player_controller.dart
import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:http/io_client.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../../network/app_http_overrides.dart';
import '../../../network/app_ssh_tunnel_service.dart';
import '../models/media_item_model.dart';
import '../views/media_player_view.dart';

class MediaPlayerController extends GetxController {
  static MediaPlayerController get to => Get.find<MediaPlayerController>();

  final Color primaryColor = const Color.fromRGBO(44, 123, 109, 1.0);
  final Color accentAmber = const Color(0xFFD97706);
  final Color obsidianBg = const Color(0xFF0F172A);

  // 统一双引擎播放器
  final ap.AudioPlayer audioPlayer = ap.AudioPlayer();
  VideoPlayerController? videoPlayerController;

  // 列表与搜索状态
  final RxList<MediaItemModel> mediaList = <MediaItemModel>[].obs;
  final RxBool isLoading = true.obs;
  final RxBool isSearching = false.obs;
  final RxString selectedTrendTag = '🔥 实时热播'.obs;

  // 当前播放与进度状态
  final Rxn<MediaItemModel> currentPlaying = Rxn<MediaItemModel>();
  final RxBool isMediaLoading = false.obs;
  final RxBool isPlaying = false.obs;
  final RxBool isVideoMode = false.obs;
  final Rx<Duration> currentPosition = Duration.zero.obs;
  final Rx<Duration> totalDuration = Duration.zero.obs;

  final List<Map<String, String>> trendingChips = [
    {'name': '🔥 实时热播', 'query': 'Trending music video hot'},
    {'name': '🎵 爆款流行', 'query': '最新流行热门歌曲榜单'},
    {'name': '☕ 专注Lo-Fi', 'query': 'Lofi hip hop chill beats study relax'},
    {'name': '🤖 科技AI前沿', 'query': 'Artificial Intelligence tech documentary'},
    {'name': '🎙️ 深度播客', 'query': 'Podcast interview story'},
    {'name': '🎬 4K视觉原声', 'query': '4K HDR cinematic nature soundtrack'},
    {'name': '🌙 晚安白噪音', 'query': 'Rain ambient sleep sound'},
  ];

  /// 🌟 动态获取 YouTube 客户端（自动继承并应用全局隧道代理）
  YoutubeExplode _getYtClient() {
    int proxyPort = 0;
    try {
      if (Get.isRegistered<AppSshTunnelService>()) {
        proxyPort = AppSshTunnelService.to.currentSocks5Port.value;
      }
    } catch (_) {}

    // 确保全局代理生效
    if (proxyPort > 0 && HttpOverrides.current == null) {
      HttpOverrides.global = AppHttpOverrides(proxyPort: proxyPort);
    }

    // 🌟 3.x 版本直接实例化即可，底层会自动接管 HttpOverrides 中的代理配置
    return YoutubeExplode();
  }
  @override
  void onInit() {
    super.onInit();
    _setupAudioListeners();
    // 延迟 500ms 确保隧道握手完成
    Future.delayed(const Duration(milliseconds: 600), () {
      loadCategoryFeeds(trendingChips.first['query']!);
    });
  }

  @override
  void onClose() {
    _disposePlayers();
    super.onClose();
  }

  void _disposePlayers() {
    audioPlayer.stop();
    audioPlayer.dispose();
    videoPlayerController?.pause();
    videoPlayerController?.dispose();
    videoPlayerController = null;
  }

  void _setupAudioListeners() {
    audioPlayer.onPositionChanged.listen((pos) {
      if (!isVideoMode.value) currentPosition.value = pos;
    });
    audioPlayer.onDurationChanged.listen((dur) {
      if (!isVideoMode.value) totalDuration.value = dur;
    });
    audioPlayer.onPlayerStateChanged.listen((state) {
      if (!isVideoMode.value) {
        isPlaying.value = state == ap.PlayerState.playing;
      }
    });
  }

  void selectTrendTag(Map<String, String> chip) {
    selectedTrendTag.value = chip['name']!;
    loadCategoryFeeds(chip['query']!);
  }

  /// 🌟 依据关键词拉取内容（强行走本地代理）
  Future<void> loadCategoryFeeds(String query) async {
    isLoading.value = true;
    final yt = _getYtClient();
    try {
      final VideoSearchList searchResults = await yt.search.search(query);
      final List<MediaItemModel> items = [];

      for (final Video video in searchResults.take(18)) {
        items.add(MediaItemModel.fromYoutubeVideo(video));
      }

      mediaList.assignAll(items);
    } catch (e) {
      debugPrint("❌ [Media] 搜索加载异常: $e");
      Fluttertoast.showToast(msg: "正在通过安全隧道加速中...");
    } finally {
      yt.close();
      isLoading.value = false;
    }
  }

  /// 🌟 搜索框提交强搜索
  Future<void> searchMedia(String keyword) async {
    if (keyword.trim().isEmpty) return;
    HapticFeedback.lightImpact();
    isSearching.value = true;
    isLoading.value = true;
    final yt = _getYtClient();
    try {
      final VideoSearchList searchResults = await yt.search.search(keyword.trim());
      final List<MediaItemModel> items = [];

      for (final Video video in searchResults) {
        items.add(MediaItemModel.fromYoutubeVideo(video));
      }

      mediaList.assignAll(items);
    } catch (e) {
      debugPrint("❌ [Media] 搜索异常: $e");
      Fluttertoast.showToast(msg: "搜索异常: $e");
    } finally {
      yt.close();
      isLoading.value = false;
    }
  }

  /// 🌟 播放媒体（直接解析最高码率流）
  Future<void> playMedia(MediaItemModel item, {bool asVideo = false}) async {
    currentPlaying.value = item;
    isVideoMode.value = asVideo;
    isMediaLoading.value = true;

    Get.to(() => const MediaPlayerView(), transition: Transition.fadeIn);

    try {
      await audioPlayer.stop();
      await videoPlayerController?.pause();
      await videoPlayerController?.dispose();
      videoPlayerController = null;

      // 1. 本地离线文件模式
      if (item.isDownloaded.value && item.localFilePath.value.isNotEmpty) {
        final localFile = File(item.localFilePath.value);
        if (await localFile.exists()) {
          if (isVideoMode.value) {
            videoPlayerController = VideoPlayerController.file(localFile);
            await videoPlayerController!.initialize();
            _bindVideoListeners();
            videoPlayerController!.play();
          } else {
            await audioPlayer.play(ap.DeviceFileSource(localFile.path));
          }
          isMediaLoading.value = false;
          return;
        }
      }

      // 2. 在线流提取：指定 ytClients 模拟 Android/iOS/VR 移动设备，完美绕过机房限制
      final yt = _getYtClient();
      final StreamManifest manifest = await yt.videos.streams.getManifest(
        item.id,
        ytClients: [
          YoutubeApiClient.android,
          YoutubeApiClient.ios,
          YoutubeApiClient.androidVr,
          YoutubeApiClient.safari,
        ],
      );
      yt.close();

      if (isVideoMode.value) {
        // 优先提取有声音的音画合一流，若无则提取最高画质流
        final videoStream = manifest.muxed.isNotEmpty
            ? manifest.muxed.withHighestBitrate()
            : manifest.video.withHighestBitrate();
        final videoUrl = videoStream.url.toString();

        videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
        await videoPlayerController!.initialize();
        _bindVideoListeners();
        videoPlayerController!.play();
      } else {
        // 提取最高码率纯音频流
        final audioStream = manifest.audioOnly.isNotEmpty
            ? manifest.audioOnly.withHighestBitrate()
            : manifest.audio.withHighestBitrate();
        final audioUrl = audioStream.url.toString();

        await audioPlayer.play(ap.UrlSource(audioUrl));
      }
    } catch (e) {
      debugPrint("❌ [Media] 播放解析失败: $e");
      Fluttertoast.showToast(msg: "解析失败: $e");
    } finally {
      isMediaLoading.value = false;
    }
  }

  void _bindVideoListeners() {
    if (videoPlayerController == null) return;
    videoPlayerController!.addListener(() {
      if (isVideoMode.value && videoPlayerController != null) {
        currentPosition.value = videoPlayerController!.value.position;
        totalDuration.value = videoPlayerController!.value.duration;
        isPlaying.value = videoPlayerController!.value.isPlaying;
      }
    });
  }

  void toggleVideoAudioMode() {
    if (currentPlaying.value == null) return;
    playMedia(currentPlaying.value!, asVideo: !isVideoMode.value);
  }

  void togglePlayPause() {
    HapticFeedback.selectionClick();
    if (isVideoMode.value && videoPlayerController != null) {
      if (videoPlayerController!.value.isPlaying) {
        videoPlayerController!.pause();
      } else {
        videoPlayerController!.play();
      }
    } else {
      if (isPlaying.value) {
        audioPlayer.pause();
      } else {
        audioPlayer.resume();
      }
    }
  }

  void pauseOnPlayerExit() {
    if (isVideoMode.value) {
      videoPlayerController?.pause();
    } else {
      audioPlayer.pause();
    }
    isPlaying.value = false;
  }

  void seekTo(Duration position) {
    if (isVideoMode.value && videoPlayerController != null) {
      videoPlayerController!.seekTo(position);
    } else {
      audioPlayer.seek(position);
    }
  }
  /// 🌟 本地下载管理器（同步加入 ytClients 移动端伪装）
  Future<void> downloadMediaToLocal(MediaItemModel item, {bool downloadVideo = false}) async {
    if (item.isDownloaded.value) {
      Fluttertoast.showToast(msg: "该内容已保存在本地设备");
      return;
    }
    if (item.isDownloading.value) {
      Fluttertoast.showToast(msg: "正在下载中，请稍候...");
      return;
    }

    HapticFeedback.mediumImpact();
    item.isDownloading.value = true;
    item.downloadProgress.value = 0.01;
    Fluttertoast.showToast(msg: "已加入后台下载队列...");

    IOSink? fileSink;
    final yt = _getYtClient();
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final downloadDir = Directory('${appDir.path}/downloads');
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }

      final ext = downloadVideo ? "mp4" : "mp3";
      final String safeFileName = "${item.id}_${item.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.$ext";
      final String fullPath = "${downloadDir.path}/$safeFileName";
      final File targetFile = File(fullPath);
      if (await targetFile.exists()) {
        await targetFile.delete();
      }

      fileSink = targetFile.openWrite();

      // 🌟 加入 ytClients 移动端模拟
      final StreamManifest manifest = await yt.videos.streams.getManifest(
        item.id,
        ytClients: [
          YoutubeApiClient.android,
          YoutubeApiClient.ios,
          YoutubeApiClient.androidVr,
          YoutubeApiClient.safari,
        ],
      );

      final streamInfo = downloadVideo
          ? (manifest.muxed.isNotEmpty ? manifest.muxed.withHighestBitrate() : manifest.video.withHighestBitrate())
          : (manifest.audioOnly.isNotEmpty ? manifest.audioOnly.withHighestBitrate() : manifest.audio.withHighestBitrate());

      final stream = yt.videos.streams.get(streamInfo);
      final totalBytes = streamInfo.size.totalBytes;
      int receivedBytes = 0;

      await for (final chunk in stream) {
        fileSink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          item.downloadProgress.value = receivedBytes / totalBytes;
        }
      }

      await fileSink.flush();
      await fileSink.close();
      fileSink = null;

      item.isDownloading.value = false;
      item.isDownloaded.value = true;
      item.localFilePath.value = fullPath;
      item.downloadProgress.value = 1.0;

      Fluttertoast.showToast(
        msg: "🎉 《${item.title}》已成功下载至本地目录！",
        toastLength: Toast.LENGTH_LONG,
      );
    } catch (e) {
      await fileSink?.close();
      item.isDownloading.value = false;
      item.downloadProgress.value = 0.0;
      debugPrint("❌ [Download] 本地下载异常: $e");
      Fluttertoast.showToast(msg: "下载失败: $e");
    } finally {
      yt.close();
    }
  }
}