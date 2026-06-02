class ApplicantModel {
  final String userId;
  final String nickname;
  final String avatar;
  final String appliedAt;

  ApplicantModel({
    required this.userId,
    required this.nickname,
    required this.avatar,
    required this.appliedAt,
  });

  factory ApplicantModel.fromJson(Map<String, dynamic> json) {
    return ApplicantModel(
      userId: json['userId'] ?? '',
      nickname: json['nickname'] ?? '学者',
      avatar: json['avatar'] ?? '',
      appliedAt: json['appliedAt'] ?? '',
    );
  }
}