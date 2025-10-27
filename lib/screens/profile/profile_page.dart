import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repos/profile_repository.dart';
import '../../repos/auth_repository.dart';
import '../../services/session.dart';
import '../../services/network.dart';
import '../../services/app_settings.dart';
import '../../theme/app_theme.dart';

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
    final session = ref.watch(sessionProvider);

    final settings = ref.watch(appSettingsProvider);
    final settingsCtl = ref.read(appSettingsProvider.notifier);

    final cs = Theme.of(context).colorScheme;
    final bg = Theme.of(context).extension<AppGradients>()!.background;

    final roleLabel = switch (user['role'] ?? session.role) {
      'owner' => 'Owner',
      'treasurer' => 'Thủ quỹ',
      _ => 'Member',
    };

    return Container(
      decoration: BoxDecoration(gradient: bg),
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
          child: Text(
            err!,
            style: const TextStyle(color: Colors.red),
          ),
        )
            : SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            child: Column(
              children: [
                // ===== Header =====
                _GlassCard(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: cs.primaryContainer,
                        backgroundImage: (user['avatar_url'] != null &&
                            (user['avatar_url'] as String).isNotEmpty)
                            ? NetworkImage(user['avatar_url'])
                            : null,
                        child: (user['avatar_url'] == null ||
                            (user['avatar_url'] as String).isEmpty)
                            ? Text(
                          _initial((user['name'] ?? session.name) as String?),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        )
                            : null,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (user['name'] ?? session.name ?? '').toString(),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              (user['email'] ?? session.email ?? '').toString(),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: cs.outline),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(roleLabel,
                            style: Theme.of(context).textTheme.labelMedium),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // ===== Info card =====
                _GlassCard(
                  child: Column(
                    children: [
                      _InfoTile(
                        icon: Icons.mail_outline,
                        title: 'Email',
                        value: (user['email'] ?? session.email ?? '').toString(),
                      ),
                      const Divider(height: 1),
                      _InfoTile(
                        icon: Icons.phone_outlined,
                        title: 'Điện thoại',
                        value: (() {
                          final v = (user['phone'] ?? '').toString();
                          return v.isEmpty ? '—' : v;
                        })(),
                      ),
                      const Divider(height: 1),
                      _InfoTile(
                        icon: Icons.cake_outlined,
                        title: 'Ngày sinh',
                        value: (() {
                          final v = (user['dob'] ?? user['dob_iso'] ?? '').toString();
                          return v.isEmpty ? '—' : v;
                        })(),
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
                const SizedBox(height: 14),

                // ===== Settings card =====
                _GlassCard(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cài đặt',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),

                      // Màu seed
                      _SettingRow(
                        icon: Icons.palette_outlined,
                        title: 'Màu sắc',
                        trailing: Wrap(
                          spacing: 10,
                          children: [
                            for (final c in _seedChoices)
                              _ColorDot(
                                color: c,
                                selected: settings.seed == c.value,
                                onTap: () => settingsCtl.setSeed(c),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Giao diện
                      _SettingRow(
                        icon: Icons.brightness_6_outlined,
                        title: 'Giao diện',
                        trailing: SizedBox(
                          height: 38,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SegmentedButton<ThemeMode>(
                              segments: const [
                                ButtonSegment(
                                    value: ThemeMode.light, label: Text('Sáng')),
                                ButtonSegment(
                                    value: ThemeMode.system, label: Text('Hệ thống')),
                                ButtonSegment(
                                    value: ThemeMode.dark, label: Text('Tối')),
                              ],
                              selected: {settings.mode},
                              onSelectionChanged: (s) =>
                                  settingsCtl.setMode(s.first),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),



                      // Cỡ chữ
                      _SettingRow(
                        icon: Icons.text_fields_outlined,
                        title: 'Cỡ chữ',
                        trailing: SizedBox(
                          width: 180,
                          child: Slider(
                            value: settings.textScale,
                            onChanged: (v) => settingsCtl.setTextScale(v),
                            min: .9,
                            max: 1.3,
                            divisions: 8,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // ===== Bottom buttons =====
        bottomNavigationBar: loading || err != null
            ? null
            : SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final initial = Map<String, dynamic>.from(user);
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => EditProfilePage(initial: initial)),
                          );
                          _load();
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
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.logout),
                    label: const Text('Đăng xuất'),
                    onPressed: () async {
                      await ref.read(authRepositoryProvider).logout();
                      if (!mounted) return;
                      Navigator.of(context)
                          .pushNamedAndRemoveUntil('/login', (r) => false);
                    },
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

class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _GlassCard({required this.child, this.padding = const EdgeInsets.all(16)});

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
  const _InfoTile({required this.icon, required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      leading: Container(
        height: 36,
        width: 36,
        alignment: Alignment.center,
        decoration:
        BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 20),
      ),
      title: Text(
        title,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.outline),
      ),
      subtitle: Text(
        value,
        style:
        Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget trailing;

  /// Ép xuống dòng (control ở dòng dưới). Mặc định = true để thoáng.
  final bool forceWrap;

  const _SettingRow({
    required this.icon,
    required this.title,
    required this.trailing,
    this.forceWrap = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget iconBox() => Container(
      height: 36,
      width: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 20),
    );

    final titleWidget =
    Text(title, style: Theme.of(context).textTheme.bodyLarge);

    if (forceWrap) {
      // ⤵️ Xuống dòng: nhãn ở trên, control ở dưới (full width)
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [iconBox(), const SizedBox(width: 10), titleWidget]),
            const SizedBox(height: 10),
            trailing,
          ],
        ),
      );
    } else {
      // Cùng một dòng (nếu bạn muốn dùng lại ở nơi khác)
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            iconBox(),
            const SizedBox(width: 10),
            titleWidget,
            const SizedBox(width: 8),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: trailing,
                ),
              ),
            ),
          ],
        ),
      );
    }
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _ColorDot({required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        height: 26,
        width: 26,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
            width: selected ? 2 : 1,
          ),
        ),
      ),
    );
  }
}

const _seedChoices = <Color>[
  Color(0xFF6D4BF1), // purple
  Color(0xFFEC4899), // pink
  Color(0xFF3B82F6), // blue
  Color(0xFF10B981), // emerald
  Color(0xFFF59E0B), // amber
  Color(0xFF6B7280), // gray

];
