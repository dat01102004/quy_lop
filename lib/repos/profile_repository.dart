import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/session.dart';
import 'package:quylop/env.dart';

final profileRepoProvider = Provider<ProfileRepository>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: Env.apiBase, // ví dụ: http://10.0.2.2:8000/api
    headers: {'Accept': 'application/json'},
    followRedirects: false,
    validateStatus: (s) => s != null && s < 400, // đọc được body nếu 4xx
  ));
  return ProfileRepository(ref, dio);
});

class ProfileRepository {
  final Ref ref;
  final Dio _dio;
  ProfileRepository(this.ref, this._dio);

  Options _auth() {
    final token = ref.read(sessionProvider).token;
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  Future<Map<String, dynamic>> getMe() async {
    final res = await _dio.get('/me', options: _auth());
    if (res.data is Map) {
      return Map<String, dynamic>.from(res.data as Map);
    }
    throw Exception('Unexpected /me response');
  }

  Future<Map<String, dynamic>> updateMe({
    String? name,
    String? email,
    String? phone,
    String? dob,            // yyyy-MM-dd
    String? avatarFilePath, // nếu upload ảnh
  }) async {
    Response res;
    if (avatarFilePath != null) {
      final form = FormData.fromMap({
        if (name != null) 'name': name,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
        if (dob != null) 'dob': dob,
        'avatar': await MultipartFile.fromFile(avatarFilePath),
      });
      try {
        res = await _dio.put('/me', data: form, options: _auth());
      } on DioException {
        // fallback khi server không cho PUT multipart
        form.fields.add(const MapEntry('_method', 'PUT'));
        res = await _dio.post('/me', data: form, options: _auth());
      }
    } else {
      res = await _dio.put('/me', data: {
        if (name != null) 'name': name,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
        if (dob != null) 'dob': dob,
      }, options: _auth());
    }
    if (res.data is Map) {
      return Map<String, dynamic>.from(res.data as Map);
    }
    throw Exception('Unexpected /me (update) response');
  }

  Future<String> changePassword({
    required String current,
    required String newPass,
    String? confirm,
  }) async {
    final body = {
      'current_password': current,
      'new_password': newPass,
      if (confirm != null) 'new_password_confirmation': confirm,
    };
    final res = await _dio.put('/me/password', data: body, options: _auth());
    if (res.data is Map && (res.data as Map)['message'] != null) {
      return (res.data as Map)['message'] as String;
    }
    return 'OK';
  }
}
