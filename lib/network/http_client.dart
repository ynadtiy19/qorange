import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'dart:typed_data';

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

  // 统一指向您的 Zeabur 线上部署后端服务
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
        // validateStatus: (status) => status != null && status < 500,
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
        Duration? connectTimeout,
        Duration? receiveTimeout,
        Duration? sendTimeout,
      }) async {
    try {
      final response = await _dio.request(
        path,
        data: data,
        queryParameters: queryParameters,
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


  /// ==============================
  /// PUT 请求 (新增补全)
  /// ==============================
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



  /// ==============================
  /// DELETE 请求 (新增)
  /// ==============================
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