// lib/services/api.dart
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../env.dart';
import 'session.dart';

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: Env.apiBase,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'Accept': 'application/json'},
    ),
  );

  dio.interceptors.add(InterceptorsWrapper(
    // Luôn chèn token mới nhất trước khi bắn request
    onRequest: (options, handler) {
      final token = ref.read(sessionProvider).token;
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      } else {
        options.headers.remove('Authorization');
      }
      handler.next(options);
    },

    onError: (e, handler) async {
      // Chuẩn hoá lỗi offline -> connectionError (DNS/Socket)
      if (e.type == DioExceptionType.unknown && e.error is SocketException) {
        e = DioException(
          requestOptions: e.requestOptions,
          response: e.response,
          error: e.error,
          type: DioExceptionType.connectionError,
          message: e.message,
        );
      }

      // 401 -> đăng xuất
      if (e.response?.statusCode == 401) {
        try { ref.read(sessionProvider.notifier).logout(); } catch (_) {}
      }

      // Retry nhẹ 1 lần cho lỗi mạng/timeout
      final transient = e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout   ||
          e.type == DioExceptionType.connectionError;
      final retried = e.requestOptions.extra['__retried'] == true;

      if (transient && !retried) {
        final req = e.requestOptions;
        req.extra = {...req.extra, '__retried': true};
        try {
          final res = await dio.fetch(req);
          return handler.resolve(res);
        } catch (_) {
          // bỏ qua, rơi xuống handler.next(e)
        }
      }

      handler.next(e);
    },
  ));

  return dio;
});
