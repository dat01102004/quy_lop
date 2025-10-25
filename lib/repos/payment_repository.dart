import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api.dart';
import '../services/session.dart';

final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  final dio = ref.watch(dioProvider);
  return PaymentRepository(ref, dio);
});

class PaymentRepository {
  final Ref _ref;
  final Dio _dio;
  PaymentRepository(this._ref, this._dio);

  Options _auth() {
    final token = _ref.read(sessionProvider).token;
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  // ================== DETAIL (đã duyệt / bất kỳ) ==================
  Future<Map<String, dynamic>> approvedDetail({
    required int classId,
    required int paymentId,
  }) async {
    final res = await _dio.get(
      '/classes/$classId/payments/$paymentId',
      options: _auth(),
    );
    // cho phép BE trả {payment:{...}} hoặc {...}
    final raw = res.data is Map ? Map<String, dynamic>.from(res.data) : <String, dynamic>{};
    final m = (raw['payment'] is Map) ? Map<String, dynamic>.from(raw['payment']) : raw;
    return m;
  }

  // (Deprecated ở BE) – vẫn giữ để FE cũ không crash
  Future<void> deleteApproved({
    required int classId,
    required int paymentId,
  }) async {
    await _dio.delete(
      '/classes/$classId/payments/$paymentId',
      options: _auth(),
    );
  }

  // ================== SUBMITTED LIST (group theo kỳ) ==================
  Future<List<Map<String, dynamic>>> listPaymentsGrouped(
      int classId, {
        String status = 'submitted',
        bool? aiFailed,
      }) async {
    final qp = <String, dynamic>{
      'status': status,
      'group': 'cycle',
      if (aiFailed == true) 'ai_failed': '1',
    };

    final res = await _dio.get(
      '/classes/$classId/payments',
      queryParameters: qp,
      options: _auth(),
    );

    final data = (res.data is Map)
        ? Map<String, dynamic>.from(res.data)
        : <String, dynamic>{};

    final list = (data['cycles'] is List) ? data['cycles'] as List : const [];
    return list
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  // ================== APPROVED LIST (phẳng) ==================
  // GET /classes/{classId}/payments/approved
  // - Thêm status?: truyền 'invalid' để lấy tab Không hợp lệ
  Future<List<Map<String, dynamic>>> listApproved({
    required int classId,
    int? feeCycleId,
    String? status,        // <-- THÊM
    bool all = false,
    String? group,
  }) async {
    final qp = <String, dynamic>{
      if (feeCycleId != null) 'fee_cycle_id': feeCycleId,
      if (status != null) 'status': status,   // ví dụ: 'invalid'
      if (all) 'all': 1,
      if (group != null) 'group': group,      // dùng khi BE hỗ trợ group
    };

    final res = await _dio.get(
      '/classes/$classId/payments/approved',
      queryParameters: qp.isEmpty ? null : qp,
      options: _auth(),
    );

    final data =
    (res.data is Map) ? Map<String, dynamic>.from(res.data) : <String, dynamic>{};

    // Case 1: BE trả trực tiếp { payments: [...] }
    if (data['payments'] is List) {
      return List<Map<String, dynamic>>.from(
        (data['payments'] as List).map((e) => Map<String, dynamic>.from(e)),
      );
    }

    // Case 2: BE trả group theo kỳ { cycles: [{ payments:[...] }, ...] }
    if (data['cycles'] is List) {
      final cycles = data['cycles'] as List;
      final flattened = <Map<String, dynamic>>[];
      for (final c in cycles) {
        final m = Map<String, dynamic>.from(c as Map);
        final ps = (m['payments'] is List) ? m['payments'] as List : const [];
        flattened.addAll(ps.map((e) => Map<String, dynamic>.from(e)));
      }
      return flattened;
    }

    // Case 3: fallback — không đúng format
    return const [];
  }

  // ================== APPROVED LIST (giữ group theo kỳ) ==================
  Future<List<Map<String, dynamic>>> listApprovedGrouped({
    required int classId,
    int? feeCycleId,
    String? status,  // có thể truyền 'invalid'
  }) async {
    final res = await _dio.get(
      '/classes/$classId/payments/approved',
      queryParameters: {
        'group': 'cycle',
        if (feeCycleId != null) 'fee_cycle_id': feeCycleId,
        if (status != null) 'status': status,
      },
      options: _auth(),
    );
    final data =
    (res.data is Map) ? Map<String, dynamic>.from(res.data) : <String, dynamic>{};
    final list = (data['cycles'] is List) ? data['cycles'] as List : const [];
    return list
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  // ================== DANH SÁCH PAYMENTS THEO STATUS ==================
  Future<List<Map<String, dynamic>>> listPayments({
    required int classId,
    String status = 'submitted',
    bool? aiFailed,
  }) async {
    final qp = <String, dynamic>{
      'status': status,
      if (aiFailed == true) 'ai_failed': '1',
    };

    final res = await _dio.get(
      '/classes/$classId/payments',
      queryParameters: qp,
      options: _auth(),
    );

    final body = res.data;
    if (body is Map && body['payments'] is List) {
      return List<Map<String, dynamic>>.from(
        (body['payments'] as List).map((e) => Map<String, dynamic>.from(e)),
      );
    }
    if (body is List) {
      return List<Map<String, dynamic>>.from(
        body.map((e) => Map<String, dynamic>.from(e)),
      );
    }
    return const [];
  }

  // ================== CHI TIẾT PAYMENT (processing) ==================
  Future<Map<String, dynamic>> paymentDetail({
    required int classId,
    required int paymentId,
  }) async {
    final res = await _dio.get(
      '/classes/$classId/payments/$paymentId',
      options: _auth(),
    );
    final body = res.data;
    if (body is Map && body['payment'] is Map) {
      return Map<String, dynamic>.from(body['payment']);
    }
    return Map<String, dynamic>.from(body as Map);
  }

  // ================== DUYỆT / TỪ CHỐI ==================
  Future<void> verifyPayment({
    required int classId,
    required int paymentId,
    required bool approve,
    String? note,
  }) async {
    await _dio.post(
      '/classes/$classId/payments/$paymentId/verify',
      data: {'action': approve ? 'approve' : 'reject', if (note != null) 'note': note},
      options: _auth(),
    );
  }

  // ================== ĐÁNH DẤU KHÔNG HỢP LỆ ==================
  Future<void> invalidatePayment({
    required int classId,
    required int paymentId,
    required String reason,
    String? note,
  }) async {
    await _dio.post(
      '/classes/$classId/payments/$paymentId/invalidate',
      data: {'reason': reason, if (note != null) 'note': note},
      options: _auth(),
    );
  }
}
