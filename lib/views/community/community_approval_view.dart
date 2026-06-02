import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'applicant_model.dart';
import 'community_approval_controller.dart';

class CommunityApprovalView extends StatelessWidget {
  final String communityId;
  const CommunityApprovalView({super.key, required this.communityId});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(CommunityApprovalController(communityId: communityId), tag: communityId);
    final themeColor = const Color.fromRGBO(44, 123, 109, 1.0);

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('成员加入审核中心', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Get.back(),
          icon: const Icon(Icons.arrow_back, color: Colors.black),
        ),
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return Center(child: CircularProgressIndicator(color: themeColor, strokeWidth: 2));
        }

        if (controller.applicants.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedCheckList,
                  color: themeColor.withOpacity(0.2),
                  size: 48,
                ),
                const SizedBox(height: 12),
                const Text("暂无待审核加入的成员申请", style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: controller.applicants.length,
          itemBuilder: (context, index) {
            final applicant = controller.applicants[index];
            return _buildApplicantCard(context, controller, applicant, themeColor);
          },
        );
      }),
    );
  }

  Widget _buildApplicantCard(
      BuildContext context,
      CommunityApprovalController controller,
      ApplicantModel applicant,
      Color themeColor,
      ) {
    final formattedTime = applicant.appliedAt.length > 16
        ? applicant.appliedAt.substring(0, 16).replaceAll('T', ' ')
        : applicant.appliedAt;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.01),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundImage: NetworkImage(applicant.avatar),
                backgroundColor: Colors.grey.shade100,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(applicant.nickname, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
                    const SizedBox(height: 2),
                    Text('申请时间: $formattedTime', style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _showRejectReasonDialog(context, controller, applicant.userId),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.red.shade100),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: Text('拒绝申请', style: TextStyle(color: Colors.red.shade400, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => controller.approveApplicant(applicant.userId),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: themeColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: const Text('同意加入', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  void _showRejectReasonDialog(BuildContext context, CommunityApprovalController controller, String applicantUserId) {
    final TextEditingController reasonC = TextEditingController(text: '不满足社群加入标准');

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('驳回申请', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          content: TextField(
            controller: reasonC,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              labelText: '请填写驳回原因 (系统将通过推送告知该学者)',
              labelStyle: TextStyle(fontSize: 11),
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                controller.rejectApplicant(applicantUserId, reasonC.text.trim());
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('确认拒绝', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }
}