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
      if (msg != null &&
          (msg.contains('unauth') || msg.contains('token'))) {
        _throwUnauth(root);
      }
    }

    dynamic listLike = root;
    if (root is Map) {
      listLike = root['comments'] ??
          root['data'] ??
          root['items'] ??
          root['results'] ??
          [];
    }

    if (listLike is! List) return const [];

    return listLike.map<Map<String, dynamic>>((e) {
      if (e is Map) return Map<String, dynamic>.from(e);
      return {'value': e};
    }).toList();
  }

  Map<String, dynamic> _normalizeOne(dynamic root) {
    if (root is Map) {
      final x = root['comment'] ?? root['data'] ?? root;
      if (x is Map) return Map<String, dynamic>.from(x);
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

  // ===== APIs =====

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

    // ignore: avoid_print
    print('[comments.list] /classes/$classId/expenses/$expenseId/comments -> ${res.data}');
    return _normalizeList(res.data);
  }

  Future<Map<String, dynamic>> createComment({
    required int classId,
    required int expenseId,
    required String body,
  }) async {
    if (classId <= 0) {
      throw ArgumentError('Invalid classId ($classId)');
    }

    final res = await _dio.post(
      '/classes/$classId/expenses/$expenseId/comments',
      data: _qp({'body': body.trim()}),
    );

    // ignore: avoid_print
    print('[comments.create] -> ${res.data}');
    return _normalizeOne(res.data);
  }
}
