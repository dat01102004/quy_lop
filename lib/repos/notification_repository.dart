import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api.dart'; // dioProvider

class Notif {
  final String id;
  final String type;
  final String title;
  final int amount;
  final DateTime createdAt;
  bool read;

  Notif({
    required this.id,
    required this.type,
    required this.title,
    required this.amount,
    required this.createdAt,
    this.read = false,
  });

  factory Notif.fromJson(Map<String, dynamic> j) => Notif(
    id: (j['id'] ?? '').toString(),
    type: (j['type'] ?? '').toString(),
    title: (j['title'] ?? '').toString(),
    amount: _toInt(j['amount']),
    createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()) ??
        DateTime.now(),
    read: (j['read'] ?? false) == true,
  );

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}

final notificationRepositoryProvider =
Provider<NotificationRepository>((ref) {
  final dio = ref.read(dioProvider);
  return NotificationRepository(dio);
});

class NotificationRepository {
  final Dio _dio;
  NotificationRepository(this._dio);

  Future<List<Notif>> list() async {
    final res = await _dio.get('/notifications');
    final list = (res.data['data'] as List?) ?? [];
    return list
        .map((e) => Notif.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> markRead(String id) async {
    await _dio.post('/notifications/$id/read');
  }

  Future<void> markAllRead() async {
    await _dio.post('/notifications/read-all');
  }
}
