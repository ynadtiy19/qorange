// lib/views/community/community_discovery_view.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qorange/theme.dart';
import '../../services/api_service.dart';
import '../../user_controller.dart';
import 'community_discovery_controller.dart';
import 'community_model.dart';
import 'community_space_view.dart';

class CommunityDiscoveryView extends StatelessWidget {
  const CommunityDiscoveryView({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.isRegistered<CommunityDiscoveryController>()
        ? Get.find<CommunityDiscoveryController>()
        : Get.put(CommunityDiscoveryController());

    final themeColor = AppColors.primary;

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
      backgroundColor: AppColors.surfaceAlt,
      appBar: AppBar(
        title: Text(
          'discover_communities'.tr,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black),
        ),
        centerTitle: true,
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          onPressed: () => _showCreateCommunitySheet(context, controller, themeColor, categories),
          icon: const HugeIcon(
            icon: HugeIcons.strokeRoundedPlusSignSquare,
            color: themeColor,
            size: 22.0,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () => _showFilterBottomSheet(context, controller, themeColor),
            icon: const HugeIcon(
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
            color: AppColors.surface,
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
                          color: isSelected ? themeColor : AppColors.divider,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          cat['name']!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.white : AppColors.textSecondary,
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
                return const Center(child: CircularProgressIndicator(color: themeColor, strokeWidth: 2));
              }
              if (controller.communities.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      HugeIcon(icon: HugeIcons.strokeRoundedUserGroup, color: AppColors.border, size: 48),
                      const SizedBox(height: 12),
                      Text("no_matching_communities".tr, style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () => controller.fetchDiscoveryList(isRefresh: true),
                color: themeColor,
                // 🌟 使用 NotificationListener 监听触底分页，完美避开 ScrollController 生命周期冲突
                child: NotificationListener<ScrollNotification>(
                  onNotification: (ScrollNotification scrollInfo) {
                    if (scrollInfo.metrics.pixels >= scrollInfo.metrics.maxScrollExtent - 200) {
                      controller.fetchMoreDiscoveryList();
                    }
                    return false;
                  },
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    padding: const EdgeInsets.all(16),
                    itemCount: controller.communities.length + 1,
                    itemBuilder: (context, index) {
                      if (index == controller.communities.length) {
                        return Obx(() => controller.isLoadingMore.value
                            ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(color: themeColor, strokeWidth: 2),
                          ),
                        )
                            : const SizedBox.shrink());
                      }

                      final item = controller.communities[index];
                      return _buildCommunityCard(context, controller, item, themeColor);
                    },
                  ),
                ),
              );
            }),
          )
        ],
      ),
    );
  }

  Widget _buildCommunityCard(
      BuildContext context,
      CommunityDiscoveryController controller,
      CommunityModel item,
      Color themeColor,
      ) {
    return GestureDetector(
      // 🌟 从社群空间返回大厅时自动重载最新状态
      onTap: () => Get.to(() => CommunitySpaceView(communityId: item.id))?.then((_) {
        controller.fetchDiscoveryList(isRefresh: true);
      }),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider, width: 1),
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
                      Expanded(
                        child: Text(
                          item.name,
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: item.price > 0.0 ? Colors.orange.shade50 : Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          item.price > 0.0
                              ? '¥${item.price.toStringAsFixed(2)} / ${item.billingCycle == 'month' ? 'monthly'.tr : 'yearly'.tr}'
                              : 'free_join'.tr,
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
                  Text(item.descShort, style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4)),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      HugeIcon(icon: HugeIcons.strokeRoundedUserGroup, color: AppColors.textHint, size: 14),
                      const SizedBox(width: 6),
                      Text('${item.memberCount} ${'members'.tr}', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                      const Spacer(),
                      if (item.isJoined)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(12)),
                          child: Text('joined_space'.tr, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(color: themeColor, borderRadius: BorderRadius.circular(12)),
                          child: Text('join_community'.tr, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
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
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('advanced_filter'.tr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 20),
              Text('price_type'.tr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 10),
              Obx(() => Row(
                children: [
                  _buildChoiceChip(
                    text: 'filter_all'.tr,
                    isSelected: controller.selectedPrice.value == 'all',
                    onTap: () => controller.updateFilters(price: 'all'),
                    themeColor: themeColor,
                  ),
                  const SizedBox(width: 8),
                  _buildChoiceChip(
                    text: 'filter_free'.tr,
                    isSelected: controller.selectedPrice.value == 'free',
                    onTap: () => controller.updateFilters(price: 'free'),
                    themeColor: themeColor,
                  ),
                  const SizedBox(width: 8),
                  _buildChoiceChip(
                    text: 'filter_paid'.tr,
                    isSelected: controller.selectedPrice.value == 'paid',
                    onTap: () => controller.updateFilters(price: 'paid'),
                    themeColor: themeColor,
                  ),
                ],
              )),
              const SizedBox(height: 20),
              Text('community_attr'.tr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 10),
              Obx(() => Row(
                children: [
                  _buildChoiceChip(
                    text: 'filter_all'.tr,
                    isSelected: controller.selectedType.value == 'all',
                    onTap: () => controller.updateFilters(type: 'all'),
                    themeColor: themeColor,
                  ),
                  const SizedBox(width: 8),
                  _buildChoiceChip(
                    text: 'filter_public'.tr,
                    isSelected: controller.selectedType.value == 'public',
                    onTap: () => controller.updateFilters(type: 'public'),
                    themeColor: themeColor,
                  ),
                  const SizedBox(width: 8),
                  _buildChoiceChip(
                    text: 'filter_private'.tr,
                    isSelected: controller.selectedType.value == 'private',
                    onTap: () => controller.updateFilters(type: 'private'),
                    themeColor: themeColor,
                  ),
                ],
              )),
              const SizedBox(height: 20),
              Text('sort_rule'.tr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 10),
              Obx(() => Row(
                children: [
                  _buildChoiceChip(
                    text: 'filter_trending'.tr,
                    isSelected: controller.selectedSort.value == 'trending',
                    onTap: () => controller.updateFilters(sort: 'trending'),
                    themeColor: themeColor,
                  ),
                  const SizedBox(width: 8),
                  _buildChoiceChip(
                    text: 'filter_top_members'.tr,
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
                  child: Text('apply_filters'.tr, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              )
            ],
          ),
        );
      },
    );
  }

  Widget _buildChoiceChip({
    required String text,
    required bool isSelected,
    required VoidCallback onTap,
    required Color themeColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? themeColor : AppColors.divider,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? themeColor : Colors.transparent, width: 1),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  void _showCreateCommunitySheet(
      BuildContext context,
      CommunityDiscoveryController controller,
      Color themeColor,
      List<Map<String, String>> categoriesList,
      ) {
    if (!UserController.to.isLoggedIn) {
      Fluttertoast.showToast(msg: 'login_to_create_community'.tr);
      return;
    }
    final TextEditingController nameC = TextEditingController();
    final TextEditingController descC = TextEditingController();
    final TextEditingController priceC = TextEditingController();

    String selectedCategory = 'music';
    String selectedType = 'public';
    String billingCycle = 'month';
    String bannerUrl = '';
    bool isUploading = false;

    final realCategories = categoriesList.where((e) => e['key'] != 'trending').toList();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> pickBannerImage() async {
              final picker = ImagePicker();
              final xFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
              if (xFile == null) return;

              setModalState(() => isUploading = true);
              Fluttertoast.showToast(msg: 'uploading_cover'.tr);

              try {
                final url = await ApiService.uploadImage(File(xFile.path));
                if (url != null) {
                  setModalState(() {
                    bannerUrl = url;
                    isUploading = false;
                  });
                  Fluttertoast.showToast(msg: 'cover_upload_success'.tr);
                } else {
                  setModalState(() => isUploading = false);
                  Fluttertoast.showToast(msg: 'cover_upload_failed'.tr);
                }
              } catch (_) {
                setModalState(() => isUploading = false);
              }
            }

            return Container(
              decoration: BoxDecoration(color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.only(
                top: 20,
                left: 24,
                right: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 30,
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
                        decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('create_my_community'.tr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: isUploading ? null : pickBannerImage,
                      child: Container(
                        width: double.infinity,
                        height: 120,
                        decoration: BoxDecoration(
                          color: AppColors.divider,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.divider),
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
                              Text('tap_upload_cover'.tr, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameC,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'community_name_hint'.tr,
                        hintStyle: TextStyle(color: AppColors.textHint, fontSize: 13),
                        prefixIcon: const Icon(Icons.drive_file_rename_outline, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descC,
                      style: const TextStyle(fontSize: 14),
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: 'community_desc_hint'.tr,
                        hintStyle: TextStyle(color: AppColors.textHint, fontSize: 13),
                        prefixIcon: const Icon(Icons.text_fields_outlined, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('select_interest_field'.tr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
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
                              color: isSelected ? themeColor : AppColors.divider,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              cat['name']!,
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : AppColors.textPrimary),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Text('public_attribute'.tr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                        const SizedBox(width: 8),
                        _buildChoiceChip(
                          text: 'join_public'.tr,
                          isSelected: selectedType == 'public',
                          onTap: () => setModalState(() => selectedType = 'public'),
                          themeColor: themeColor,
                        ),
                        const SizedBox(width: 8),
                        _buildChoiceChip(
                          text: 'join_private_approval'.tr,
                          isSelected: selectedType == 'private',
                          onTap: () => setModalState(() => selectedType = 'private'),
                          themeColor: themeColor,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: priceC,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: const TextStyle(fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'subscription_price_hint'.tr,
                              hintStyle: TextStyle(color: AppColors.textHint, fontSize: 13),
                              prefixIcon: const Icon(Icons.attach_money, size: 18),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        _buildChoiceChip(
                          text: 'bill_monthly'.tr,
                          isSelected: billingCycle == 'month',
                          onTap: () => setModalState(() => billingCycle = 'month'),
                          themeColor: themeColor,
                        ),
                        const SizedBox(width: 8),
                        _buildChoiceChip(
                          text: 'bill_yearly'.tr,
                          isSelected: billingCycle == 'year',
                          onTap: () => setModalState(() => billingCycle = 'year'),
                          themeColor: themeColor,
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () async {
                          final name = nameC.text.trim();
                          final desc = descC.text.trim();
                          final price = priceC.text.trim();

                          if (name.isEmpty) {
                            Fluttertoast.showToast(msg: 'please_enter_community_name'.tr);
                            return;
                          }

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
                            Navigator.pop(context);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: themeColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: Text(
                          'create_community_now'.tr,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
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