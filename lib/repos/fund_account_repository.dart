import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/dio_provider.dart';

final fundAccountRepositoryProvider = Provider<FundAccountRepository>((ref) {
  return FundAccountRepository(ref.watch(dioProvider));
});

class FundAccountRepository {
  final Dio _dio;
  FundAccountRepository(this._dio);

  int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  /// Sổ tay thu/chi
  /// GET /classes/{classId}/ledger?fee_cycle_id=&from=&to=
  /// BE trả: { opening, income, expenses, closing, items: [...] }
  Future<Map<String, dynamic>> getLedger({
    required int classId,
    int? feeCycleId,
    DateTime? from,
    DateTime? to,
  }) async {
    String? _d(DateTime? d) =>
        d == null ? null : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    final q = <String, dynamic>{};
    if (feeCycleId != null) q['fee_cycle_id'] = feeCycleId;
    final fs = _d(from), ts = _d(to);
    if (fs != null) q['from'] = fs;
    if (ts != null) q['to'] = ts;

    final res = await _dio.get('/classes/$classId/ledger', queryParameters: q);

    // raw -> Map
    final raw = (res.data is Map)
        ? Map<String, dynamic>.from(res.data as Map)
        : <String, dynamic>{};

    // chuẩn hoá items thành List<Map<String, dynamic>>
    final items = <Map<String, dynamic>>[];
    final list = raw['items'];
    if (list is List) {
      for (final e in list) {
        if (e is Map) items.add(Map<String, dynamic>.from(e as Map));
      }
    }

    return {
      // khớp đúng key BE đang trả
      'opening': _toInt(raw['opening']),
      'income': _toInt(raw['income']),
      'expenses': _toInt(raw['expenses']),
      'closing': _toInt(raw['closing']),
      'items': items,
    };
  }

  /// GET /classes/{classId}/fund-account
  /// BE có thể trả trực tiếp {...} hoặc { fund_account: {...} }
  Future<Map<String, String>> getFundAccount({required int classId}) async {
    final res = await _dio.get(
      '/classes/$classId/fund-account',
      options: Options(receiveTimeout: const Duration(seconds: 15)),
    );

    final data = (res.data is Map)
        ? Map<String, dynamic>.from(res.data as Map)
        : <String, dynamic>{};

    final x = (data['fund_account'] is Map)
        ? Map<String, dynamic>.from(data['fund_account'] as Map)
        : data;

    return {
      'bank_code': (x['bank_code'] ?? '').toString(),
      'account_number': (x['account_number'] ?? '').toString(),
      'account_name': (x['account_name'] ?? '').toString(),
    };
  }

  /// PUT /classes/{classId}/fund-account
  Future<Map<String, String>> upsert({
    required int classId,
    required String bankCode,
    required String accountNumber,
    required String accountName,
  }) async {
    final res = await _dio.put(
      '/classes/$classId/fund-account',
      data: {
        'bank_code': bankCode,
        'account_number': accountNumber,
        'account_name': accountName,
      },
      options: Options(sendTimeout: const Duration(seconds: 15)),
    );

    final data = (res.data is Map)
        ? Map<String, dynamic>.from(res.data as Map)
        : <String, dynamic>{};

    final x = (data['fund_account'] is Map)
        ? Map<String, dynamic>.from(data['fund_account'] as Map)
        : <String, dynamic>{};

    return {
      'bank_code': (x['bank_code'] ?? '').toString(),
      'account_number': (x['account_number'] ?? '').toString(),
      'account_name': (x['account_name'] ?? '').toString(),
    };
  }

  /// GET /classes/{classId}/fund-account/summary
  /// Trả về { total_income, total_expense, balance } (int)
  /// Hỗ trợ filter: feeCycleId / from / to (YYYY-MM-DD)
  Future<Map<String, int>> getSummary({
    required int classId,
    int? feeCycleId,
    DateTime? from,
    DateTime? to,
  }) async {
    final q = <String, dynamic>{};
    if (feeCycleId != null) q['fee_cycle_id'] = feeCycleId;
    if (from != null) {
      q['from'] =
      '${from.year}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}';
    }
    if (to != null) {
      q['to'] =
      '${to.year}-${to.month.toString().padLeft(2, '0')}-${to.day.toString().padLeft(2, '0')}';
    }

    final res = await _dio.get(
      '/classes/$classId/fund-account/summary',
      queryParameters: q,
      options: Options(receiveTimeout: const Duration(seconds: 15)),
    );

    final data = (res.data is Map)
        ? Map<String, dynamic>.from(res.data as Map)
        : const <String, dynamic>{};

    return {
      'total_income': _toInt(data['total_income']),
      'total_expense': _toInt(data['total_expense']),
      'balance': _toInt(data['balance']),
    };
  }
}
