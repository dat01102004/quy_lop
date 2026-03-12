import 'package:dio/dio.dart';

class FundNotificationRepository {
  final Dio _dio;

  FundNotificationRepository({required Dio dio}) : _dio = dio;

  Future<List<Map<String, dynamic>>> getNotifications({int page = 1}) async {
    final res = await _dio.get(
      '/notifications',
      queryParameters: {'page': page},
    );

    // Tuỳ BE: nếu BE trả về { data: [...] }
    final data = res.data['data'] as List<dynamic>;
    return data.cast<Map<String, dynamic>>();
  }

  Future<int> getUnreadCount() async {
    final res = await _dio.get('/notifications/unread-count');
    return (res.data['unread'] as num).toInt();
  }

  Future<void> markAsRead(int notificationId) async {
    await _dio.post('/notifications/$notificationId/read');
  }

  Future<void> markAllAsRead() async {
    await _dio.post('/notifications/read-all');
  }
}
