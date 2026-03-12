import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/dio_provider.dart';

final expenseCommentRepositoryProvider = Provider((ref) {
  return ExpenseCommentRepository(ref.watch(dioProvider));
});

class ExpenseCommentRepository {
  final Dio _dio;
  ExpenseCommentRepository(this._dio);

  Never _throwUnauth([dynamic data]) {
    throw DioException(
      requestOptions: RequestOptions(path: ''),
      type: DioExceptionType.badResponse,
      response: Response(
        requestOptions: RequestOptions(path: ''),
        statusCode: 401,
        data: data,
      ),
      error: 'Unauthenticated',
    );
  }

  List<Map<String, dynamic>> _normalizeList(dynamic root) {
    if (root is Map) {
      final msg = root['message']?.toString().toLowerCase();
      if (msg != null && (msg.contains('unauth') || msg.contains('token'))) {
        _throwUnauth(root);
      }
    }

    dynamic listLike = root;
    if (root is Map) {
      listLike =
          root['comments'] ?? root['data'] ?? root['items'] ?? root['results'] ?? [];
    }

    if (listLike is! List) return const [];

    return listLike.map<Map<String, dynamic>>((e) {
      if (e is! Map) return {'value': e};

      final item = Map<String, dynamic>.from(e);

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

      item['liked_users'] ??= const [];
      item['like_count'] ??= 0;
      item['is_liked'] ??= false;

      return item;
    }).toList();
  }

  Map<String, dynamic> _normalizeOne(dynamic root) {
    if (root is Map) {
      final x = root['comment'] ?? root['data'] ?? root;
      if (x is Map) {
        final item = Map<String, dynamic>.from(x);

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

        item['liked_users'] ??= const [];
        item['like_count'] ??= 0;
        item['is_liked'] ??= false;

        return item;
      }
    }
    return <String, dynamic>{};
  }

  Map<String, dynamic> _qp(Map<String, dynamic> raw) {
    final out = <String, dynamic>{};
    raw.forEach((k, v) {
      if (v != null) out[k] = v;
    });
    return out;
  }

  Future<List<Map<String, dynamic>>> listComments({
    required int classId,
    required int expenseId,
    CancelToken? cancelToken,
  }) async {
    if (classId <= 0) {
      throw ArgumentError('Invalid classId ($classId)');
    }

    final res = await _dio.get(
      '/classes/$classId/expenses/$expenseId/comments',
      cancelToken: cancelToken,
    );

    print(
      '[comments.list] /classes/$classId/expenses/$expenseId/comments -> ${res.data}',
    );

    return _normalizeList(res.data);
  }

  Future<Map<String, dynamic>> createComment({
    required int classId,
    required int expenseId,
    required String body,
    int? parentId,
  }) async {
    if (classId <= 0) {
      throw ArgumentError('Invalid classId ($classId)');
    }

    final payload = _qp({
      'body': body.trim(),
      'parent_id': parentId,
      'reply_to_id': parentId,
      'parent_comment_id': parentId,
    });

    final res = await _dio.post(
      '/classes/$classId/expenses/$expenseId/comments',
      data: payload,
    );

    print('[comments.create] -> ${res.data}');
    return _normalizeOne(res.data);
  }
}