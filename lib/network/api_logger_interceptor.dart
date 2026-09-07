// lib/network/api_logger_interceptor.dart
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// 高性能网络日志拦截器（瞬间整块打印，杜绝流式排队卡顿）
class ApiLoggerInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (kDebugMode) {
      final sb = StringBuffer();
      sb.writeln('==================== 网络请求 ====================');
      sb.writeln('➤ 请求方式  : ${options.method}');
      sb.writeln('➤ 请求地址  : ${options.baseUrl}${options.path}');
      sb.writeln('➤ 请求头    : ${options.headers}');
      sb.writeln('➤ 查询参数  : ${options.queryParameters}');
      
      if (options.data != null) {
        if (options.data is FormData) {
          sb.writeln('➤ 请求体    : [FormData 文件上传]');
        } else if (options.data is List<int> || options.data is Uint8List) {
          final int bytesLen = (options.data as dynamic).length ?? 0;
          sb.writeln('➤ 请求体    : [Binary 二进制数据流: ${(bytesLen / 1024 / 1024).toStringAsFixed(2)} MB]');
        } else {
          try {
            sb.writeln('➤ 请求体    : ${jsonEncode(options.data)}');
          } catch (_) {
            sb.writeln('➤ 请求体    : [无法序列化的对象数据]');
          }
        }
      }
      sb.write('==================================================');
      
      // 🌟 使用 dev.log 瞬间整块输出，绕开 debugPrintThrottled 节流队列
      dev.log(sb.toString(), name: 'HTTP.Request');
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (kDebugMode) {
      final sb = StringBuffer();
      sb.writeln('==================== 网络响应 ====================');
      sb.writeln('➤ 请求地址  : ${response.requestOptions.baseUrl}${response.requestOptions.path}');
      sb.writeln('➤ 状态码    : ${response.statusCode}');
      
      if (response.data is ResponseBody) {
        sb.writeln('➤ 返回数据  : [SSE Stream Body - 流式数据不予打印]');
      } else {
        sb.writeln('➤ 返回数据  : ${_formatJson(response.data)}');
      }
      sb.write('==================================================');
      
      dev.log(sb.toString(), name: 'HTTP.Response');
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (kDebugMode) {
      final sb = StringBuffer();
      sb.writeln('==================== 网络错误 ====================');
      sb.writeln('➤ 请求地址  : ${err.requestOptions.baseUrl}${err.requestOptions.path}');
      sb.writeln('➤ 状态码    : ${err.response?.statusCode}');
      sb.writeln('➤ 错误类型  : ${err.type}');
      sb.writeln('➤ 错误信息  : ${err.message}');
      sb.writeln('➤ 返回数据  : ${err.response?.data}');
      sb.write('==================================================');
      
      dev.log(sb.toString(), name: 'HTTP.Error');
    }
    handler.next(err);
  }

  /// 智能格式化：短数据美化，超大包紧凑单行输出，兼顾美观与性能
  String _formatJson(dynamic data) {
    if (data == null) return 'null';
    if (data is String) return data;
    try {
      final jsonStr = jsonEncode(data);
      // 如果数据小于 2000 字符，进行带缩进的美化排版；超大响应采用紧凑格式，防止终端排队
      if (jsonStr.length < 2000) {
        return const JsonEncoder.withIndent('  ').convert(data);
      }
      return jsonStr;
    } catch (_) {
      return data.toString();
    }
  }
}