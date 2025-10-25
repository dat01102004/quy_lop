import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/session.dart';
import '../repos/class_repository.dart';

class ClassManagementPage extends ConsumerStatefulWidget {
  const ClassManagementPage({super.key});
  @override
  ConsumerState<ClassManagementPage> createState() => _ClassManagementPageState();
}

class _ClassManagementPageState extends ConsumerState<ClassManagementPage> {
  List<Map<String, dynamic>> items = [];
  String? err;
  bool loading = true;

  Future<void> _load() async {
    setState(() { loading = true; err = null; });
    try {
      final list = await ref.read(classRepositoryProvider).myClasses();
      setState(() { items = list; loading = false; });
    } catch (e) {
      setState(() { err = '$e'; loading = false; });
    }
  }

  Future<void> _createClass() async {
    final nameCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Tạo lớp mới'),
        content: TextField(
          controller: nameCtl,
          decoration: const InputDecoration(labelText: 'Tên lớp'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Tạo')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final resp = await ref.read(classRepositoryProvider).createClass(nameCtl.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Đã tạo lớp: ${resp['class']['name']} — mã: ${resp['class']['code']}'),
      ));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider);
    final isOwner = (s.role == 'owner');

    return Scaffold(
      appBar: AppBar(title: const Text('Quản lý lớp')),
      floatingActionButton: isOwner
          ? FloatingActionButton.extended(
        onPressed: _createClass,
        icon: const Icon(Icons.add),
        label: const Text('Tạo lớp'),
      )
          : null,
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : err != null
          ? Center(child: Text(err!, style: const TextStyle(color: Colors.red)))
          : RefreshIndicator(
        onRefresh: _load,
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final c = items[i];
            return Card(
              child: ListTile(
                leading: const Icon(Icons.class_),
                title: Text(c['name']?.toString() ?? 'Lớp'),
                subtitle: Text('Mã: ${c['code'] ?? '-'} • Vai trò: ${c['role'] ?? '-'}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  // tuỳ bạn: mở dashboard lớp / invoices / fee cycles...
                  // ví dụ: Navigator.pushNamed(context, '/invoices', arguments: c['class_id']);
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
