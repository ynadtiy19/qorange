import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../network/http_client.dart';
import 'community_model.dart';

class CommunityDiscoveryController extends GetxController {
  final ScrollController scrollController = ScrollController();

  // 状态变量
  final RxList<CommunityModel> communities = <CommunityModel>[].obs;
  final RxBool isLoading = true.obs;
  final RxBool isLoadingMore = false.obs;
  final RxBool hasMore = true.obs;

  // 过滤指标
  final RxString selectedCategory = 'trending'.obs; // 对应顶部药丸分类
  final RxString selectedPrice = 'all'.obs;        // all, free, paid
  final RxString selectedType = 'all'.obs;         // all, public, private
  final RxString selectedSort = 'trending'.obs;     // trending, top

  int _page = 1;
  final int _limit = 10;

  @override
  void onInit() {
    super.onInit();
    scrollController.addListener(_onScroll);
    fetchDiscoveryList(isRefresh: true);
  }

  @override
  void onClose() {
    scrollController.dispose();
    super.onClose();
  }

  void _onScroll() {
    if (scrollController.position.pixels >= scrollController.position.maxScrollExtent - 200) {
      fetchMoreDiscoveryList();
    }
  }

  // 切换过滤器
  void updateFilters({String? price, String? type, String? sort}) {
    if (price != null) selectedPrice.value = price;
    if (type != null) selectedType.value = type;
    if (sort != null) selectedSort.value = sort;
    fetchDiscoveryList(isRefresh: true);
  }

  // 切换分类药丸
  void updateCategory(String category) {
    selectedCategory.value = category;
    fetchDiscoveryList(isRefresh: true);
  }

  /// 🌟 统一分页异步网络拉取
  Future<void> fetchDiscoveryList({bool isRefresh = false}) async {
    if (isRefresh) {
      _page = 1;
      hasMore.value = true;
      isLoading.value = true;
    }

    try {
      final Map<String, dynamic> queryParams = {
        'category': selectedCategory.value,
        'page': _page,
        'limit': _limit,
        'sort': selectedSort.value,
      };

      if (selectedPrice.value != 'all') {
        queryParams['price'] = selectedPrice.value;
      }
      if (selectedType.value != 'all') {
        queryParams['type'] = selectedType.value;
      }

      final res = await HttpClient.instance.get<Map<String, dynamic>>(
        '/api-communities',
        queryParameters: queryParams,
      );

      if (res.respCode == 0 && res.datas != null) {
        final List<dynamic> list = res.datas!['communities'] as List? ?? [];
        final parsed = list.map((e) => CommunityModel.fromJson(e)).toList();

        if (isRefresh) {
          communities.assignAll(parsed);
        } else {
          communities.addAll(parsed);
        }

        isLoading.value = false;
        isLoadingMore.value = false;
        if (parsed.length < _limit) {
          hasMore.value = false;
        }
      }
    } catch (_) {
      isLoading.value = false;
      isLoadingMore.value = false;
    }
  }

  Future<void> fetchMoreDiscoveryList() async {
    if (isLoadingMore.value || !hasMore.value || isLoading.value) return;
    isLoadingMore.value = true;
    _page++;
    await fetchDiscoveryList(isRefresh: false);
  }

  /// 🌟 新增：向后端提交新建社群数据，并在成功时自动回显
  Future<bool> createCommunity(Map<String, dynamic> data) async {
    try {
      final res = await HttpClient.instance.post<Map<String, dynamic>>(
        '/api-communities',
        data: data,
      );
      if (res.respCode == 0) {
        Fluttertoast.showToast(msg: 'community_created'.tr);
        // 🌟 强力重洗列表，让最新创建的社群瞬间呈现在最顶部，完美回显！
        fetchDiscoveryList(isRefresh: true);
        return true;
      } else {
        Fluttertoast.showToast(msg: res.respMsg);
        return false;
      }
    } catch (e) {
      Fluttertoast.showToast(msg: 'community_create_error'.trParams({'error': '$e'}));
      return false;
    }
  }
}