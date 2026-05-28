import 'dart:convert';
import 'package:dio/dio.dart';

/// 全局自定义异常处理类
class ApiException implements Exception {
  final int? statusCode; // HTTP 状态码 (如 401, 404, 500)
  final int? businessCode; // 业务状态码 (如 resp_code)
  final String message; // 错误信息

  ApiException({this.statusCode, this.businessCode, required this.message});

  /// 辅助方法：尝试从服务器的原始响应中提取具体的错误信息
  static String _extractServerMessage(Response? response) {
    if (response?.data != null) {
      final data = response!.data;
      if (data is Map) {
        // 尝试从返回的 Map 中提取标准的业务错误字段
        if (data['resp_msg'] != null && data['resp_msg'].toString().isNotEmpty) {
          return data['resp_msg'].toString();
        }
        if (data['message'] != null && data['message'].toString().isNotEmpty) {
          return data['message'].toString();
        }
      } else if (data is String) {
        try {
          final Map<String, dynamic> parsed = jsonDecode(data);
          if (parsed['resp_msg'] != null && parsed['resp_msg'].toString().isNotEmpty) {
            return parsed['resp_msg'].toString();
          }
        } catch (_) {}
      }
    }
    return '';
  }

  /// 将 DioException 转换为自定义异常
  factory ApiException.fromDioException(DioException error) {
    switch (error.type) {
      case DioExceptionType.cancel:
        return ApiException(message: "请求被取消");
      case DioExceptionType.connectionTimeout:
        return ApiException(message: "连接超时，请检查网络");
      case DioExceptionType.sendTimeout:
        return ApiException(message: "请求发送超时");
      case DioExceptionType.receiveTimeout:
        return ApiException(message: "响应接收超时");
      case DioExceptionType.badCertificate:
        return ApiException(message: "证书验证失败");
      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode;

        // 🌟 核心改进点：优先提取后端返回的 resp_msg 错误细节
        final serverMessage = _extractServerMessage(error.response);
        if (serverMessage.isNotEmpty) {
          return ApiException(
            statusCode: statusCode,
            businessCode: error.response?.data is Map ? error.response?.data['resp_code'] : null,
            message: serverMessage,
          );
        }

        // 如果后端没有返回任何包含 resp_msg 的内容，再退回到本地通用的 HTTP 提示
        switch (statusCode) {
          case 400:
            return ApiException(statusCode: statusCode, message: "语法错误，服务器无法理解请求");
          case 401:
            return ApiException(statusCode: statusCode, message: "登录已过期，请重新登录");
          case 403:
            return ApiException(statusCode: statusCode, message: "服务器拒绝执行此请求");
          case 404:
            return ApiException(statusCode: statusCode, message: "请求资源不存在");
          case 500:
          case 502:
          case 503:
            return ApiException(statusCode: statusCode, message: "服务器内部异常，请稍后重试");
          default:
            return ApiException(
              statusCode: statusCode,
              message: error.response?.statusMessage ?? "网络响应异常",
            );
        }
      case DioExceptionType.connectionError:
        return ApiException(message: "网络连接断开，请检查网络设置");
      case DioExceptionType.unknown:
        return ApiException(message: "未知网络错误");
    }
  }

  @override
  String toString() {
    return 'ApiException: statusCode=$statusCode, businessCode=$businessCode, message=$message';
  }
}