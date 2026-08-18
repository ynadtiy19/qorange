// lib/views/community/community_discovery_controller.dart
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import '../../network/http_client.dart';
import '../../user_controller.dart';
import 'community_model.dart';

class CommunityDiscoveryController extends GetxController {
  static CommunityDiscoveryController get to => Get.find<CommunityDiscoveryController>();

  final RxList<CommunityModel> communities = <CommunityModel>[].obs;
  final RxBool isLoading = true.obs;
  final RxBool isLoadingMore = false.obs;
  final RxBool hasMore = true.obs;

  final RxString selectedCategory = 'trending'.obs;
  final RxString selectedPrice = 'all'.obs;
  final RxString selectedType = 'all'.obs;
  final RxString selectedSort = 'trending'.obs;

  int _page = 1;
  final int _limit = 10;
  bool _isFetching = false;

  Worker? _userStateWorker;
  Worker? _globalSyncWorker;

  @override
  void onInit() {
    super.onInit();

    // 🌟 1. 监听用户状态变动（切号后强制重刷第 1 个 Tab 发现流）
    _userStateWorker = ever(UserController.to.user, (_) {
      fetchDiscoveryList(isRefresh: true);
    });

    // 🌟 2. 监听跨页全局同步信号（购买、加群、审批通过后即时全量同步）
    _globalSyncWorker = ever(globalDataSyncSignal, (_) {
      fetchDiscoveryList(isRefresh: true);
    });

    fetchDiscoveryList(isRefresh: true);
  }

  @override
  void onClose() {
    _userStateWorker?.dispose();
    _globalSyncWorker?.dispose();
    super.onClose();
  }

  void updateFilters({String? price, String? type, String? sort}) {
    if (price != null) selectedPrice.value = price;
    if (type != null) selectedType.value = type;
    if (sort != null) selectedSort.value = sort;
    fetchDiscoveryList(isRefresh: true);
  }

  void updateCategory(String category) {
    selectedCategory.value = category;
    fetchDiscoveryList(isRefresh: true);
  }

  Future<void> fetchDiscoveryList({bool isRefresh = false}) async {
    if (isRefresh) {
      _page = 1;
      hasMore.value = true;
      isLoading.value = true;
    }

    _isFetching = true;

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

        // 🌟 核心强制重绘：通知所有卡片即时刷新 isJoined 与群成员状态
        communities.refresh();

        isLoading.value = false;
        isLoadingMore.value = false;
        if (parsed.length < _limit) {
          hasMore.value = false;
        }
      }
    } catch (_) {
      isLoading.value = false;
      isLoadingMore.value = false;
    } finally {
      _isFetching = false;
    }
  }

  Future<void> fetchMoreDiscoveryList() async {
    if (isLoadingMore.value || !hasMore.value || isLoading.value || _isFetching) return;
    isLoadingMore.value = true;
    _page++;
    await fetchDiscoveryList(isRefresh: false);
  }

  Future<bool> createCommunity(Map<String, dynamic> data) async {
    try {
      final res = await HttpClient.instance.post<Map<String, dynamic>>(
        '/api-communities',
        data: data,
      );
      if (res.respCode == 0) {
        Fluttertoast.showToast(msg: 'community_created'.tr);
        fetchDiscoveryList(isRefresh: true);
        triggerGlobalDataSync(); // 🌟 广播同步商店与首页
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