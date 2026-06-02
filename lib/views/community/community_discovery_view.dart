import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:image_picker/image_picker.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../services/api_service.dart';
import '../../user_controller.dart';
import 'community_discovery_controller.dart';
import 'community_model.dart';
import 'community_space_view.dart';

class CommunityDiscoveryView extends StatelessWidget {
  const CommunityDiscoveryView({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(CommunityDiscoveryController());
    final themeColor = const Color.fromRGBO(44, 123, 109, 1.0);

    // 目标领域映射中文
    final List<Map<String, String>> categories = [
      {'key': 'trending', 'name': '🔥 Trending', 'emoji': '🔥'},
      {'key': 'music', 'name': '🎸 Music', 'emoji': '🎸'},
      {'key': 'money', 'name': '💰 Money', 'emoji': '💰'},
      {'key': 'tech', 'name': '💻 Tech', 'emoji': '💻'},
      {'key': 'health', 'name': '🥕 Health', 'emoji': '🥕'},
      {'key': 'sports', 'name': '⚽ Sports', 'emoji': '⚽'},
      {'key': 'style', 'name': '🎨 Style', 'emoji': '🎨'},
    ];

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('发现高能社群', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        // 🌟 新增：左侧AppBar新建社群入口
        leading: IconButton(
          onPressed: () => _showCreateCommunitySheet(context, controller, themeColor, categories),
          icon: HugeIcon(
            icon: HugeIcons.strokeRoundedPlusSignSquare,
            color: themeColor,
            size: 22.0,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () => _showFilterBottomSheet(context, controller, themeColor),
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedFilter,
              color: themeColor,
              size: 22.0,
            ),
          )
        ],
      ),
      body: Column(
        children: [
          // 顶部水平滑动的分类药丸
          Container(
            height: 54,
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final cat = categories[index];
                return Obx(() {
                  final isSelected = controller.selectedCategory.value == cat['key'];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => controller.updateCategory(cat['key']!),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected ? themeColor : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          cat['name']!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.white : Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ),
                  );
                });
              },
            ),
          ),
          // 社群卡片流
          Expanded(
            child: Obx(() {
              if (controller.isLoading.value) {
                return Center(child: CircularProgressIndicator(color: themeColor, strokeWidth: 2));
              }
              if (controller.communities.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      HugeIcon(icon: HugeIcons.strokeRoundedUserGroup, color: Colors.grey.shade300, size: 48),
                      const SizedBox(height: 12),
                      const Text("没有找到符合条件的社群", style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () => controller.fetchDiscoveryList(isRefresh: true),
                color: themeColor,
                child: ListView.builder(
                  controller: controller.scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: controller.communities.length + 1,
                  itemBuilder: (context, index) {
                    if (index == controller.communities.length) {
                      return Obx(() => controller.isLoadingMore.value
                          ? Center(child: Padding(padding: const EdgeInsets.all(16), child: CircularProgressIndicator(color: themeColor, strokeWidth: 2)))
                          : const SizedBox.shrink());
                    }

                    final item = controller.communities[index];
                    return _buildCommunityCard(context, item, themeColor);
                  },
                ),
              );
            }),
          )
        ],
      ),
    );
  }

  Widget _buildCommunityCard(BuildContext context, CommunityModel item, Color themeColor) {
    return GestureDetector(
      onTap: () => Get.to(() => CommunitySpaceView(communityId: item.id)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade100, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🌟 修复：直接使用标准 ClipRRect 替换 SRect 依赖，防止报错
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              child: item.bannerUrl.isNotEmpty
                  ? Image.network(item.bannerUrl, height: 140, width: double.infinity, fit: BoxFit.cover)
                  : Container(
                height: 140,
                width: double.infinity,
                color: themeColor.withOpacity(0.05),
                child: Center(
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedUserGroup,
                    color: themeColor.withOpacity(0.2),
                    size: 48,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: item.price > 0.0 ? Colors.orange.shade50 : Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          item.price > 0.0 ? '¥${item.price.toStringAsFixed(2)} / ${item.billingCycle == 'month' ? '月' : '年'}' : '免费加入',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: item.price > 0.0 ? Colors.orange.shade800 : Colors.green.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(item.descShort, style: TextStyle(color: Colors.grey.shade500, fontSize: 12, height: 1.4)),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      HugeIcon(icon: HugeIcons.strokeRoundedUserGroup, color: Colors.grey.shade400, size: 14),
                      const SizedBox(width: 6),
                      Text('${item.memberCount} 成员', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                      const Spacer(),
                      if (item.isJoined)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
                          child: const Text('已加入空间', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(color: themeColor, borderRadius: BorderRadius.circular(12)),
                          child: const Text('加入社群', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                        ),
                    ],
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  void _showFilterBottomSheet(BuildContext context, CommunityDiscoveryController controller, Color themeColor) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('高级筛选', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 20),
              // 价格大项过滤
              const Text('价格类型', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 10),
              Obx(() => Row(
                children: [
                  _buildChoiceChip(
                    text: '全部',
                    isSelected: controller.selectedPrice.value == 'all',
                    onTap: () => controller.updateFilters(price: 'all'),
                    themeColor: themeColor,
                  ),
                  const SizedBox(width: 8),
                  _buildChoiceChip(
                    text: '免费',
                    isSelected: controller.selectedPrice.value == 'free',
                    onTap: () => controller.updateFilters(price: 'free'),
                    themeColor: themeColor,
                  ),
                  const SizedBox(width: 8),
                  _buildChoiceChip(
                    text: '付费订阅',
                    isSelected: controller.selectedPrice.value == 'paid',
                    onTap: () => controller.updateFilters(price: 'paid'),
                    themeColor: themeColor,
                  ),
                ],
              )),
              const SizedBox(height: 20),
              // 社群属性过滤
              const Text('社群属性', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 10),
              Obx(() => Row(
                children: [
                  _buildChoiceChip(
                    text: '全部',
                    isSelected: controller.selectedType.value == 'all',
                    onTap: () => controller.updateFilters(type: 'all'),
                    themeColor: themeColor,
                  ),
                  const SizedBox(width: 8),
                  _buildChoiceChip(
                    text: '公开加入',
                    isSelected: controller.selectedType.value == 'public',
                    onTap: () => controller.updateFilters(type: 'public'),
                    themeColor: themeColor,
                  ),
                  const SizedBox(width: 8),
                  _buildChoiceChip(
                    text: '私密群组',
                    isSelected: controller.selectedType.value == 'private',
                    onTap: () => controller.updateFilters(type: 'private'),
                    themeColor: themeColor,
                  ),
                ],
              )),
              const SizedBox(height: 20),
              // 排序方式过滤
              const Text('排序规则', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 10),
              Obx(() => Row(
                children: [
                  _buildChoiceChip(
                    text: '热门趋势',
                    isSelected: controller.selectedSort.value == 'trending',
                    onTap: () => controller.updateFilters(sort: 'trending'),
                    themeColor: themeColor,
                  ),
                  const SizedBox(width: 8),
                  _buildChoiceChip(
                    text: '群员最多',
                    isSelected: controller.selectedSort.value == 'top',
                    onTap: () => controller.updateFilters(sort: 'top'),
                    themeColor: themeColor,
                  ),
                ],
              )),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: themeColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: const Text('应用筛选指标', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              )
            ],
          ),
        );
      },
    );
  }

  Widget _buildChoiceChip({required String text, required bool isSelected, required VoidCallback onTap, required Color themeColor}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? themeColor : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? themeColor : Colors.transparent, width: 1),
        ),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.black87)),
      ),
    );
  }

  /// 🌟 新增：模态滑出新建高颜值社群面板（包含封面异步上传与回显）
  void _showCreateCommunitySheet(
      BuildContext context,
      CommunityDiscoveryController controller,
      Color themeColor,
      List<Map<String, String>> categoriesList,
      ) {
    if (!UserController.to.isLoggedIn) {
      Fluttertoast.showToast(msg: "请登录后创建社群");
      return;
    }
    final TextEditingController nameC = TextEditingController();
    final TextEditingController descC = TextEditingController();
    final TextEditingController priceC = TextEditingController();

    String selectedCategory = 'music';
    String selectedType = 'public'; // public, private
    String billingCycle = 'month';  // month, year
    String bannerUrl = '';
    bool isUploading = false;

    // 排除 trending 大项，仅保留真实业务分类
    final realCategories = categoriesList.where((e) => e['key'] != 'trending').toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            // 🌟 核心：客户端调用相册并直连上传
            Future<void> pickBannerImage() async {
              final picker = ImagePicker();
              final xFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
              if (xFile == null) return;

              setModalState(() => isUploading = true);
              Fluttertoast.showToast(msg: "正在上传封面背景...");

              try {
                final url = await ApiService.uploadImage(File(xFile.path));
                if (url != null) {
                  setModalState(() {
                    bannerUrl = url;
                    isUploading = false;
                  });
                  Fluttertoast.showToast(msg: "封面图片上传成功！");
                } else {
                  setModalState(() => isUploading = false);
                  Fluttertoast.showToast(msg: "封面上传失败");
                }
              } catch (_) {
                setModalState(() => isUploading = false);
              }
            }

            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.only(
                top: 20,
                left: 24,
                right: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 30, // 键盘避让
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text('开启我的社群圈子', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 20),

                    // 封面上传交互卡片
                    GestureDetector(
                      onTap: isUploading ? null : pickBannerImage,
                      child: Container(
                        width: double.infinity,
                        height: 120,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                          image: bannerUrl.isNotEmpty
                              ? DecorationImage(image: NetworkImage(bannerUrl), fit: BoxFit.cover)
                              : null,
                        ),
                        child: bannerUrl.isNotEmpty
                            ? const SizedBox.shrink()
                            : Center(
                          child: isUploading
                              ? CircularProgressIndicator(color: themeColor, strokeWidth: 2)
                              : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              HugeIcon(icon: HugeIcons.strokeRoundedImage01, color: themeColor, size: 24.0),
                              const SizedBox(height: 8),
                              const Text('点击上传社群封面背景图', style: TextStyle(fontSize: 11, color: Colors.grey)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 社群名称
                    TextField(
                      controller: nameC,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: "为您的社群取一个响亮的名字...",
                        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                        prefixIcon: const Icon(Icons.drive_file_rename_outline, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 简短描述
                    TextField(
                      controller: descC,
                      style: const TextStyle(fontSize: 14),
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: "简短介绍社群的主题与核心价值...",
                        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                        prefixIcon: const Icon(Icons.text_fields_outlined, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 类别选择大片
                    const Text('选择所属兴趣领域', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: realCategories.map((cat) {
                        final isSelected = selectedCategory == cat['key'];
                        return GestureDetector(
                          onTap: () => setModalState(() => selectedCategory = cat['key']!),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: isSelected ? themeColor : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              cat['name']!,
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.black87),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),

                    // 社群属性
                    Row(
                      children: [
                        const Text('公开属性：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                        const SizedBox(width: 8),
                        _buildChoiceChip(
                          text: '公开加入',
                          isSelected: selectedType == 'public',
                          onTap: () => setModalState(() => selectedType = 'public'),
                          themeColor: themeColor,
                        ),
                        const SizedBox(width: 8),
                        _buildChoiceChip(
                          text: '私密同意申请',
                          isSelected: selectedType == 'private',
                          onTap: () => setModalState(() => selectedType = 'private'),
                          themeColor: themeColor,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // 价格设置
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: priceC,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: const TextStyle(fontSize: 14),
                            decoration: InputDecoration(
                              hintText: "订阅价格 (0代表免费)",
                              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                              prefixIcon: const Icon(Icons.attach_money, size: 18),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        _buildChoiceChip(
                          text: '按月收',
                          isSelected: billingCycle == 'month',
                          onTap: () => setModalState(() => billingCycle = 'month'),
                          themeColor: themeColor,
                        ),
                        const SizedBox(width: 8),
                        _buildChoiceChip(
                          text: '按年收',
                          isSelected: billingCycle == 'year',
                          onTap: () => setModalState(() => billingCycle = 'year'),
                          themeColor: themeColor,
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),

                    // 立即创建
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () async {
                          final name = nameC.text.trim();
                          final desc = descC.text.trim();
                          final price = priceC.text.trim();

                          if (name.isEmpty) {
                            Fluttertoast.showToast(msg: "请填写社群名称");
                            return;
                          }

                          // 组合参数提交
                          final success = await controller.createCommunity({
                            'name': name,
                            'desc_short': desc,
                            'category': selectedCategory,
                            'type': selectedType,
                            'price': price.isEmpty ? "0.00" : price,
                            'billing_cycle': billingCycle,
                            'banner_url': bannerUrl,
                          });

                          if (success) {
                            Navigator.pop(context); // 关闭面板
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: themeColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: const Text('立即创建社群空间', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}