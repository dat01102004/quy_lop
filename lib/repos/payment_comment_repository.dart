import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../repos/payment_comment_repository.dart';
import '../services/session.dart';
import '../services/network.dart';

import '../services/api.dart';

final paymentCommentRepositoryProvider =
Provider<PaymentCommentRepository>((ref) {
  final dio = ref.read(dioProvider);
  return PaymentCommentRepository(dio);
});

class PaymentCommentRepository {
  final Dio _dio;
  PaymentCommentRepository(this._dio);

  Future<List<Map<String, dynamic>>> listComments({
    required int classId,
    required int paymentId,
  }) async {
    final res = await _dio.get(
      '/classes/$classId/payments/$paymentId/comments',
    );

    final data = res.data;
    if (data is List) {
      return data.map<Map<String, dynamic>>((e) {
        return Map<String, dynamic>.from(e as Map);
      }).toList();
    }
    if (data is Map && data['data'] is List) {
      return (data['data'] as List).map<Map<String, dynamic>>((e) {
        return Map<String, dynamic>.from(e as Map);
      }).toList();
    }
    return [];
  }

  Future<Map<String, dynamic>> createComment({
    required int classId,
    required int paymentId,
    required String body,
  }) async {
    final res = await _dio.post(
      '/classes/$classId/payments/$paymentId/comments',
      data: {
        'body': body,
      },
    );

    return Map<String, dynamic>.from(res.data as Map);
  }
}
