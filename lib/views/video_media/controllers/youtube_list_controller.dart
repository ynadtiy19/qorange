// lib/views/video_media/controllers/youtube_list_controller.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/youtube_service.dart';
import '../models/youtube_model.dart';

class YouTubeListController extends GetxController {
  final YouTubeService _service = YouTubeService();
  final TextEditingController searchTextController = TextEditingController();
  final ScrollController scrollController = ScrollController();

  final RxList<YouTubeVideoModel> videoList = <YouTubeVideoModel>[].obs;
  final RxList<String> searchHistory = <String>[].obs;

  final RxBool isLoading = false.obs;
  final RxBool isMoreLoading = false.obs;
  final RxBool hasMore = true.obs;
  final RxBool isSearchFocused = false.obs;

  final RxString currentTag = '热门推荐'.obs;
  final RxString currentSearchQuery = ''.obs;
  final RxInt currentPage = 1.obs;

  static const String _kHistoryPrefsKey = 'youtube_search_history_v1';

  final List<String> categoryTags = [
    '热门推荐',
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
    _loadSearchHistory();
    _initScrollListener();
    fetchVideosByTag(currentTag.value);
  }

  void _initScrollListener() {
    scrollController.addListener(() {
      if (scrollController.position.pixels >= scrollController.position.maxScrollExtent - 200) {
        if (!isLoading.value && !isMoreLoading.value && hasMore.value) {
          loadMoreVideos();
        }
      }
    });
  }

  Future<void> _loadSearchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final history = prefs.getStringList(_kHistoryPrefsKey) ?? [];
      searchHistory.assignAll(history);
    } catch (_) {}
  }

  Future<void> _saveSearchTerm(String term) async {
    final query = term.trim();
    if (query.isEmpty) return;

    searchHistory.remove(query);
    searchHistory.insert(0, query);
    if (searchHistory.length > 15) {
      searchHistory.removeLast();
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kHistoryPrefsKey, searchHistory.toList());
    } catch (_) {}
  }

  Future<void> deleteHistoryItem(String query) async {
    searchHistory.remove(query);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kHistoryPrefsKey, searchHistory.toList());
    } catch (_) {}
  }

  Future<void> clearAllHistory() async {
    searchHistory.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kHistoryPrefsKey);
    } catch (_) {}
  }

  void onTagSelected(String tag) {
    if (currentTag.value == tag && !isLoading.value) return;
    currentTag.value = tag;
    currentSearchQuery.value = '';
    searchTextController.clear();
    isSearchFocused.value = false;
    currentPage.value = 1;
    hasMore.value = true;
    fetchVideosByTag(tag);
  }

  /// 🌟 修复：输入时立即响应式更新 currentSearchQuery.value
  void onSearchChanged(String query) {
    currentSearchQuery.value = query;
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 600), () {
      if (query.trim().isNotEmpty) {
        performSearch(query.trim());
      }
    });
  }

  void performSearch(String query) {
    final q = query.trim();
    if (q.isEmpty) return;

    currentTag.value = '';
    currentSearchQuery.value = q;
    isSearchFocused.value = false;
    currentPage.value = 1;
    hasMore.value = true;
    _saveSearchTerm(q);
    fetchVideosByQuery(q, page: 1);
  }

  Future<void> fetchVideosByTag(String tag) async {
    isLoading.value = true;
    currentPage.value = 1;
    hasMore.value = true;

    try {
      List<YouTubeVideoModel> results = [];
      if (tag == '热门推荐') {
        results = await _service.fetchTrendingVideos();
      } else {
        results = await _service.searchVideos(tag, page: 1, limit: 20);
      }
      videoList.assignAll(results);
      if (results.length < 10) {
        hasMore.value = false;
      }
    } catch (e) {
      Fluttertoast.showToast(msg: '链接异常');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> fetchVideosByQuery(String query, {int page = 1}) async {
    isLoading.value = true;
    currentPage.value = page;

    try {
      final results = await _service.searchVideos(query, page: page, limit: 20);
      videoList.assignAll(results);
      if (results.length < 10) {
        hasMore.value = false;
      }
    } catch (e) {
      Fluttertoast.showToast(msg: '搜索失败');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadMoreVideos() async {
    if (isMoreLoading.value || !hasMore.value) return;

    isMoreLoading.value = true;
    final nextPage = currentPage.value + 1;

    try {
      final query = currentSearchQuery.value.isNotEmpty ? currentSearchQuery.value : currentTag.value;
      if (query.isEmpty || query == '热门推荐') {
        hasMore.value = false;
        return;
      }

      final results = await _service.searchVideos(query, page: nextPage, limit: 20);
      if (results.isEmpty) {
        hasMore.value = false;
      } else {
        videoList.addAll(results);
        currentPage.value = nextPage;
        if (results.length < 10) {
          hasMore.value = false;
        }
      }
    } catch (_) {
    } finally {
      isMoreLoading.value = false;
    }
  }

  @override
  void onClose() {
    _debounceTimer?.cancel();
    searchTextController.dispose();
    scrollController.dispose();
    super.onClose();
  }
}