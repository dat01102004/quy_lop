import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SessionState {
  final String? token;
  final String? name;
  final String? email;
  final String? phone;
  final String? dob;
  final String? avatarUrl;
  final int? classId;
  final String? role;
  final bool hydrated;
  const SessionState({
    this.token,
    this.name,
    this.email,
    this.phone,
    this.dob,
    this.avatarUrl,
    this.classId,
    this.role,
    this.hydrated = false,
  });

  SessionState copyWith({
    String? token,
    String? name,
    String? email,
    String? phone,
    String? dob,
    String? avatarUrl,
    int? classId,
    String? role,
    bool? hydrated,
  }) {
    return SessionState(
      token: token ?? this.token,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      dob: dob ?? this.dob,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      classId: classId ?? this.classId,
      role: role ?? this.role,
      hydrated: hydrated ?? this.hydrated,
    );
  }
}
/// (Giữ lại nếu nơi khác còn dùng)
class Session {
  static String? token;
  static String baseUrl = "http://10.0.2.2:8000/api";
  static void clear() {
    token = null;
  }
}

class SessionNotifier extends Notifier<SessionState> {
  @override
  SessionState build() {
    _restore(); // async restore, không block
    return const SessionState();
  }

  Future<void> _restore() async {
    final sp = await SharedPreferences.getInstance();
    state = SessionState(
      token: sp.getString('token'),
      classId: sp.getInt('classId'),
      role: sp.getString('role'),
      name: sp.getString('name'),
      email: sp.getString('email'),
      phone: sp.getString('phone'),
      dob: sp.getString('dob'),
      avatarUrl: sp.getString('avatarUrl'),
      hydrated: true,
    );
  }

  Future<void> setToken(String t) async {
    state = state.copyWith(token: t);
    final sp = await SharedPreferences.getInstance();
    await sp.setString('token', t);
  }

  Future<void> setRole(String r) async {
    state = state.copyWith(role: r);
    final sp = await SharedPreferences.getInstance();
    await sp.setString('role', r);
  }

  Future<void> setClass(int id) async {
    state = state.copyWith(classId: id);
    final sp = await SharedPreferences.getInstance();
    await sp.setInt('classId', id);
  }

  /// ✅ Hàm mới: set cả classId và role cùng lúc
  Future<void> setClassInfo({
    required int classId,
    required String role,
  }) async {
    state = state.copyWith(classId: classId, role: role);

    final sp = await SharedPreferences.getInstance();
    await sp.setInt('classId', classId);
    await sp.setString('role', role);
  }

  Future<void> setUserFromProfileResponse(Map<String, dynamic> resp) async {
    final Map<String, dynamic> u =
    (resp['user'] ?? resp) as Map<String, dynamic>;

    final next = state.copyWith(
      name: u['name'] as String?,
      email: u['email'] as String?,
      phone: u['phone'] as String?,
      dob: u['dob'] as String?,
      avatarUrl: (resp['avatar_url'] ?? u['avatar_url']) as String?,
    );
    state = next;

    final sp = await SharedPreferences.getInstance();
    if (next.name != null) await sp.setString('name', next.name!);
    if (next.email != null) await sp.setString('email', next.email!);
    if (next.phone != null) await sp.setString('phone', next.phone!);
    if (next.dob != null) await sp.setString('dob', next.dob!);
    if (next.avatarUrl != null) await sp.setString('avatarUrl', next.avatarUrl!);
  }

  Future<void> setUserBasic({
    String? name,
    String? email,
    String? phone,
    String? dob,
    String? avatarUrl,
  }) async {
    final next = state.copyWith(
        name: name, email: email, phone: phone, dob: dob, avatarUrl: avatarUrl);
    state = next;
    final sp = await SharedPreferences.getInstance();
    if (name != null) await sp.setString('name', name);
    if (email != null) await sp.setString('email', email);
    if (phone != null) await sp.setString('phone', phone);
    if (dob != null) await sp.setString('dob', dob);
    if (avatarUrl != null) await sp.setString('avatarUrl', avatarUrl);
  }

  Future<void> logout() async {
    state = const SessionState();
    final sp = await SharedPreferences.getInstance();
    await sp.remove('token');
    await sp.remove('classId');
    await sp.remove('role');
    await sp.remove('name');
    await sp.remove('email');
    await sp.remove('phone');
    await sp.remove('dob');
    await sp.remove('avatarUrl');
  }
}

final sessionProvider =
NotifierProvider<SessionNotifier, SessionState>(SessionNotifier.new);
