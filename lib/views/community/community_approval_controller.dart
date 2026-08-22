import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:qorange/theme.dart';
import '../../network/http_client.dart';
import 'applicant_model.dart';
import 'community_space_controller.dart'; // 🌟 用于联动更新小红点

class CommunityApprovalController extends GetxController {
  final String communityId;
  CommunityApprovalController({required this.communityId});

  final RxList<ApplicantModel> applicants = <ApplicantModel>[].obs;
  final RxBool isLoading = true.obs;

  Color get primaryColor => AppColors.primary;

  @override
  void onInit() {
    super.onInit();
    loadApplicants();
  }

  /// 加载待审核清单
  Future<void> loadApplicants() async {
    isLoading.value = true;
    try {
      final res = await HttpClient.instance.get<List<dynamic>>('/api-communities/$communityId/applicants');
      if (res.respCode == 0 && res.datas != null) {
        final List<dynamic> list = res.datas!;
        applicants.assignAll(list.map((e) => ApplicantModel.fromJson(e)).toList());
      }
    } catch (_) {
      isLoading.value = false;
    } finally {
      isLoading.value = false;
    }
  }

  /// 🌟 批准通过申请加入
  Future<void> approveApplicant(String applicantUserId) async {
    Get.dialog(
      Center(child: CircularProgressIndicator(color: AppColors.primary)),
      barrierDismissible: false,
    );

    try {
      final res = await HttpClient.instance.post<Map<String, dynamic>>(
        '/api-communities/$communityId/approve',
        data: {
          'userId': applicantUserId,
          'action': 'approve',
          'reason': 'approve_reason_default'.tr,
        },
      );

      Get.back(); // 关掉加载狂

      if (res.respCode == 0) {
        Fluttertoast.showToast(msg: 'approve_success'.tr);

        // 🌟 核心：从本地 Observable 列表中移除该成员，无缝淡出回显
        applicants.removeWhere((element) => element.userId == applicantUserId);

        // 🌟 核心：通知空间主控制器，同步扣减并更新小红点气泡
        _syncPendingCountToSpaceHeader();
      } else {
        Fluttertoast.showToast(msg: res.respMsg);
      }
    } catch (e) {
      Get.back();
      Fluttertoast.showToast(msg: 'approve_network_error'.trParams({'error': '$e'}));
    }
  }

  /// 🌟 拒绝/驳回学者加入申请
  Future<void> rejectApplicant(String applicantUserId, String reason) async {
    Get.dialog(
      Center(child: CircularProgressIndicator(color: AppColors.primary)),
      barrierDismissible: false,
    );

    try {
      final res = await HttpClient.instance.post<Map<String, dynamic>>(
        '/api-communities/$communityId/approve',
        data: {
          'userId': applicantUserId,
          'action': 'reject',
          'reason': reason,
        },
      );

      Get.back();

      if (res.respCode == 0) {
        Fluttertoast.showToast(msg: 'reject_success'.tr);
        applicants.removeWhere((element) => element.userId == applicantUserId);
        _syncPendingCountToSpaceHeader();
      } else {
        Fluttertoast.showToast(msg: res.respMsg);
      }
    } catch (e) {
      Get.back();
      Fluttertoast.showToast(msg: 'approve_network_error'.trParams({'error': '$e'}));
    }
  }

  /// 🌟 联动刷新空间大厅的小红点徽章
  void _syncPendingCountToSpaceHeader() {
    try {
      final spaceController = Get.find<CommunitySpaceController>(tag: communityId);
      spaceController.pendingApprovalsCount.value = applicants.length;
    } catch (_) {
      // 防止控制器销毁引发冲突
    }
  }
}