import 'package:get/get.dart';
import '../network/secure_storage_manager.dart';

/// 🌟 全局跨页面数据同步广播信号（首页、社群、商店、个人中心全局联动）
final RxInt globalDataSyncSignal = 0.obs;

/// 触发全局页面静默重载（在购买成功、点赞、加群、切用户后调用）
void triggerGlobalDataSync() {
  globalDataSyncSignal.value++;
}

class UserModel {
  final String id;
  final String nickname;
  final String avatar;
  final String? phone;
  final String? bio;
  final String? location;
  final String? website;
  final List<String> topics;

  UserModel({
    required this.id,
    required this.nickname,
    required this.avatar,
    this.phone,
    this.bio,
    this.location,
    this.website,
    required this.topics,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
      nickname: json['nickname']?.toString() ?? '未设置昵称',
      avatar: json['avatar']?.toString() ?? '',
      phone: json['phone']?.toString(),
      bio: json['bio']?.toString() ?? '',
      location: json['location']?.toString() ?? '',
      website: json['website']?.toString() ?? '',
      topics: List<String>.from(json['topics'] ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nickname': nickname,
      'avatar': avatar,
      'phone': phone,
      'bio': bio,
      'location': location,
      'website': website,
      'topics': topics,
    };
  }
}

class UserController extends GetxController {
  static UserController get to => Get.find<UserController>();

  final Rxn<UserModel> user = Rxn<UserModel>();

  bool get isLoggedIn => user.value != null;

  @override
  void onInit() {
    super.onInit();
    _loadUserFromLocal();
  }

  Future<void> _loadUserFromLocal() async {
    final cachedId = await SecureStorageManager.instance.getString('user_id');
    final cachedNickname = await SecureStorageManager.instance.getString('user_nickname');
    final cachedAvatar = await SecureStorageManager.instance.getString('user_avatar');

    if (cachedId != null && cachedId.isNotEmpty) {
      user.value = UserModel(
        id: cachedId,
        nickname: cachedNickname ?? '用户',
        avatar: cachedAvatar ?? '',
        topics: [],
      );
      triggerGlobalDataSync();
    }
  }

  Future<void> saveUserInfo(Map<String, dynamic> rawData) async {
    final userData = rawData['user'] ?? rawData;
    final parsedUser = UserModel.fromJson(userData);
    user.value = parsedUser;

    await SecureStorageManager.instance.saveString('user_id', parsedUser.id);
    await SecureStorageManager.instance.saveString('user_nickname', parsedUser.nickname);
    await SecureStorageManager.instance.saveString('user_avatar', parsedUser.avatar);

    // 🌟 登录成功：立即广播通知首页、社群、商店等第一个 Tab 刷新
    triggerGlobalDataSync();
  }

  Future<void> clearUserInfo() async {
    user.value = null;
    await SecureStorageManager.instance.delete('user_id');
    await SecureStorageManager.instance.delete('user_nickname');
    await SecureStorageManager.instance.delete('user_avatar');

    // 🌟 退出登录：立即广播重置全页面状态
    triggerGlobalDataSync();
  }
}