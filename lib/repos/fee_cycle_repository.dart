import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api.dart';       // dioProvider
import '../services/session.dart';   // sessionProvider để lấy token

final feeCycleRepositoryProvider = Provider<FeeCycleRepository>((ref) {
  final dio = ref.watch(dioProvider);
  return FeeCycleRepository(ref, dio);
});

class FeeCycleRepository {
  final Ref _ref;
  final Dio _dio;
  FeeCycleRepository(this._ref, this._dio);

  // Đính kèm Bearer token cho mọi request
  Options _auth() {
    final token = _ref.read(sessionProvider).token;
    return Options(headers: {
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      'Accept': 'application/json',
    });
  }

  /// Ép kiểu int an toàn
  int _asInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    final s = v.toString();
    final onlyDigits = RegExp(r'-?\d+');
    final m = onlyDigits.firstMatch(s);
    if (m == null) return 0;
    return int.tryParse(m.group(0)!) ?? 0;
  }

  /// Ép kiểu bool an toàn
  bool _asBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.toLowerCase().trim();
      return s == 'true' || s == '1' || s == 'yes';
    }
    return false;
  }

  /// Danh sách kỳ thu
  Future<List<Map<String, dynamic>>> listCycles(int classId) async {
    final res = await _dio.get('/classes/$classId/fee-cycles', options: _auth());

    List<Map<String, dynamic>> normalizeList(List list) {
      return List<Map<String, dynamic>>.from(
        list.map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          if (m.containsKey('amount_per_member')) {
            m['amount_per_member'] = _asInt(m['amount_per_member']);
          }
          if (m.containsKey('allow_late')) {
            m['allow_late'] = _asBool(m['allow_late']);
          }
          return m;
        }),
      );
    }

    if (res.data is List) {
      return normalizeList(res.data as List);
    }

    if (res.data is Map) {
      final data = Map<String, dynamic>.from(res.data as Map);
      final raw = (data['fee_cycles'] ?? data['items'] ?? data['data'] ?? const []) as List;
      return normalizeList(raw);
    }

    return const [];
  }

  /// Chi tiết 1 kỳ thu (nếu cần)
  Future<Map<String, dynamic>> getCycle(int classId, int cycleId) async {
    final res = await _dio.get(
      '/classes/$classId/fee-cycles/$cycleId',
      options: _auth(),
    );
    if (res.data is Map) {
      final m = Map<String, dynamic>.from(res.data as Map);
      final x = Map<String, dynamic>.from((m['fee_cycle'] ?? m['data'] ?? m) as Map);
      if (x.containsKey('amount_per_member')) {
        x['amount_per_member'] = _asInt(x['amount_per_member']);
      }
      if (x.containsKey('allow_late')) {
        x['allow_late'] = _asBool(x['allow_late']);
      }
      return x;
    }
    return {};
  }

  /// Tạo kỳ thu (có hỗ trợ allowLate -> gửi lên 'allow_late')
  Future<Map<String, dynamic>> createCycle({
    required int classId,
    required String name,
    String? term,
    required num amountPerMember,
    required String dueDateIso, // yyyy-MM-dd
    bool allowLate = false,
  }) async {
    final res = await _dio.post(
      '/classes/$classId/fee-cycles',
      options: _auth(),
      data: {
        'name': name,
        if (term != null && term.isNotEmpty) 'term': term,
        'amount_per_member': amountPerMember,
        'due_date': dueDateIso,
        'allow_late': allowLate, // 👈 thêm trường này
      },
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Phát hoá đơn theo kỳ
  Future<Map<String, dynamic>> generateInvoices({
    required int classId,
    required int cycleId,
    int? amountPerMember,
  }) async {
    final res = await _dio.post(
      '/classes/$classId/fee-cycles/$cycleId/generate-invoices',
      options: _auth(),
      data: {
        if (amountPerMember != null) 'amount_per_member': amountPerMember,
      },
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Báo cáo kỳ thu (đồng bộ với ReportController@cycleSummary)
  Future<Map<String, dynamic>> report(int classId, int cycleId) async {
    final res = await _dio.get(
      '/classes/$classId/fee-cycles/$cycleId/report',
      options: _auth(),
    );
    final raw = Map<String, dynamic>.from(res.data as Map);

    // Chuẩn hoá kiểu số cho FE dùng an tâm
    return {
      ...raw,
      'active_members': _asInt(raw['active_members']),
      'amount_per_member': _asInt(raw['amount_per_member']),
      'expected_total': _asInt(raw['expected_total']),
      'unpaid_total': _asInt(raw['unpaid_total']),
      'submitted_total': _asInt(raw['submitted_total']),
      'verified_total': _asInt(raw['verified_total']),
      'paid_total': _asInt(raw['paid_total']),
      'total_income': _asInt(raw['total_income']),
      'total_expense': _asInt(raw['total_expense']),
      'balance': _asInt(raw['balance']),
    };
  }

  /// Số dư hiện tại của lớp (ReportController@classBalance)
  Future<Map<String, int>> classBalance(int classId) async {
    final res = await _dio.get(
      '/classes/$classId/balance',
      options: _auth(),
    );
    final m = Map<String, dynamic>.from(res.data as Map);
    return {
      'income': _asInt(m['income']),
      'expense': _asInt(m['expense']),
      'balance': _asInt(m['balance']),
    };
  }
}
