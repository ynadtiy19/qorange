// lib/network/http_client.dart
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response, FormData, MultipartFile;

import 'api_exception.dart';
import 'api_logger_interceptor.dart';
import 'api_response.dart';
import 'auth_interceptor.dart';

/// 统一网络请求客户端
class HttpClient {
  HttpClient._internal() {
    _initDio();
  }

  static final HttpClient _instance = HttpClient._internal();
  static HttpClient get instance => _instance;

  late Dio _dio;

  // 统一指向 Zeabur 线上部署后端服务
  static const String _baseUrl = 'https://googlechat.zeabur.app';
  static const Duration _defaultConnectTimeout = Duration(seconds: 15);
  static const Duration _defaultReceiveTimeout = Duration(seconds: 15);
  static const Duration _defaultSendTimeout = Duration(seconds: 15);

  void _initDio() {
    _dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: _defaultConnectTimeout,
        receiveTimeout: _defaultReceiveTimeout,
        sendTimeout: _defaultSendTimeout,
      ),
    );

    _dio.interceptors.add(AuthInterceptor(_dio));
    _dio.interceptors.add(ApiLoggerInterceptor());
  }

  Future<ApiResponse<T>> _request<T>(
      String path, {
        required String method,
        Map<String, dynamic>? queryParameters,
        dynamic data,
        Map<String, dynamic>? headers,
        ProgressCallback? onSendProgress, // 🌟 改动点：支持发送进度监听
        Duration? connectTimeout,
        Duration? receiveTimeout,
        Duration? sendTimeout,
      }) async {
    try {
      final response = await _dio.request(
        path,
        data: data,
        queryParameters: queryParameters,
        onSendProgress: onSendProgress, // 🌟 改动点：透传给 Dio 底层
        options: Options(
          method: method,
          headers: headers,
          sendTimeout: sendTimeout,
          receiveTimeout: receiveTimeout,
        ),
      );

      final apiResponse = ApiResponse<T>.fromJson(response.data);
      apiResponse.checkBusinessError();
      return apiResponse;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'err_parse_data'.trParams({'error': e.toString()}));
    }
  }

  Future<ApiResponse<T>> get<T>(
      String path, {
        Map<String, dynamic>? queryParameters,
        Map<String, dynamic>? headers,
        Duration? receiveTimeout,
      }) async {
    return _request<T>(
      path,
      method: 'GET',
      queryParameters: queryParameters,
      headers: headers,
      receiveTimeout: receiveTimeout,
    );
  }

  Future<ApiResponse<T>> post<T>(
      String path, {
        dynamic data,
        Map<String, dynamic>? queryParameters,
        Map<String, dynamic>? headers,
        Duration? sendTimeout,
        Duration? receiveTimeout,
      }) async {
    return _request<T>(
      path,
      method: 'POST',
      data: data,
      queryParameters: queryParameters,
      headers: headers,
      sendTimeout: sendTimeout,
      receiveTimeout: receiveTimeout,
    );
  }

  Future<ApiResponse<T>> put<T>(
      String path, {
        dynamic data,
        Map<String, dynamic>? queryParameters,
        Map<String, dynamic>? headers,
        Duration? sendTimeout,
        Duration? receiveTimeout,
      }) async {
    return _request<T>(
      path,
      method: 'PUT',
      data: data,
      queryParameters: queryParameters,
      headers: headers,
      receiveTimeout: receiveTimeout,
    );
  }

  Future<ApiResponse<T>> delete<T>(
      String path, {
        dynamic data,
        Map<String, dynamic>? queryParameters,
        Map<String, dynamic>? headers,
        Duration? sendTimeout,
        Duration? receiveTimeout,
      }) async {
    return _request<T>(
      path,
      method: 'DELETE',
      data: data,
      queryParameters: queryParameters,
      headers: headers,
      receiveTimeout: receiveTimeout,
    );
  }

  Future<ApiResponse<T>> upload<T>(
      String path, {
        required String filePath,
        String fileKey = 'file',
        Map<String, dynamic>? additionalData,
        Map<String, dynamic>? headers,
        ProgressCallback? onSendProgress,
      }) async {
    try {
      final fileName = filePath.split('/').last;
      final formData = FormData.fromMap({
        if (additionalData != null) ...additionalData,
        fileKey: await MultipartFile.fromFile(filePath, filename: fileName),
      });

      final response = await _dio.post(
        path,
        data: formData,
        options: Options(headers: headers),
        onSendProgress: onSendProgress,
      );

      final apiResponse = ApiResponse<T>.fromJson(response.data);
      apiResponse.checkBusinessError();
      return apiResponse;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'err_parse_upload'.trParams({'error': e.toString()}));
    }
  }

  /// 🌟 核心改动：发送纯二进制字节流（加入 onSendProgress 进度监听与大文件超时保障）
  Future<ApiResponse<T>> postBinary<T>(
      String path, {
        required Uint8List data,
        Map<String, dynamic>? queryParameters,
        ProgressCallback? onSendProgress, // 🌟 改动点：支持上传百分比监听
        Duration? sendTimeout,
        Duration? receiveTimeout,
      }) async {
    return _request<T>(
      path,
      method: 'POST',
      data: data,
      queryParameters: queryParameters,
      headers: {
        'Content-Type': 'application/octet-stream',
      },
      onSendProgress: onSendProgress, // 🌟 改动点：传入进度监听
      sendTimeout: sendTimeout ?? const Duration(minutes: 5), // 🌟 改动点：大文件默认5分钟超时
      receiveTimeout: receiveTimeout ?? const Duration(minutes: 5),
    );
  }

  Future<Stream<Uint8List>> postStream(
      String path, {
        dynamic data,
        Map<String, dynamic>? queryParameters,
        Map<String, dynamic>? headers,
        Duration? sendTimeout,
        Duration? receiveTimeout,
      }) async {
    try {
      final response = await _dio.post<ResponseBody>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(
          headers: headers,
          responseType: ResponseType.stream,
          sendTimeout: sendTimeout,
          receiveTimeout: receiveTimeout,
        ),
      );

      if (response.data != null) {
        return response.data!.stream;
      } else {
        throw ApiException(message: 'err_stream_no_data'.tr);
      }
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'err_parse_stream'.trParams({'error': e.toString()}));
    }
  }
}