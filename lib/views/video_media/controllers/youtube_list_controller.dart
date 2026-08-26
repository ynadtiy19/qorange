import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../services/youtube_service.dart';
import '../models/youtube_model.dart';

class YouTubeListController extends GetxController {
  final YouTubeService _service = YouTubeService();
  final TextEditingController searchTextController = TextEditingController();

  final RxList<YouTubeVideoModel> videoList = <YouTubeVideoModel>[].obs;
  final RxBool isLoading = false.obs;
  final RxString currentTag = 'Flutter 2026'.obs;
  final RxString searchKeyword = ''.obs;

  final List<String> categoryTags = [
    'Flutter 2026',
    'Lofi Coffee',
    'Acoustic Pop',
    'Tech Minimal',
    'Art & Design',
    'Nature Walk',
    'Ambient Piano',
  ];

  Timer? _debounceTimer;

  @override
  void onInit() {
    super.onInit();
    fetchVideosByTag(currentTag.value);
  }

  void onTagSelected(String tag) {
    if (currentTag.value == tag) return;
    currentTag.value = tag;
    searchTextController.clear();
    searchKeyword.value = '';
    fetchVideosByTag(tag);
  }

  void onSearchChanged(String query) {
    searchKeyword.value = query;
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 600), () {
      if (query.trim().isNotEmpty) {
        currentTag.value = '';
        fetchVideosByQuery(query.trim());
      } else {
        onTagSelected(categoryTags.first);
      }
    });
  }

  Future<void> fetchVideosByTag(String tag) async {
    isLoading.value = true;
    try {
      final results = await _service.searchVideos(tag, limit: 20);
      videoList.assignAll(results);
    } catch (e) {
      Get.snackbar('加载提示', e.toString(), snackPosition: SnackPosition.BOTTOM);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> fetchVideosByQuery(String query) async {
    isLoading.value = true;
    try {
      final results = await _service.searchVideos(query, limit: 20);
      videoList.assignAll(results);
    } catch (e) {
      Get.snackbar('搜索提示', e.toString(), snackPosition: SnackPosition.BOTTOM);
    } finally {
      isLoading.value = false;
    }
  }

  @override
  void onClose() {
    _debounceTimer?.cancel();
    searchTextController.dispose();
    super.onClose();
  }
}