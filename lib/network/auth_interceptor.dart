import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'auth_state_manager.dart';
import 'secure_storage_manager.dart';

/// 请求挂起队列模型
class _QueuedRequest {
  final RequestOptions options;
  final ErrorInterceptorHandler handler;

  _QueuedRequest(this.options, this.handler);
}

/// Token拦截与 401 无感刷新状态锁
class AuthInterceptor extends Interceptor {
  final Dio dio;

  // 状态锁：判断是否正在刷新 Token
  bool _isRefreshing = false;

  // 挂起队列：刷新 Token 期间的所有请求会被锁在这个队列中
  final List<_QueuedRequest> _queue = [];

  AuthInterceptor(this.dio);

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // 每次发请求前注入最新的 Token
    final token = await SecureStorageManager.instance.getAccessToken();
    if (token != null && token.isNotEmpty) {
      options.headers['token'] = '$token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    // 捕获到 401 未授权错误，可能 Token 已经过期
    if (err.response?.statusCode == 401) {
      final refreshToken = await SecureStorageManager.instance.getRefreshToken();

      // 如果本地没有 RefreshToken，直接抛出给外层跳登录
      if (refreshToken == null || refreshToken.isEmpty) {
        AuthStateManager.instance.onTokenExpired();
        return handler.next(err);
      }

      // 如果当前没有在刷新，则开启【状态锁】进行刷新
      if (!_isRefreshing) {
        _isRefreshing = true;
        bool isRefreshSuccess = false;

        // 【步骤一】仅保护刷新 Token 的逻辑
        try {
          debugPrint("【AuthInterceptor】正在静默刷新 Token...");
          isRefreshSuccess = await _performRefreshToken(refreshToken);
        } catch (e) {
          debugPrint("【AuthInterceptor】刷新 Token 接口请求异常: $e");
          isRefreshSuccess = false;
        }

        // 【步骤二】根据刷新结果处理后续
        if (isRefreshSuccess) {
          debugPrint("【AuthInterceptor】Token 刷新成功！重试之前被挂起的请求。");
          final newToken = await SecureStorageManager.instance.getAccessToken();

          // 1. 重发当前失败的请求 (用独立的 try-catch 保护，避免重发失败连累到登出逻辑)
          err.requestOptions.headers['token'] = '$newToken';
          try {
            final response = await dio.fetch(err.requestOptions);
            handler.resolve(response); // 重试成功，返回正常数据
          } on DioException catch (retryErr) {
            handler.reject(retryErr); // 重试依然失败（如400/500等），将错误传递给业务层
          } catch (retryErr) {
            handler.reject(DioException(requestOptions: err.requestOptions, error: retryErr));
          }

          // 2. 释放队列锁，重发排队中的请求
          for (var q in _queue) {
            q.options.headers['token'] = '$newToken';
            try {
              final res = await dio.fetch(q.options);
              q.handler.resolve(res);
            } on DioException catch (e) {
              q.handler.reject(e);
            } catch (e) {
              q.handler.reject(DioException(requestOptions: q.options, error: e));
            }
          }
        } else {
          // 刷新失败，强制登出并清空队列
          _triggerLogout(err, handler);
        }

        // 无论成功失败，释放状态锁并清空队列
        _isRefreshing = false;
        _queue.clear();
      } else {
        // 如果【状态锁】为 true (正在刷新)，新来的请求自动进入队列等待
        debugPrint("【AuthInterceptor】正在刷新中，请求挂起等待排队...");
        _queue.add(_QueuedRequest(err.requestOptions, handler));
      }
      return; // 拦截结束
    }

    // 非 401 错误，正常放行
    handler.next(err);
  }
  /// 使用一个纯净的 Dio 实例去请求刷新接口，防止死循环触发本拦截器
  Future<bool> _performRefreshToken(String refreshToken) async {
    final tokenDio = Dio(BaseOptions(baseUrl: dio.options.baseUrl));
    try {
      // 获取可选的 access_token
      final oldAccessToken = await SecureStorageManager.instance
          .getAccessToken();

      final response = await tokenDio.post(
        '/api-users/login/refreshToken', // 替换为了您指定的接口
        data: {
          if (oldAccessToken != null) 'token': oldAccessToken, // 可选参数
          'refresh_token': refreshToken,
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final respCode = response.data['resp_code'];
        if (respCode == 0) {
          final datas = response.data['datas'];
          final newAccessToken = datas['token'];
          final newRefreshToken = datas['refresh_token'];

          await SecureStorageManager.instance.saveAccessToken(newAccessToken);
          await SecureStorageManager.instance.saveRefreshToken(newRefreshToken);
          return true;
        }
      }
      return false;
    } catch (e) {
      debugPrint("【AuthInterceptor】刷新 Token 请求本身发生异常: $e");
      return false;
    }
  }

  /// 刷新失败，执行登出和路由切换
  void _triggerLogout(DioException err, ErrorInterceptorHandler handler) {
    debugPrint("【AuthInterceptor】Token 刷新失败，踢出用户。");
    AuthStateManager.instance.onTokenExpired();
    handler.next(err);
    // 拒绝队列里等待的兄弟们
    for (var q in _queue) {
      q.handler.reject(
        DioException(requestOptions: q.options, error: "登录凭证已彻底失效，请重新登录"),
      );
    }
  }
}
