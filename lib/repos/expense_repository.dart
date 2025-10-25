import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/dio_provider.dart';

final expenseRepositoryProvider = Provider<ExpenseRepository>((ref) {
  return ExpenseRepository(ref.watch(dioProvider));
});

class ExpenseRepository {
  final Dio _dio;
  ExpenseRepository(this._dio);

  // ===== Utilities =====
  Never _throwUnauth([dynamic data]) {
    throw DioException(
      requestOptions: RequestOptions(path: ''),
      type: DioExceptionType.badResponse,
      response: Response(requestOptions: RequestOptions(path: ''), statusCode: 401, data: data),
      error: 'Unauthenticated',
    );
  }

  List<Map<String, dynamic>> _normalizeList(dynamic root) {
    // Detect unauth text in message
    if (root is Map) {
      final msg = root['message']?.toString().toLowerCase();
      if (msg != null && (msg.contains('unauth') || msg.contains('token'))) {
        _throwUnauth(root);
      }
    }

    // Accept formats:
    // - List
    // - {expenses:[...]} or {data:[...]} or {items:[...]} or {results:[...]}
    dynamic listLike = root;
    if (root is Map) {
      listLike = root['expenses'] ?? root['data'] ?? root['items'] ?? root['results'] ?? [];
    }

    if (listLike is! List) return const [];
    return listLike.map((e) {
      if (e is Map) return Map<String, dynamic>.from(e);
      // nếu phần tử không phải Map thì wrap lại để tránh crash UI
      return <String, dynamic>{'value': e};
    }).toList();
  }

  Map<String, dynamic> _normalizeOne(dynamic root) {
    if (root is Map) {
      final x = root['expense'] ?? root['data'] ?? root;
      if (x is Map) return Map<String, dynamic>.from(x);
    }
    return <String, dynamic>{};
  }

  Map<String, dynamic> _qp(Map<String, dynamic?> raw) {
    // loại bỏ null để query gọn
    final out = <String, dynamic>{};
    raw.forEach((k, v) {
      if (v != null) out[k] = v;
    });
    return out;
  }

  // ===== APIs =====

  Future<List<Map<String, dynamic>>> listExpenses({
    required int classId,
    int? feeCycleId,
    CancelToken? cancelToken,
  }) async {
    if (classId <= 0) {
      // Giúp debug dễ thấy lỗi "chưa chọn lớp"
      throw ArgumentError('Invalid classId ($classId)');
    }
    final res = await _dio.get(
      '/classes/$classId/expenses',
      queryParameters: _qp({'fee_cycle_id': feeCycleId}),
      cancelToken: cancelToken,
    );
    // ignore: avoid_print
    print('[expenses.list] /classes/$classId/expenses?fee_cycle_id=$feeCycleId -> ${res.data}');
    return _normalizeList(res.data);
  }

  Future<Map<String, dynamic>> createExpense({
    required int classId,
    required String title,
    required int amount,
    int? feeCycleId,
    String? note,
  }) async {
    if (classId <= 0) throw ArgumentError('Invalid classId ($classId)');
    final res = await _dio.post(
      '/classes/$classId/expenses',
      data: _qp({
        'title': title.trim(),
        'amount': amount,
        'fee_cycle_id': feeCycleId,
        'note': (note ?? '').trim().isEmpty ? null : note!.trim(),
      }),
    );
    // ignore: avoid_print
    print('[expenses.create] -> ${res.data}');
    return _normalizeOne(res.data);
  }

  Future<Map<String, dynamic>> updateExpense({
    required int classId,
    required int expenseId,
    required String title,
    required int amount,
    int? feeCycleId,
    String? note,
  }) async {
    if (classId <= 0) throw ArgumentError('Invalid classId ($classId)');
    final res = await _dio.put(
      '/classes/$classId/expenses/$expenseId',
      data: _qp({
        'title': title.trim(),
        'amount': amount,
        'fee_cycle_id': feeCycleId,
        'note': (note ?? '').trim().isEmpty ? null : note!.trim(),
      }),
    );
    // ignore: avoid_print
    print('[expenses.update#$expenseId] -> ${res.data}');
    return _normalizeOne(res.data);
  }

  Future<void> deleteExpense({
    required int classId,
    required int expenseId,
  }) async {
    if (classId <= 0) throw ArgumentError('Invalid classId ($classId)');
    final res = await _dio.delete('/classes/$classId/expenses/$expenseId');
    // ignore: avoid_print
    print('[expenses.delete#$expenseId] -> ${res.data}');
  }

  Future<Map<String, dynamic>> uploadReceipt({
    required int classId,
    required int expenseId,
    required String filePath,
    String fieldName = 'image', // khớp BE: đổi nếu server yêu cầu 'receipt'
  }) async {
    if (classId <= 0) throw ArgumentError('Invalid classId ($classId)');

    final form = FormData.fromMap({
      fieldName: await MultipartFile.fromFile(filePath),
    });

    final res = await _dio.post(
      '/classes/$classId/expenses/$expenseId/receipt',
      data: form,
      options: Options(contentType: 'multipart/form-data'),
    );
    // ignore: avoid_print
    print('[expenses.receipt#$expenseId] -> ${res.data}');
    return _normalizeOne(res.data);
  }
}
