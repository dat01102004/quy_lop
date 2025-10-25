import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/session.dart';
import '../services/dio_provider.dart';

final classRepositoryProvider = Provider<ClassRepository>((ref) {
  final dio = ref.read(dioProvider);
  return ClassRepository(ref, dio);
});

class ClassRepository {
  final Ref ref;
  final Dio _dio;
  ClassRepository(this.ref, this._dio);

  Options _auth() => Options(
    headers: {
      'Authorization': 'Bearer ${ref.read(sessionProvider).token}',
    },
  );

  /// Danh sách lớp của tôi
  Future<List<Map<String, dynamic>>> myClasses() async {
    final res = await _dio.get('/classes', options: _auth());
    final data =
    (res.data is Map) ? Map<String, dynamic>.from(res.data) : <String, dynamic>{};

    final list = List<Map<String, dynamic>>.from(
      (data['classes'] as List? ?? const []).map(
            (e) => Map<String, dynamic>.from(e as Map),
      ),
    );
    return list;
  }

  /// Tạo lớp mới (mọi role đều được phép theo BE bạn đã sửa)
  /// -> cập nhật ngay session.classId + session.role để dùng liền
  Future<Map<String, dynamic>> createClass(String name) async {
    final res = await _dio.post(
      '/classes',
      data: {'name': name},
      options: _auth(),
    );

    final data = (res.data is Map) ? Map<String, dynamic>.from(res.data) : <String, dynamic>{};
    final cls  = Map<String, dynamic>.from(data['class'] ?? {});
    final role = (data['role'] ?? 'owner').toString();

    // Lấy ID lớp (int hoặc string)
    final idAny = cls['id'];
    final classId =
    idAny is int ? idAny : int.tryParse(idAny?.toString() ?? '');

    if (classId != null) {
      // ✅ cập nhật session: classId + role
      await ref.read(sessionProvider.notifier).setClassInfo(
        classId: classId,
        role: role,
      );
    }

    return {
      'class': cls,
      'role': role,
    };
  }

  /// (Giữ để tương thích cũ) Lấy số dư lớp từ endpoint cũ nếu còn dùng
  Future<num?> getBalance(int classId) async {
    final res = await _dio.get('/classes/$classId/balance', options: _auth());
    final data = (res.data is Map) ? Map<String, dynamic>.from(res.data) : {};
    final bal = data['balance'];
    if (bal is num) return bal;
    if (bal is String) return num.tryParse(bal);
    return null;
  }

  /// Danh sách thành viên lớp
  Future<List<Map<String, dynamic>>> listMembers(int classId) async {
    final res = await _dio.get('/classes/$classId/members', options: _auth());
    final data = (res.data is Map) ? Map<String, dynamic>.from(res.data) : {};
    return List<Map<String, dynamic>>.from(
      (data['members'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)),
    );
  }

  /// Set role cho 1 user trong lớp
  Future<void> setRole({
    required int classId,
    required int userId,
    required String role, // 'member' | 'treasurer'
  }) async {
    await _dio.post(
      '/classes/$classId/members/$userId/role',
      data: {'role': role},
      options: _auth(),
    );
  }

  /// Chuyển quyền owner
  Future<void> transferOwnership({
    required int classId,
    required int userId,
  }) async {
    await _dio.post('/classes/$classId/transfer-ownership/$userId', options: _auth());
  }

  /// Join bằng mã lớp -> cập nhật session.classId + session.role
  Future<Map<String, dynamic>> joinByCode(String code) async {
    final res = await _dio.post(
      '/classes/join',
      data: {'code': code},
      options: _auth(),
    );

    final data =
    (res.data is Map) ? Map<String, dynamic>.from(res.data) : <String, dynamic>{};
    final cls  = Map<String, dynamic>.from(data['class'] ?? {});
    final role = (data['role'] ?? 'member').toString();

    final idAny = cls['id'];
    final classId =
    idAny is int ? idAny : int.tryParse(idAny?.toString() ?? '');

    if (classId != null) {
      await ref.read(sessionProvider.notifier).setClassInfo(
        classId: classId,
        role: role,
      );
    }

    // kỳ vọng BE trả: { class: {...}, role: '...' }
    return data;
  }
}
