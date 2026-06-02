import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'community_model.dart';
import 'community_space_controller.dart';
import '../post_detail/post_detail_view.dart';

class CommunitySpaceView extends StatelessWidget {
  final String communityId;
  const CommunitySpaceView({super.key, required this.communityId});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(CommunitySpaceController(communityId: communityId), tag: communityId);
    final themeColor = const Color.fromRGBO(44, 123, 109, 1.0);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Obx(() => Text(controller.community.value?.name ?? '社群加载中', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87))),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(onPressed: () => Get.back(), icon: const Icon(Icons.arrow_back, color: Colors.black)),
      ),
      body: Obx(() {
        if (controller.isLoadingDetails.value) {
          return Center(child: CircularProgressIndicator(color: themeColor, strokeWidth: 2));
        }

        final space = controller.community.value;
        if (space == null) {
          return const Center(child: Text('空间资源不存在'));
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
              tabs: const [
                Tab(text: '💬 Discussions / 讨论大厅'),
                Tab(text: 'ℹ️ About / 空间简介'),
              ],
            ),

            Expanded(
              child: TabBarView(
                controller: controller.tabController,
                children: [
                  // Tab 1: 讨论大厅（内置付费防火墙拦截）
                  _buildDiscussionsTab(context, controller, themeColor),

                  // Tab 2: 关于详情大卡
                  _buildAboutTab(space, themeColor),
                ],
              ),
            )
          ],
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
      // 🌟🌟 付费防火墙被拦截：展示高档玻璃质感锁定 Paywall [2]
      if (!controller.hasPostsPermission.value) {
        final space = controller.community.value!;
        return Container(
          color: Colors.grey.shade50,
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: themeColor.withOpacity(0.08), shape: BoxShape.circle),
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedLockPassword, // 大挂锁安全指示
                    color: themeColor,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '【${space.name}】是付费专享社群',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 8),
                Text(
                  '创作者已在云端部署了访问控制保护墙。\n点击下方按钮解锁，立即加入空间学习并查看全部 ${space.memberCount} 名群友发帖！',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 11, height: 1.5),
                ),
                const SizedBox(height: 24),
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
                    '立即支付 ¥${space.price.toStringAsFixed(2)} / 加入空间',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                  ),
                )
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
        return const Center(child: Text('当前群组内暂无学者发贴'));
      }

      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: controller.posts.length,
        itemBuilder: (context, index) {
          final post = controller.posts[index];
          final isPinned = post['is_pinned'] as bool? ?? false;
          final title = post['title']?.toString() ?? 'Saysay想法';
          final author = post['author'] ?? {};

          return Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade100)),
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              title: Row(
                children: [
                  if (isPinned) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(4)),
                      child: Text('📌 置顶', style: TextStyle(color: Colors.orange.shade800, fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Row(
                  children: [
                    CircleAvatar(radius: 8, backgroundImage: NetworkImage(author['avatar'] ?? '')),
                    const SizedBox(width: 6),
                    Text(author['nickname'] ?? '学者', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                    const Spacer(),
                    Text('点赞 ${post['likes']?.length ?? 0}', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                  ],
                ),
              ),
              onTap: () => Get.to(() => PostDetailView(postId: post['id'])),
            ),
          );
        },
      );
    });
  }

  Widget _buildAboutTab(CommunityModel space, Color themeColor) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('📖 空间介绍', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 10),
          Text(space.descShort, style: const TextStyle(color: Colors.black87, fontSize: 13, height: 1.5)),
          if (space.fullDesc.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(space.fullDesc, style: TextStyle(color: Colors.grey.shade600, fontSize: 12, height: 1.5)),
          ],
          if (space.links.isNotEmpty) ...[
            const Divider(height: 32),
            const Text('🌐 空间外链', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
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
                    Text(link['title'] ?? '链接', style: TextStyle(color: themeColor, fontSize: 13, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            )),
          ]
        ],
      ),
    );
  }
}