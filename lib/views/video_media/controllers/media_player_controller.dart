// lib/views/video_media/controllers/media_player_controller.dart
import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/media_item_model.dart';
import '../views/media_player_view.dart';

class MediaPlayerController extends GetxController {
  static MediaPlayerController get to => Get.find<MediaPlayerController>();

  // 经典高级品牌色系
  final Color primaryColor = const Color.fromRGBO(44, 123, 109, 1.0); // 桉树深青
  final Color accentAmber = const Color(0xFFD97706); // 质感琥珀金
  final Color obsidianBg = const Color(0xFF0F172A); // 曜石深黑

  final YoutubeExplode _yt = YoutubeExplode();

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
  final RxBool isVideoMode = false.obs; // true: 视频模式, false: 黑胶纯音频
  final Rx<Duration> currentPosition = Duration.zero.obs;
  final Rx<Duration> totalDuration = Duration.zero.obs;

  // 🌟 结合当下前沿热搜趋势的潮流分类标签池
  final List<Map<String, String>> trendingChips = [
    {'name': '🔥 实时热播', 'query': 'Trending music video hot'},
    {'name': '🎵 爆款流行', 'query': '最新流行热门歌曲榜单'},
    {'name': '☕ 专注Lo-Fi', 'query': 'Lofi hip hop chill beats study relax'},
    {'name': '🤖 科技AI前沿', 'query': 'Artificial Intelligence tech documentary'},
    {'name': '🎙️ 深度播客', 'query': 'Podcast interview story'},
    {'name': '🎬 4K视觉原声', 'query': '4K HDR cinematic nature soundtrack'},
    {'name': '🌙 晚安白噪音', 'query': 'Rain ambient sleep sound'},
  ];

  @override
  void onInit() {
    super.onInit();
    _setupAudioListeners();
    // 默认加载第一个热点趋势
    loadCategoryFeeds(trendingChips.first['query']!);
  }

  @override
  void onClose() {
    _disposePlayers();
    _yt.close();
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

  /// 切换潮流分类胶囊
  void selectTrendTag(Map<String, String> chip) {
    selectedTrendTag.value = chip['name']!;
    loadCategoryFeeds(chip['query']!);
  }

  /// 🌟 依据分类或关键词拉取内容
  Future<void> loadCategoryFeeds(String query) async {
    isLoading.value = true;
    try {
      // 🌟 使用 var 或 VideoSearchList 接收返回值
      final VideoSearchList searchResults = await _yt.search.search(query);
      final List<MediaItemModel> items = [];

      for (final Video video in searchResults.take(18)) {
        items.add(MediaItemModel.fromYoutubeVideo(video));
      }

      mediaList.assignAll(items);
    } catch (e) {
      debugPrint("❌ [Media] 搜索加载异常: $e");
      Fluttertoast.showToast(msg: "媒体数据加载异常，请检查隧道连接");
    } finally {
      isLoading.value = false;
    }
  }

  /// 🌟 搜索框提交强搜索
  Future<void> searchMedia(String keyword) async {
    if (keyword.trim().isEmpty) return;
    HapticFeedback.lightImpact();
    isSearching.value = true;
    isLoading.value = true;
    try {
      final VideoSearchList searchResults = await _yt.search.search(keyword.trim());
      final List<MediaItemModel> items = [];

      for (final Video video in searchResults) {
        items.add(MediaItemModel.fromYoutubeVideo(video));
      }

      mediaList.assignAll(items);
    } catch (e) {
      debugPrint("❌ [Media] 搜索异常: $e");
      Fluttertoast.showToast(msg: "搜索异常: $e");
    } finally {
      isLoading.value = false;
    }
  }
  /// 🌟 播放媒体（支持本地离线秒开 & 在线流解析）
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

      // 1. 优先检测本地离线文件
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

      // 2. 在线流解析模式（走 Atsign 隧道直连解析）
      final manifest = await _yt.videos.streamsClient.getManifest(item.id);

      if (isVideoMode.value) {
        final muxedStream = manifest.muxed.withHighestBitrate();
        final videoUrl = muxedStream.url.toString();

        videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
        await videoPlayerController!.initialize();
        _bindVideoListeners();
        videoPlayerController!.play();
      } else {
        final audioStream = manifest.audioOnly.withHighestBitrate();
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

  /// 切换【超清视频】与【黑胶音频】
  void toggleVideoAudioMode() {
    if (currentPlaying.value == null) return;
    playMedia(currentPlaying.value!, asVideo: !isVideoMode.value);
  }

  /// 播放与暂停切换
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

  /// 🌟 退出播放器页面时的安全暂停处理
  void pauseOnPlayerExit() {
    if (isVideoMode.value) {
      videoPlayerController?.pause();
    } else {
      audioPlayer.pause();
    }
    isPlaying.value = false;
  }

  /// 拖动进度条
  void seekTo(Duration position) {
    if (isVideoMode.value && videoPlayerController != null) {
      videoPlayerController!.seekTo(position);
    } else {
      audioPlayer.seek(position);
    }
  }

  /// 本地下载管理器
  Future<void> downloadMediaToLocal(MediaItemModel item, {bool downloadVideo = false}) async {
    if (item.isDownloaded.value) {
      Fluttertoast.showToast(msg: "该文件已保存在本地设备");
      return;
    }
    if (item.isDownloading.value) {
      Fluttertoast.showToast(msg: "下载任务正在进行中...");
      return;
    }

    HapticFeedback.mediumImpact();
    item.isDownloading.value = true;
    item.downloadProgress.value = 0.01;
    Fluttertoast.showToast(msg: "已加入后台下载队列...");

    IOSink? fileSink;
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

      final manifest = await _yt.videos.streamsClient.getManifest(item.id);
      final streamInfo = downloadVideo ? manifest.muxed.withHighestBitrate() : manifest.audioOnly.withHighestBitrate();
      final stream = _yt.videos.streamsClient.get(streamInfo);

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
        msg: "🎉 《${item.title}》已成功保存至离线目录！",
        toastLength: Toast.LENGTH_LONG,
      );
    } catch (e) {
      await fileSink?.close();
      item.isDownloading.value = false;
      item.downloadProgress.value = 0.0;
      debugPrint("❌ [Download] 本地下载异常: $e");
      Fluttertoast.showToast(msg: "下载失败: $e");
    }
  }
}