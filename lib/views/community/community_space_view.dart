import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:qorange/theme.dart';
import '../../user_controller.dart';
import 'community_approval_view.dart';
import 'community_model.dart';
import 'community_space_controller.dart';
import '../post_detail/post_detail_view.dart';

class CommunitySpaceView extends StatelessWidget {
  final String communityId;
  const CommunitySpaceView({super.key, required this.communityId});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(CommunitySpaceController(communityId: communityId), tag: communityId);
    final themeColor = AppColors.primary;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Obx(() => Text(
          controller.community.value?.name ?? 'community_loading'.tr,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary),
        )),
        centerTitle: true,
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Get.back(),
          icon: const Icon(Icons.arrow_back, color: Colors.black),
        ),
      ),
      body: Obx(() {
        if (controller.isLoadingDetails.value) {
          return Center(child: CircularProgressIndicator(color: themeColor, strokeWidth: 2));
        }

        final space = controller.community.value;
        if (space == null) {
          return Center(child: Text('space_not_found'.tr));
        }

        return Column(
          children: [
            // 空间 Banner
            _buildSpaceBanner(space, themeColor),

            // 空间主 Tab (Discussions, About)
            TabBar(
              controller: controller.tabController,
              indicatorColor: themeColor,
              labelColor: themeColor,
              unselectedLabelColor: Colors.grey,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              tabs: [
                Tab(text: '💬 ${'saysay_hall'.tr}'),
                Tab(text: 'ℹ️ ${'community_space'.tr}'),
              ],
            ),

            Expanded(
              child: TabBarView(
                controller: controller.tabController,
                children: [
                  // Tab 1: 讨论大厅（内置付费/私密防火墙拦截、高维卡片、置顶管控）
                  _buildDiscussionsTab(context, controller, themeColor),

                  // Tab 2: 关于详情大卡
                  _buildAboutTab(
                    space,
                    themeColor,
                    controller,
                  ),
                ],
              ),
            )
          ],
        );
      }),
      // 🌟 核心设计：仅在拥有群组权限且当前 Tab 为讨论大厅时才显示发帖 FloatingActionButton
      floatingActionButton: Obx(() {
        final hasPermission = controller.hasPostsPermission.value;
        final isDetailLoading = controller.isLoadingDetails.value;

        if (isDetailLoading || !hasPermission) return const SizedBox.shrink();

        return FloatingActionButton(
          onPressed: () => _showPublishInSpaceSheet(context, controller, themeColor),
          backgroundColor: themeColor,
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: const HugeIcon(
            icon: HugeIcons.strokeRoundedQuillWrite02,
            color: Colors.white,
            size: 24.0,
          ),
        );
      }),
    );
  }

  Widget _buildSpaceBanner(CommunityModel space, Color themeColor) {
    return Container(
      width: double.infinity,
      height: 150,
      decoration: BoxDecoration(
        color: themeColor.withOpacity(0.05),
      ),
      child: space.bannerUrl.isNotEmpty
          ? Image.network(space.bannerUrl, fit: BoxFit.cover)
          : Center(child: HugeIcon(icon: HugeIcons.strokeRoundedUserGroup, color: themeColor.withOpacity(0.2), size: 50)),
    );
  }

  Widget _buildDiscussionsTab(BuildContext context, CommunitySpaceController controller, Color themeColor) {
    return Obx(() {
      // 🌟🌟 核心安全修正：付费/私密社群大屏障拦截 Paywall 🌟🌟
      if (!controller.hasPostsPermission.value) {
        final space = controller.community.value!;
        final String status = controller.memberStatus.value; // none, applying, approved_to_pay

        return Container(
          color: AppColors.surfaceAlt,
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: themeColor.withOpacity(0.08), shape: BoxShape.circle),
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedLockPassword,
                    color: themeColor,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  space.price > 0.0
                      ? 'space_is_paid'.trParams({'name': space.name})
                      : 'space_is_private'.trParams({'name': space.name}),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 8),
                Text(
                  space.price > 0.0
                      ? 'space_paid_desc'.trParams({'count': '${space.memberCount}'})
                      : 'space_private_desc'.tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11, height: 1.5),
                ),
                const SizedBox(height: 24),

                // 🌟🌟 动态审批流按钮多维拦截回显（分流免费/付费，支持审核中置灰置禁用） 🌟🌟
                if (status == 'applying') ...[
                  // 情况 A：审核中，置灰不可点按，防刷
                  ElevatedButton.icon(
                    onPressed: null, // 置灰禁用
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.border,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.hourglass_empty_rounded, color: Colors.grey, size: 16),
                    label: Text(
                      'application_pending'.tr,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey),
                    ),
                  )
                ] else if (status == 'approved_to_pay' || (status == 'none' && space.price > 0.0 && space.type == 'public')) ...[
                  // 情况 B：审核通过待付款，或者原本就是公开付费群 -> 引导调用支付收银台付款
                  ElevatedButton.icon(
                    onPressed: () => controller.purchaseJoinWorkflow(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: themeColor,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.shopping_bag_outlined, color: Colors.white, size: 16),
                    label: Text(
                      status == 'approved_to_pay'
                          ? 'approved_pay_to_join'.trParams({'price': space.price.toStringAsFixed(2)})
                          : 'pay_to_join_now'.trParams({'price': space.price.toStringAsFixed(2)}),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                    ),
                  )
                ] else ...[
                  // 情况 C：初始状态，且属于免费私密群，引导其提交 apply 申请表单给群主
                  ElevatedButton.icon(
                    onPressed: () => controller.applyToJoinCommunity(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: themeColor,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.add_task_rounded, color: Colors.white, size: 16),
                    label: Text(
                      'apply_join_private_space'.tr,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                    ),
                  )
                ]
              ],
            ),
          ),
        );
      }

      // 已加入/已付费用户：渲染帖子列表
      if (controller.isLoadingPosts.value) {
        return Center(child: CircularProgressIndicator(color: themeColor, strokeWidth: 2));
      }

      if (controller.posts.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              HugeIcon(icon: HugeIcons.strokeRoundedMessage01, color: AppColors.border, size: 48),
              const SizedBox(height: 12),
              Text('space_empty_post_first'.tr, style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        );
      }

      final isMeCreator = controller.community.value?.creatorId == UserController.to.user.value?.id;

      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: controller.posts.length,
        itemBuilder: (context, index) {
          final post = controller.posts[index];
          final String postId = post['id']?.toString() ?? '';
          final bool isPinned = post['is_pinned'] as bool? ?? false;
          final String title = post['title']?.toString() ?? 'default_post_title'.tr;
          final author = post['author'] ?? {};
          final timestamp = post['created_at'] != null ? post['created_at'].toString().substring(0, 10) : '';

          // 🌟 物理安全解析：提取富文本正文中的极简文本快照供 lobby 页面直接阅读
          String contentPreview = 'no_paragraph_content'.tr;
          try {
            final dynamic content = post['content'];
            if (content != null) {
              final parsed = jsonDecode(content.toString());
              if (parsed is List) {
                contentPreview = parsed.map((op) => op['insert']?.toString() ?? '').join().trim();
              } else {
                contentPreview = content.toString();
              }
            }
          } catch (_) {
            contentPreview = post['content']?.toString() ?? 'no_paragraph_content'.tr;
          }
          if (contentPreview.length > 60) {
            contentPreview = '${contentPreview.substring(0, 60)}...';
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.01),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Get.to(() => PostDetailView(postId: postId)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 头衔行
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundImage: NetworkImage(author['avatar'] ?? ''),
                            backgroundColor: AppColors.divider,
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(author['nickname'] ?? 'scholar'.tr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              const SizedBox(height: 2),
                              Text(timestamp, style: TextStyle(fontSize: 9, color: AppColors.textHint)),
                            ],
                          ),
                          const Spacer(),

                          // 🌟 如果是置顶帖，展示橙色置顶小角标
                          if (isPinned)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(6)),
                              child: Text('pinned_badge'.tr, style: TextStyle(color: Colors.orange.shade800, fontSize: 9, fontWeight: FontWeight.bold)),
                            ),

                          // 🌟 如果当前用户是群主，展示群主特权管理入口点
                          if (isMeCreator)
                            IconButton(
                              onPressed: () => _showAdminManageMenu(context, controller, postId, isPinned),
                              icon: const Icon(Icons.more_vert_rounded, color: Colors.grey, size: 18),
                              constraints: const BoxConstraints(),
                              padding: EdgeInsets.zero,
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // 标题
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 6),

                      // 正文快照
                      Text(
                        contentPreview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4),
                      ),
                      const Divider(height: 24),

                      // 底部互动行
                      Row(
                        children: [
                          HugeIcon(icon: HugeIcons.strokeRoundedFavourite, color: AppColors.textHint, size: 14),
                          const SizedBox(width: 4),
                          Text('${post['likes']?.length ?? 0}', style: TextStyle(fontSize: 10, color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 16),
                          HugeIcon(icon: HugeIcons.strokeRoundedComment01, color: AppColors.textHint, size: 14),
                          const SizedBox(width: 4),
                          Text('insightful_replies'.tr, style: TextStyle(fontSize: 10, color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    });
  }

  Widget _buildAboutTab(
      CommunityModel space,
      Color themeColor,
      CommunitySpaceController controller,
      ) {
    // 🌟 判断当前用户是否是群主
    final isMeCreator = space.creatorId == UserController.to.user.value?.id;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🌟🌟 新增群主特权管理入口（含红点回显） 🌟🌟
          if (isMeCreator) ...[
            Obx(() {
              final count = controller.pendingApprovalsCount.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.divider, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.01),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                child: ListTile(
                  leading: HugeIcon(
                    icon: HugeIcons.strokeRoundedCheckList, // 审批大清单 Icon
                    color: Colors.orangeAccent,
                    size: 20.0,
                  ),
                  title: Text('member_approval_center'.tr, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                  subtitle: Text(count > 0 ? 'pending_approvals_count'.trParams({'count': '$count'}) : 'no_pending_members'.tr, style: const TextStyle(fontSize: 11)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 🌟 小红点核心渲染：如果有等候审核人数，展示红色气泡
                      if (count > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                          child: Text(
                            '$count',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      const SizedBox(width: 8),
                      const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                    ],
                  ),
                  onTap: () => Get.to(() => CommunityApprovalView(communityId: communityId)),
                ),
              );
            }),
          ],

          Text('space_intro'.tr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 10),
          Text(space.descShort, style: TextStyle(color: AppColors.textPrimary, fontSize: 13, height: 1.5)),
          if (space.fullDesc.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(space.fullDesc, style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.5)),
          ],
          if (space.links.isNotEmpty) ...[
            const Divider(height: 32),
            Text('space_links'.tr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 10),
            ...space.links.map((link) => Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: InkWell(
                onTap: () async {
                  final url = Uri.parse(link['url'] ?? '');
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
                child: Row(
                  children: [
                    HugeIcon(icon: HugeIcons.strokeRoundedGlobal, color: themeColor, size: 16),
                    const SizedBox(width: 8),
                    Text(link['title'] ?? 'link'.tr, style: TextStyle(color: themeColor, fontSize: 13, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            )),
          ]
        ],
      ),
    );
  }

  /// 🌟 创作者群主特权一键修改/置顶/下架菜单
  void _showAdminManageMenu(BuildContext context, CommunitySpaceController controller, String postId, bool isPinned) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 20),
              Text('manage_community_post'.tr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 20),
              ListTile(
                leading: HugeIcon(
                    icon: HugeIcons.strokeRoundedPin,
                    color: isPinned ? Colors.grey : Colors.orange,
                    size: 20.0
                ),
                title: Text(isPinned ? 'unpin_globally'.tr : 'pin_to_top'.tr, style: const TextStyle(fontSize: 14)),
                onTap: () {
                  Navigator.pop(context);
                  controller.togglePinPost(postId, isPinned);
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const HugeIcon(icon: HugeIcons.strokeRoundedDelete02, color: Colors.redAccent, size: 20.0),
                title: Text('delete_post_permanently'.tr, style: const TextStyle(fontSize: 14, color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(context);
                  controller.deletePostByAdmin(postId);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// 🌟 调起极简高能社群内容发布面板
  void _showPublishInSpaceSheet(BuildContext context, CommunitySpaceController controller, Color themeColor) {
    final TextEditingController titleC = TextEditingController();
    final TextEditingController contentC = TextEditingController();
    bool isPinnedSelected = false;
    final bool isMeCreator = controller.community.value?.creatorId == UserController.to.user.value?.id;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              decoration: BoxDecoration(color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.only(
                top: 20,
                left: 24,
                right: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 30, // 键盘避让
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('share_my_thoughts'.tr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                      )
                    ],
                  ),
                  const SizedBox(height: 20),

                  // 标题
                  TextField(
                    controller: titleC,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'share_title_hint'.tr,
                      hintStyle: TextStyle(color: AppColors.textHint, fontSize: 13),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 内容主体
                  TextField(
                    controller: contentC,
                    maxLines: 5,
                    style: const TextStyle(fontSize: 14, height: 1.4),
                    decoration: InputDecoration(
                      hintText: 'share_content_hint'.tr,
                      hintStyle: TextStyle(color: AppColors.textHint, fontSize: 13),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 🌟 如果是群主，允许勾选发布时是否一键置顶本群组大厅
                  if (isMeCreator)
                    CheckboxListTile(
                      value: isPinnedSelected,
                      onChanged: (val) => setModalState(() => isPinnedSelected = val ?? false),
                      title: Text('pin_to_group_top'.tr, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      activeColor: themeColor,
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),

                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () async {
                        final titleText = titleC.text.trim();
                        final contentText = contentC.text.trim();

                        if (titleText.isEmpty || contentText.isEmpty) {
                          Fluttertoast.showToast(msg: 'fill_title_and_content'.tr);
                          return;
                        }

                        final success = await controller.publishPostInCommunity(
                          title: titleText,
                          content: contentText,
                          isPinned: isPinnedSelected,
                        );

                        if (success) {
                          Navigator.pop(context); // 关闭输入面
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: themeColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: Text('publish_to_community'.tr, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }
}