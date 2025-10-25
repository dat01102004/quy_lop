import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api.dart';

final invoiceRepositoryProvider = Provider<InvoiceRepository>((ref) {
  return InvoiceRepository(ref.watch(dioProvider));
});

class InvoiceRepository {
  final Dio _dio;
  InvoiceRepository(this._dio);

  Future<List<Map<String, dynamic>>> myInvoices(int classId) async {
    final res = await _dio.get('/classes/$classId/my-invoices');
    final list = List<Map<String, dynamic>>.from(res.data);

    return list.map((json) {
      final feeCycle = json['fee_cycle'] as Map<String, dynamic>?;
      final id = json['id']?.toString() ?? '';
      final title = json['title'] ?? feeCycle?['name'] ?? 'Invoice #$id';
      return {...json, 'title': title};
    }).toList();
  }

  Future<Map<String, dynamic>> invoiceDetail(int classId, int invoiceId) async {
    final res = await _dio.get('/classes/$classId/invoices/$invoiceId');
    final json = Map<String, dynamic>.from(res.data);
    final feeCycle = json['fee_cycle'] as Map<String, dynamic>?;
    final id = json['id']?.toString() ?? '';
    final title = json['title'] ?? feeCycle?['name'] ?? 'Invoice #$id';
    return {...json, 'title': title};
  }

  /// Danh sách thành viên chưa nộp theo kỳ
  Future<Map<String, dynamic>> unpaidMembers({
    required int classId,
    required int cycleId,
  }) async {
    // Dio từ dioProvider đã có Authorization header sẵn
    final res = await _dio.get(
      '/classes/$classId/fee-cycles/$cycleId/unpaid-members',
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Gửi phiếu nộp + (tuỳ chọn) upload ảnh minh chứng
  Future<Map<String, dynamic>> submitPayment({
    required int classId,
    required int invoiceId,
    required int amount,
    required String method,
    File? proofImage,
  }) async {
    // 1) tạo payment
    final res = await _dio.post(
      '/classes/$classId/invoices/$invoiceId/payments',
      data: {'amount': amount, 'method': method},
    );

    Map<String, dynamic> p =
    (res.data is Map && res.data['payment'] is Map)
        ? Map<String, dynamic>.from(res.data['payment'])
        : Map<String, dynamic>.from(res.data as Map);

    // 2) có ảnh -> upload
    if (proofImage != null) {
      final form = FormData.fromMap({
        'image': await MultipartFile.fromFile(proofImage.path),
      });

      final up = await _dio.post(
        '/classes/$classId/payments/${p['id']}/proof',
        data: form,
        options: Options(contentType: 'multipart/form-data'),
      );

      p = (up.data is Map && up.data['payment'] is Map)
          ? Map<String, dynamic>.from(up.data['payment'])
          : Map<String, dynamic>.from(up.data as Map);
    }

    return p;
  }
}
