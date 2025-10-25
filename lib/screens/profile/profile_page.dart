import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repos/profile_repository.dart';
import '../../services/session.dart';
import '../../services/network.dart';
import 'edit_profile_page.dart';
import 'change_password_page.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});
  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  Map<String, dynamic>? meRaw;
  Map<String, dynamic> user = const {};
  String? err;
  bool loading = true;

  // Hỗ trợ cả 2 dạng: { user:{...}, ... } hoặc { id,name,email,... }
  Map<String, dynamic> _normalizeUser(Map<String, dynamic> raw) {
    final hasUser = raw['user'] is Map;
    final Map<String, dynamic> u =
    hasUser ? Map<String, dynamic>.from(raw['user'] as Map) : {};
    if (!hasUser) return Map<String, dynamic>.from(raw);
    final Map<String, dynamic> flat = Map<String, dynamic>.from(raw)..remove('user');
    return {...u, ...flat};
  }

  Future<void> _load() async {
    if (mounted) setState(() {
      loading = true;
      err = null;
    });
    try {
      final data = await ref.read(profileRepoProvider).getMe();
      if (!mounted) return;
      setState(() {
        meRaw = data;
        user = _normalizeUser(data);
        loading = false;
      });
    } on DioException catch (e) {
      final msg = prettyDioError(e);
      if (!mounted) return;
      setState(() {
        err = msg;
        loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      if (!mounted) return;
      const msg = 'Không tải được thông tin tài khoản';
      setState(() {
        err = msg;
        loading = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(msg)));
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _initial(String? name) {
    final s = (name ?? '').trim();
    return s.isEmpty ? 'U' : s.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final roleLabel = switch (user['role'] ?? s.role) {
      'owner' => 'Owner',
      'treasurer' => 'Thủ quỹ',
      _ => 'Member',
    };

    // Nền gradient đồng bộ toàn app
    return Container(
      decoration: BoxDecoration(
        gradient: isDark
            ? const LinearGradient(
          colors: [Color(0xFF2F1156), Color(0xFF0F172A)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        )
            : const LinearGradient(
          colors: [Color(0xFFF2F5FF), Color(0xFFFFFFFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          scrolledUnderElevation: 0,
          backgroundColor: Colors.transparent,
          title: const Text('Thông tin tài khoản'),
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : err != null
            ? Center(
            child: Text(err!,
                style: const TextStyle(color: Colors.red)))
            : SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            child: Column(
              children: [
                // Card header: Avatar + name + email + role chip
                _GlassCard(
                  padding:
                  const EdgeInsets.fromLTRB(16, 18, 16, 18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .primaryContainer,
                        backgroundImage: (user['avatar_url'] != null &&
                            (user['avatar_url'] as String).isNotEmpty)
                            ? NetworkImage(
                          user['avatar_url'],
                        )
                            : null,
                        child: (user['avatar_url'] == null ||
                            (user['avatar_url'] as String).isEmpty)
                            ? Text(
                          _initial(
                              (user['name'] ?? s.name) as String?),
                          style: const TextStyle(
                              fontWeight: FontWeight.w800),
                        )
                            : null,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                          CrossAxisAlignment.start,
                          children: [
                            Text(
                              (user['name'] ?? s.name ?? '')
                                  .toString(),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                  fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              (user['email'] ?? s.email ?? '')
                                  .toString(),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outline),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primaryContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(roleLabel,
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Card chi tiết
                _GlassCard(
                  child: Column(
                    children: [
                      _InfoTile(
                        icon: Icons.mail_outline,
                        title: 'Email',
                        value: (user['email'] ?? s.email ?? '')
                            .toString(),
                      ),
                      const Divider(height: 1),
                      _InfoTile(
                        icon: Icons.phone_outlined,
                        title: 'Điện thoại',
                        value:
                        (user['phone'] ?? '').toString().isEmpty
                            ? '—'
                            : (user['phone']).toString(),
                      ),
                      const Divider(height: 1),
                      _InfoTile(
                        icon: Icons.cake_outlined,
                        title: 'Ngày sinh',
                        value:
                        (user['dob'] ?? user['dob_iso'] ?? '')
                            .toString()
                            .isEmpty
                            ? '—'
                            : (user['dob'] ??
                            user['dob_iso'])
                            .toString(),
                      ),
                      const Divider(height: 1),
                      _InfoTile(
                        icon: Icons.verified_user_outlined,
                        title: 'Vai trò',
                        value: roleLabel,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Thanh nút cố định dưới
        bottomNavigationBar: loading || err != null
            ? null
            : SafeArea(
          top: false,
          child: Padding(
            padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final initial =
                      Map<String, dynamic>.from(user);
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                EditProfilePage(initial: initial)),
                      );
                      _load(); // refresh lại
                    },
                    child: const Text('Chỉnh sửa thông tin'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ChangePasswordPage()),
                      );
                    },
                    child: const Text('Đổi mật khẩu'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ======= Widgets phụ =======

class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: cs.surface.withOpacity(.75),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: cs.outlineVariant.withOpacity(.25)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(.06),
                blurRadius: 12,
                offset: const Offset(0, 6),
              )
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      leading: Container(
        height: 36,
        width: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20),
      ),
      title: Text(title,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: cs.outline)),
      subtitle: Text(
        value,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
    );
  }
}
