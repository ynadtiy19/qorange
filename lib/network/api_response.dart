import 'api_exception.dart';

/// 统一网络响应数据结构解析
class ApiResponse<T> {
  final int count;
  final int respCode;
  final String respMsg;
  final T? datas;

  ApiResponse({
    required this.count,
    required this.respCode,
    required this.respMsg,
    this.datas,
  });

  /// 自动解析 JSON，支持泛型提取
  factory ApiResponse.fromJson(Map<String, dynamic> json) {
    return ApiResponse(
      count: json['count'] ?? 0,
      respCode: json['resp_code'] ?? -1,
      respMsg: json['resp_msg'] ?? '该api返回的json消息为空',
      datas: json['datas'] as T?,
    );
  }

  /// 业务是否成功判定 (resp_code == 0 视为成功)
  bool get isSuccess => respCode == 0;

  /// 如果业务失败，抛出业务异常
  void checkBusinessError() {
    if (!isSuccess) {
      throw ApiException(
        statusCode: 200,
        businessCode: respCode,
        message: respMsg,
      );
    }
  }
}
