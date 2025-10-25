import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repos/profile_repository.dart';

class ChangePasswordPage extends ConsumerStatefulWidget {
  const ChangePasswordPage({super.key});
  @override
  ConsumerState<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends ConsumerState<ChangePasswordPage> {
  final _current = TextEditingController();
  final _new1 = TextEditingController();
  final _new2 = TextEditingController();
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    if (_new1.text != _new2.text) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Mật khẩu mới không khớp')));
      return;
    }
    setState(() => _saving = true);
    try {
      final msg = await ref
          .read(profileRepoProvider)
          .changePassword(current: _current.text, newPass: _new1.text, confirm: _new2.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Đổi mật khẩu')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(controller: _current, decoration: const InputDecoration(labelText: 'Mật khẩu hiện tại'), obscureText: true),
            const SizedBox(height: 8),
            TextField(controller: _new1, decoration: const InputDecoration(labelText: 'Mật khẩu mới'), obscureText: true),
            const SizedBox(height: 8),
            TextField(controller: _new2, decoration: const InputDecoration(labelText: 'Nhập lại mật khẩu mới'), obscureText: true),
            const Spacer(),
            FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Đang lưu...' : 'Lưu')),
          ],
        ),
      ),
    );
  }
}
