import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/dio_provider.dart';
import '../services/session.dart';
import '../env.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    ref.watch(dioProvider),
    ref.read(sessionProvider.notifier),
  );
});

class AuthRepository {
  final Dio _dio;
  final SessionNotifier _session;

  AuthRepository(this._dio, this._session);

  /// ======= Public APIs =======
  Future<void> hydrateAfterStartup() async {
    try {
      // Đọc state hiện tại từ SessionNotifier
      final st = _session.state; // không cần await
      final hasToken = st.token != null && st.token!.isNotEmpty;
      final missingClass = st.classId == null || st.classId == 0;
      final missingRole  = st.role == null || st.role!.isEmpty;

      if (hasToken && (missingClass || missingRole)) {
        await _hydrateClassFromServer(); // đã có sẵn ở file của bạn
      }
    } catch (_) {
      // im lặng để không chặn luồng khởi động
    }
  }
  /// Đăng nhập
  Future<void> login(String email, String password) async {
    final res = await _dio.post(
      '${Env.authPrefix}/login',
      data: {'email': email, 'password': password},
    );

    await _afterAuthPayload(res.data);
  }

  /// Đăng ký
  Future<void> register({
    required String name,
    required String email,
    required String password,
    String? passwordConfirmation,
    String? phone,
    String? dobIso, // yyyy-MM-dd
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'email': email,
      'password': password,
      'password_confirmation': passwordConfirmation ?? password,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      if (dobIso != null && dobIso.isNotEmpty) 'dob': dobIso,
    };

    final res = await _dio.post('${Env.authPrefix}/register', data: body);
    await _afterAuthPayload(res.data);
  }

  /// Lấy thông tin người dùng hiện tại
  Future<Map<String, dynamic>> me() async {
    final res = await _dio.get('/me');
    final map = Map<String, dynamic>.from(res.data);
    await _session.setUserFromProfileResponse(map);
    return map;
  }

  /// Đăng xuất
  Future<void> logout() async {
    try {
      await _dio.post('/logout');
    } catch (_) {
      // bỏ qua lỗi mạng khi logout
    }
    await _session.logout();
  }

  /// ======= Private helpers =======

  /// Xử lý payload sau đăng nhập/đăng ký:
  /// - Lưu token
  /// - Lưu basic user
  /// - Thiết lập class/role nếu có trong payload
  /// - Nếu thiếu -> hydrate từ server
  Future<void> _afterAuthPayload(dynamic raw) async {
    final data = _asMap(raw);

    // 1) Token
    final token = data['token']?.toString();
    if (token == null || token.isEmpty) {
      throw DioException(
        requestOptions: RequestOptions(path: '${Env.authPrefix}/login'),
        type: DioExceptionType.badResponse,
        error: 'Missing token in response',
      );
    }
    await _session.setToken(token);

    // 2) User basic (nếu có)
    final user = _asMap(data['user']);
    if (user.isNotEmpty) {
      await _session.setUserBasic(
        name: user['name'] as String?,
        email: user['email'] as String?,
        phone: user['phone'] as String?,
        dob: user['dob'] as String?,
        avatarUrl: user['avatar_url'] as String?,
      );
      // Một số BE có field role ở user (không theo lớp)
      final userRole = user['role']?.toString();
      if (userRole != null && userRole.isNotEmpty) {
        await _session.setRole(userRole);
      }
    }

    // 3) Class/role từ root payload (nếu BE trả kèm)
    final rootClassId = _asInt(data['class_id'] ?? data['default_class_id']);
    final rootRole = data['role']?.toString() ?? data['role_in_class']?.toString();
    if (rootClassId != null) {
      await _session.setClass(rootClassId);
    }
    if (rootRole != null && rootRole.isNotEmpty) {
      await _session.setRole(rootRole);
    }

    // 4) Nếu sau các bước trên vẫn thiếu class hoặc role -> hydrate
    final hasClass = (await _session.state).classId != null;
    final hasRole = (await _session.state).role != null && (await _session.state).role!.isNotEmpty;

    if (!hasClass || !hasRole) {
      await _hydrateClassFromServer();
    }
  }

  /// Lấy danh sách lớp user tham gia và chọn 1 lớp đang active.
  /// Phù hợp với nhiều dạng response:
  /// - List<dynamic> [{"id":1,"role":"owner",...}]
  /// - Map {"classes":[...]} hoặc {"data":[...]} ...
  Future<void> _hydrateClassFromServer() async {
    try {
      final res = await _dio.get('/classes');

      // Chuẩn hoá về List<Map<String,dynamic>>
      final list = _extractClassList(res.data);
      if (list.isEmpty) return;

      // Ưu tiên lớp có member_status == active (nếu không có thì lấy phần tử đầu)
      Map<String, dynamic> picked = list.first;
      for (final c in list) {
        final status = (c['member_status'] ?? c['status'] ?? 'active').toString();
        if (status == 'active') {
          picked = c;
          break;
        }
      }

      final cid = _asInt(picked['id'] ?? picked['class_id']);
      final role = (picked['role'] ?? picked['pivot_role'] ?? 'member').toString();

      if (cid != null) {
        await _session.setClass(cid);
      }
      if (role.isNotEmpty) {
        await _session.setRole(role);
      }
    } catch (_) {
      // im lặng để không chặn luồng đăng nhập/đăng ký
    }
  }

  /// ======= Parsing utilities =======

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    return <String, dynamic>{};
  }

  int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return int.tryParse(s);
  }

  /// Trích danh sách lớp từ mọi kiểu payload thường gặp
  List<Map<String, dynamic>> _extractClassList(dynamic raw) {
    if (raw is List) {
      return raw.map((e) => _asMap(e)).toList();
    }
    final map = _asMap(raw);
    // Các key có thể gặp: classes, data, items, results
    final candidates = [
      map['classes'],
      map['data'],
      map['items'],
      map['results'],
    ].where((e) => e != null).toList();

    if (candidates.isEmpty) return const [];
    final first = candidates.first;
    if (first is List) {
      return first.map((e) => _asMap(e)).toList();
    }
    return const [];
  }
}
