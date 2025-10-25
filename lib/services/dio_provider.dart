import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../env.dart';
import 'session.dart';

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: Env.apiBase, // đảm bảo đúng baseUrl
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Accept': 'application/json'},
      validateStatus: (code) => code != null && code < 400, // 4xx -> DioException
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        // 👉 luôn đọc token mới nhất tại thời điểm request
        final token = ref.read(sessionProvider).token;
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        } else {
          options.headers.remove('Authorization');
        }
        handler.next(options);
      },
      onError: (e, handler) async {
        // Tuỳ chọn: nếu 401 từ server -> xoá session để yêu cầu login lại
        if (e.response?.statusCode == 401) {
          // tránh vòng lặp nếu lỗi từ /login hoặc /register
          final path = e.requestOptions.path;
          if (!path.endsWith('/login') && !path.endsWith('/register')) {
            try {
              await ref.read(sessionProvider.notifier).logout();
            } catch (_) {}
          }
        }
        handler.next(e);
      },
    ),
  );

  // (Tuỳ chọn) LogInterceptor phục vụ debug
  // dio.interceptors.add(LogInterceptor(requestBody: true, responseBody: true));

  return dio;
});
