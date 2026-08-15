import 'package:get/get.dart';

class CommunityModel {
  final String id;
  final String name;
  final String category;
  final double price;
  final String billingCycle;
  final String descShort;
  final String fullDesc;
  final String type;
  final String bannerUrl;
  final List<String> images;
  final List<Map<String, String>> links;
  final String creatorId;
  final int memberCount;
  final int trendingScore;
  final bool isJoined;
  final String createdAt;

  CommunityModel({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.billingCycle,
    required this.descShort,
    required this.fullDesc,
    required this.type,
    required this.bannerUrl,
    required this.images,
    required this.links,
    required this.creatorId,
    required this.memberCount,
    required this.trendingScore,
    required this.isJoined,
    required this.createdAt,
  });

  factory CommunityModel.fromJson(Map<String, dynamic> json) {
    var imgs = <String>[];
    if (json['images'] != null) {
      imgs = List<String>.from(json['images']);
    }

    var lnks = <Map<String, String>>[];
    if (json['links'] != null) {
      json['links'].forEach((v) {
        if (v is Map) {
          lnks.add({
            'title': v['title']?.toString() ?? '',
            'url': v['url']?.toString() ?? '',
          });
        }
      });
    }

    return CommunityModel(
      id: json['id'] ?? '',
      name: json['name'] ?? 'default_community_name'.tr,
      category: json['category'] ?? 'general',
      price: double.tryParse(json['price']?.toString() ?? '0') ?? 0.0,
      billingCycle: json['billing_cycle'] ?? 'month',
      descShort: json['desc_short'] ?? '',
      fullDesc: json['full_desc'] ?? '',
      type: json['type'] ?? 'public',
      bannerUrl: json['banner_url'] ?? '',
      images: imgs,
      links: lnks,
      creatorId: json['creator_id'] ?? '',
      memberCount: json['member_count'] ?? 1,
      trendingScore: json['trending_score'] ?? 0,
      isJoined: json['is_joined'] ?? false,
      createdAt: json['created_at'] ?? '',
    );
  }
}