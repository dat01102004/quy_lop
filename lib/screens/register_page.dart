import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../repos/auth_repository.dart';
import '../services/network.dart';

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _nameCtl = TextEditingController();
  final _emailCtl = TextEditingController();
  final _passCtl = TextEditingController();
  final _pass2Ctl = TextEditingController();
  final _phoneCtl = TextEditingController();
  final _dobCtl = TextEditingController(); // yyyy-MM-dd

  final _formKey = GlobalKey<FormState>();

  bool _loading = false;
  bool _obscure1 = true;
  bool _obscure2 = true;
  String? _err;

  @override
  void dispose() {
    _nameCtl.dispose();
    _emailCtl.dispose();
    _passCtl.dispose();
    _pass2Ctl.dispose();
    _phoneCtl.dispose();
    _dobCtl.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final first = DateTime(now.year - 80, 1, 1);
    final last = DateTime(now.year + 1, 12, 31);
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 18, now.month, now.day),
      firstDate: first,
      lastDate: last,
    );
    if (picked != null) {
      _dobCtl.text =
      "${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      setState(() {});
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameCtl.text.trim();
    final email = _emailCtl.text.trim();
    final pass = _passCtl.text;
    final pass2 = _pass2Ctl.text;
    final phone = _phoneCtl.text.trim();
    final dob = _dobCtl.text.trim();

    setState(() {
      _loading = true;
      _err = null;
    });

    try {
      await ref.read(authRepositoryProvider).register(
        name: name,
        email: email,
        password: pass,
        passwordConfirmation: pass2,
        phone: phone.isEmpty ? null : phone,
        dobIso: dob.isEmpty ? null : dob,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đăng ký thành công')),
      );
      Navigator.of(context).pushNamedAndRemoveUntil('/', (r) => false);
    } on DioException catch (e) {
      final msg = prettyDioError(e);
      if (!mounted) return;
      setState(() => _err = msg);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      if (!mounted) return;
      const msg = 'Đăng ký thất bại';
      setState(() => _err = msg);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

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
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header / Branding
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Container(
                        //   height: 44,
                        //   width: 44,
                        //   alignment: Alignment.center,
                        //   decoration: BoxDecoration(
                        //     color: cs.primaryContainer,
                        //     borderRadius: BorderRadius.circular(12),
                        //   ),
                        //   child: const Icon(Icons.person_add_alt_1_outlined),
                        // ),
                        const SizedBox(width: 12),
                        Text(
                          'Tạo tài khoản',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    _GlassCard(
                      padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
                      child: AutofillGroup(
                        child: Form(
                          key: _formKey,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Họ tên
                              TextFormField(
                                controller: _nameCtl,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.name],
                                decoration: _inputDecoration(
                                  context,
                                  label: 'Họ tên',
                                  prefix: const Icon(Icons.badge_outlined),
                                ),
                                validator: (v) =>
                                (v == null || v.trim().isEmpty) ? 'Vui lòng nhập họ tên' : null,
                              ),
                              const SizedBox(height: 12),

                              // Email
                              TextFormField(
                                controller: _emailCtl,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.username, AutofillHints.email],
                                decoration: _inputDecoration(
                                  context,
                                  label: 'Email',
                                  hint: 'you@gmail.com',
                                  prefix: const Icon(Icons.mail_outline),
                                ),
                                validator: (v) {
                                  final s = (v ?? '').trim();
                                  if (s.isEmpty) return 'Vui lòng nhập email';
                                  final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s);
                                  if (!ok) return 'Email không hợp lệ';
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),

                              // Mật khẩu
                              TextFormField(
                                controller: _passCtl,
                                obscureText: _obscure1,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.newPassword],
                                decoration: _inputDecoration(
                                  context,
                                  label: 'Mật khẩu (tối thiểu 6 ký tự)',
                                  prefix: const Icon(Icons.lock_outline),
                                  suffix: IconButton(
                                    onPressed: () => setState(() => _obscure1 = !_obscure1),
                                    icon: Icon(_obscure1 ? Icons.visibility_off : Icons.visibility),
                                  ),
                                ),
                                validator: (v) =>
                                (v == null || v.length < 6) ? 'Mật khẩu tối thiểu 6 ký tự' : null,
                              ),
                              const SizedBox(height: 12),

                              // Xác nhận mật khẩu
                              TextFormField(
                                controller: _pass2Ctl,
                                obscureText: _obscure2,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.newPassword],
                                decoration: _inputDecoration(
                                  context,
                                  label: 'Xác nhận mật khẩu',
                                  prefix: const Icon(Icons.verified_user_outlined),
                                  suffix: IconButton(
                                    onPressed: () => setState(() => _obscure2 = !_obscure2),
                                    icon: Icon(_obscure2 ? Icons.visibility_off : Icons.visibility),
                                  ),
                                ),
                                validator: (v) =>
                                (v ?? '') != _passCtl.text ? 'Xác nhận mật khẩu không khớp' : null,
                              ),
                              const SizedBox(height: 12),

                              // Điện thoại (không bắt buộc)
                              TextFormField(
                                controller: _phoneCtl,
                                keyboardType: TextInputType.phone,
                                textInputAction: TextInputAction.next,
                                decoration: _inputDecoration(
                                  context,
                                  label: 'Điện thoại (không bắt buộc)',
                                  prefix: const Icon(Icons.phone_outlined),
                                ),
                                validator: (v) {
                                  final s = (v ?? '').trim();
                                  if (s.isEmpty) return null;
                                  final ok = RegExp(r'^[0-9 +().-]{8,}$').hasMatch(s);
                                  if (!ok) return 'Số điện thoại chưa đúng';
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),

                              // Ngày sinh (không bắt buộc)
                              TextFormField(
                                controller: _dobCtl,
                                readOnly: true,
                                onTap: _pickDob,
                                decoration: _inputDecoration(
                                  context,
                                  label: 'Ngày sinh (không bắt buộc)',
                                  prefix: const Icon(Icons.cake_outlined),
                                  suffix: IconButton(
                                    onPressed: _pickDob,
                                    icon: const Icon(Icons.calendar_month_outlined),
                                  ),
                                ),
                              ),

                              if (_err != null) ...[
                                const SizedBox(height: 10),
                                Text(_err!, style: const TextStyle(color: Colors.red)),
                              ],

                              const SizedBox(height: 14),
                              SizedBox(
                                height: 48,
                                child: FilledButton(
                                  onPressed: _loading ? null : _submit,
                                  child: _loading
                                      ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                      : const Text('Tạo tài khoản'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),
                    Center(
                      child: TextButton.icon(
                        onPressed: _loading ? null : () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Quay lại đăng nhập'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ====== UI helpers ======
  InputDecoration _inputDecoration(
      BuildContext context, {
        required String label,
        String? hint,
        Widget? prefix,
        Widget? suffix,
      }) {
    final cs = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(16);
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefix,
      suffixIcon: suffix,
      isDense: true,
      filled: true,
      fillColor: cs.surface.withOpacity(.70),
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: cs.primary.withOpacity(.45), width: 1.2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }
}

/// Glass container dùng lại như Login/Home
class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _GlassCard({required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: cs.surface.withOpacity(.75),
            borderRadius: BorderRadius.circular(22),
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
