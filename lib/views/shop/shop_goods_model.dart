import 'package:get/get.dart';

class ShopGoods {
  final String id;
  final String title;
  final String desc;
  final double price;
  final String category;
  final String tag;
  final String imageUrl;
  final bool isPurchased;
  final String targetId;
  final Map<String, dynamic> rawJson;

  ShopGoods({
    required this.id,
    required this.title,
    required this.desc,
    required this.price,
    required this.category,
    required this.tag,
    required this.imageUrl,
    required this.isPurchased,
    required this.targetId,
    required this.rawJson,
  });

  factory ShopGoods.fromJson(Map<String, dynamic> json) {
    return ShopGoods(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'default_goods_title'.tr,
      desc: json['desc']?.toString() ?? 'no_description'.tr,
      price: double.tryParse(json['price']?.toString() ?? '0') ?? 0.0,
      category: json['category']?.toString() ?? 'virtual',
      tag: json['tag']?.toString() ?? 'hot_tag'.tr,
      imageUrl: json['image_url']?.toString() ?? '',
      isPurchased: json['is_purchased'] as bool? ?? false,
      targetId: json['target_id']?.toString() ?? '',
      rawJson: json,
    );
  }
}