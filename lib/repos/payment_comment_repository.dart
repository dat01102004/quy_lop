import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quylop/services/api.dart';

import '../services/network.dart';

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

    List rawList = [];
    final data = res.data;

    if (data is List) {
      rawList = data;
    } else if (data is Map && data['data'] is List) {
      rawList = data['data'] as List;
    }

    return rawList.map<Map<String, dynamic>>((e) {
      final item = Map<String, dynamic>.from(e as Map);

      item['parent_id'] ??=
          item['reply_to_id'] ??
              item['parent_comment_id'] ??
              (item['parent'] is Map ? item['parent']['id'] : null) ??
              (item['reply_to'] is Map ? item['reply_to']['id'] : null);

      item['reply_to_name'] ??=
          item['parent_user_name'] ??
              (item['parent'] is Map ? item['parent']['user_name'] : null) ??
              (item['parent'] is Map ? item['parent']['name'] : null) ??
              (item['reply_to'] is Map ? item['reply_to']['user_name'] : null) ??
              (item['reply_to'] is Map ? item['reply_to']['name'] : null);

      item['user_name'] ??=
          (item['user'] is Map ? item['user']['name'] : null) ??
              (item['user'] is Map ? item['user']['user_name'] : null) ??
              item['name'];

      if (item['liked_users'] == null) {
        final likes = item['likes'] ?? item['likers'];
        if (likes is List) {
          item['liked_users'] = likes;
        }
      }

      item['like_count'] ??=
          item['likes_count'] ??
              (item['liked_users'] is List
                  ? (item['liked_users'] as List).length
                  : null) ??
              0;

      item['is_liked'] ??= item['liked'] ?? item['viewer_liked'] ?? false;

      return item;
    }).toList();
  }

  Future<Map<String, dynamic>> createComment({
    required int classId,
    required int paymentId,
    required String body,
    int? parentId,
  }) async {
    final payload = <String, dynamic>{'body': body};

    if (parentId != null) {
      payload['parent_id'] = parentId;
      payload['reply_to_id'] = parentId;
      payload['parent_comment_id'] = parentId;
    }

    final res = await _dio.post(
      '/classes/$classId/payments/$paymentId/comments',
      data: payload,
    );

    final data = res.data;
    if (data is Map && data['data'] is Map) {
      return Map<String, dynamic>.from(data['data'] as Map);
    }
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>> setLike({
    required int classId,
    required int paymentId,
    required int commentId,
    required bool like,
  }) async {
    final path =
        '/classes/$classId/payments/$paymentId/comments/$commentId/likes';

    final Response<dynamic> res;
    if (like) {
      res = await _dio.post(path);
    } else {
      res = await _dio.delete(path);
    }

    final data = res.data;
    if (data is Map && data['data'] is Map) {
      return Map<String, dynamic>.from(data['data'] as Map);
    }
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return <String, dynamic>{};
  }
}