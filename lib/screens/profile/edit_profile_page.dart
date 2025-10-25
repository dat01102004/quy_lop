import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../repos/profile_repository.dart';
import '../../services/session.dart';

class EditProfilePage extends ConsumerStatefulWidget {
  final Map<String, dynamic> initial;
  const EditProfilePage({super.key, required this.initial});
  @override
  ConsumerState<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends ConsumerState<EditProfilePage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  DateTime? _dob;
  File? _avatar;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // đảm bảo initial có đúng kiểu
    final initial = Map<String, dynamic>.from(widget.initial);
    _name.text  = (initial['name']  ?? '').toString();
    _email.text = (initial['email'] ?? '').toString();
    _phone.text = (initial['phone'] ?? '').toString();
    final dobStr = initial['dob']?.toString();
    if (dobStr != null && dobStr.isNotEmpty) {
      _dob = DateTime.tryParse(dobStr);
    }
  }

  Future<void> _pick() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x != null) setState(() => _avatar = File(x.path));
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(profileRepoProvider);
      final resp = await repo.updateMe(
        name: _name.text.trim().isEmpty ? null : _name.text.trim(),
        email: _email.text.trim().isEmpty ? null : _email.text.trim(),
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        dob: _dob != null ? _dob!.toIso8601String().substring(0, 10) : null,
        avatarFilePath: _avatar?.path,
      );

      // Cập nhật session để UI phản ánh ngay
      await ref.read(sessionProvider.notifier).setUserFromProfileResponse(resp);

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã cập nhật hồ sơ')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dobText = _dob == null ? 'Chưa đặt' : _dob!.toIso8601String().substring(0, 10);

    return Scaffold(
      appBar: AppBar(title: const Text('Chỉnh sửa thông tin')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: GestureDetector(
              onTap: _pick,
              child: CircleAvatar(
                radius: 36,
                backgroundImage: _avatar != null ? FileImage(_avatar!) : null,
                child: _avatar == null ? const Icon(Icons.camera_alt) : null,
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Họ tên')),
          const SizedBox(height: 8),
          TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email')),
          const SizedBox(height: 8),
          TextField(
            controller: _phone,
            decoration: const InputDecoration(labelText: 'Số điện thoại'),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Ngày sinh'),
            subtitle: Text(dobText),
            trailing: IconButton(
              icon: const Icon(Icons.date_range),
              onPressed: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _dob ?? DateTime(now.year - 18, now.month, now.day),
                  firstDate: DateTime(1900),
                  lastDate: DateTime(now.year, now.month, now.day),
                );
                if (picked != null) setState(() => _dob = picked);
              },
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Đang lưu...' : 'Lưu thay đổi'),
          ),
        ],
      ),
    );
  }
}
