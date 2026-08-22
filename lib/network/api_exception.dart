import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response, FormData, MultipartFile;

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
        return ApiException(message: 'err_request_cancelled'.tr);
      case DioExceptionType.connectionTimeout:
        return ApiException(message: 'err_connect_timeout'.tr);
      case DioExceptionType.sendTimeout:
        return ApiException(message: 'err_send_timeout'.tr);
      case DioExceptionType.receiveTimeout:
        return ApiException(message: 'err_receive_timeout'.tr);
      case DioExceptionType.badCertificate:
        return ApiException(message: 'err_bad_certificate'.tr);
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
            return ApiException(statusCode: statusCode, message: 'err_bad_request'.tr);
          case 401:
            return ApiException(statusCode: statusCode, message: 'err_unauthorized'.tr);
          case 403:
            return ApiException(statusCode: statusCode, message: 'err_forbidden'.tr);
          case 404:
            return ApiException(statusCode: statusCode, message: 'err_not_found'.tr);
          case 500:
          case 502:
          case 503:
            return ApiException(statusCode: statusCode, message: 'err_server_error'.tr);
          default:
            return ApiException(
              statusCode: statusCode,
              message: error.response?.statusMessage ?? 'err_bad_response'.tr,
            );
        }
      case DioExceptionType.connectionError:
        return ApiException(message: 'err_connection_lost'.tr);
      case DioExceptionType.unknown:
        return ApiException(message: 'err_unknown_network'.tr);
      // 🌟 兜底分支：dio 后续版本新增的异常类型(如 transformTimeout)统一按未知网络错误处理，
      //    避免依赖升级后 switch 不完备导致编译失败。
      default:
        return ApiException(message: 'err_unknown_network'.tr);
    }
  }

  @override
  String toString() {
    return 'ApiException: statusCode=$statusCode, businessCode=$businessCode, message=$message';
  }
}