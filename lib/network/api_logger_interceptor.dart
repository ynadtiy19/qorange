// lib/network/api_logger_interceptor.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// 专门用于控制台友好打印的网络日志拦截器
class ApiLoggerInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (kDebugMode) {
      debugPrint('\n==================== 网络请求 ====================');
      debugPrint('➤ 请求方式  : ${options.method}');
      debugPrint('➤ 请求地址  : ${options.baseUrl}${options.path}');
      debugPrint('➤ 请求头    : ${options.headers}');
      debugPrint('➤ 查询参数  : ${options.queryParameters}');
      if (options.data != null) {
        if (options.data is FormData) {
          debugPrint('➤ 请求体    : [FormData 文件上传]');
        } else if (options.data is List<int> || options.data is Uint8List) {
          // 🌟 核心改动：遇到二进制大包直接跳过 JSON 序列化，释放手机 CPU！
          final int bytesLen = (options.data as dynamic).length ?? 0;
          debugPrint('➤ 请求体    : [Binary 二进制数据流: ${(bytesLen / 1024 / 1024).toStringAsFixed(2)} MB]');
        } else {
          try {
            debugPrint('➤ 请求体    : ${jsonEncode(options.data)}');
          } catch (_) {
            debugPrint('➤ 请求体    : [无法序列化的对象数据]');
          }
        }
      }
      debugPrint('==================================================\n');
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (kDebugMode) {
      debugPrint('\n==================== 网络响应 ====================');
      debugPrint(
        '➤ 请求地址  : ${response.requestOptions.baseUrl}${response.requestOptions.path}',
      );
      debugPrint('➤ 状态码    : ${response.statusCode}');
      if (response.data is ResponseBody) {
        debugPrint('➤ 返回数据    : [SSE Stream Body - 流式数据不予打印]');
      } else {
        debugPrint('➤ 返回数据    : ${_prettyPrintJson(response.data)}');
      }
      debugPrint('==================================================\n');
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (kDebugMode) {
      debugPrint('\n==================== 网络错误 ====================');
      debugPrint(
        '➤ 请求地址  : ${err.requestOptions.baseUrl}${err.requestOptions.path}',
      );
      debugPrint('➤ 状态码    : ${err.response?.statusCode}');
      debugPrint('➤ 错误类型  : ${err.type}');
      debugPrint('➤ 错误信息  : ${err.message}');
      debugPrint('➤ 返回数据  : ${err.response?.data}');
      debugPrint('==================================================\n');
    }
    handler.next(err);
  }

  /// 格式化 JSON 输出（美化打印）
  String _prettyPrintJson(dynamic json) {
    try {
      final encoder = const JsonEncoder.withIndent('  ');
      return encoder.convert(json);
    } catch (e) {
      return json.toString();
    }
  }
}