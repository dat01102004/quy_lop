import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repos/class_repository.dart';
import '../services/session.dart';
import '../services/network.dart';
class ClassMembersPage extends ConsumerStatefulWidget {
  final int classId;
  const ClassMembersPage({super.key, required this.classId});

  @override
  ConsumerState<ClassMembersPage> createState() => _ClassMembersPageState();
}

class _ClassMembersPageState extends ConsumerState<ClassMembersPage> {
  List<Map<String, dynamic>> _members = [];
  String? _err;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _iAmOwner => (ref.read(sessionProvider).role == 'owner');

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _err = null;
      });
    }
    try {
      final list = await ref.read(classRepositoryProvider).listMembers(widget.classId);
      if (!mounted) return;
      setState(() => _members = list);
    } on DioException catch (e) {
      final msg = prettyDioError(e); // 👈 dùng helper
      if (!mounted) return;
      setState(() => _err = msg);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      const msg = 'Không tải được danh sách thành viên';
      setState(() => _err = msg);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setRole(int userId, String role) async {
    try {
      await ref.read(classRepositoryProvider).setRole(
        classId: widget.classId,
        userId: userId,
        role: role,
      );
      await _load(); // reload danh sách để sync
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã đặt quyền: $role')),
      );
    } on DioException catch (e) {
      final msg = prettyDioError(e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $msg')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Đặt quyền thất bại')));
    }
  }

  Future<void> _transferOwner(int userId, String userName) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận chuyển Owner'),
        content: Text('Chuyển Owner cho "$userName"? Bạn sẽ thành Thủ quỹ.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Chuyển')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await ref.read(classRepositoryProvider).transferOwnership(
        classId: widget.classId,
        userId: userId,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Đã chuyển Owner')));
    } on DioException catch (e) {
      final msg = prettyDioError(e); // 👈 dùng helper
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $msg')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Chuyển Owner thất bại')));
    }
  }

  void _openActions(Map<String, dynamic> m) {
    if (!_iAmOwner) return;

    final userId = (m['user_id'] ?? m['id']);
    if (userId == null) return;
    final uid = userId is int ? userId : int.tryParse(userId.toString()) ?? -1;
    final currentRole = (m['role'] ?? 'member').toString();
    final name = (m['name'] ?? 'Người dùng').toString();

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.person),
                title: Text(name),
                subtitle: Text(m['email']?.toString() ?? ''),
                trailing: Chip(label: Text(currentRole)),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('Đặt quyền Member'),
                onTap: () async {
                  Navigator.pop(context);
                  await _setRole(uid, 'member');
                },
              ),
              ListTile(
                leading: const Icon(Icons.verified_user_outlined),
                title: const Text('Đặt quyền Thủ quỹ'),
                onTap: () async {
                  Navigator.pop(context);
                  await _setRole(uid, 'treasurer');
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.workspace_premium_outlined),
                title: const Text('Chuyển Owner'),
                subtitle: const Text('Owner hiện tại sẽ thành Thủ quỹ'),
                onTap: () async {
                  Navigator.pop(context);
                  await _transferOwner(uid, name);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Thành viên lớp')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            if (_err != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_err!, style: const TextStyle(color: Colors.red)),
              ),
            if (_members.isEmpty)
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Chưa có thành viên'),
                ),
              ),
            ..._members.map((m) {
              final name = (m['name'] ?? '').toString();
              final email = (m['email'] ?? '').toString();
              final role = (m['role'] ?? 'member').toString();
              final isOwner = role == 'owner';

              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text((name.isEmpty ? '?' : name[0]).toUpperCase()),
                  ),
                  title: Text(name.isEmpty ? 'User #${m['user_id'] ?? m['id']}' : name),
                  subtitle: Text(email),
                  trailing: Chip(
                    label: Text(
                      isOwner
                          ? 'Owner'
                          : role == 'treasurer'
                          ? 'Thủ quỹ'
                          : 'Thành viên',
                    ),
                  ),
                  // chỉ Owner mới mở sheet hành động
                  onTap: _iAmOwner ? () => _openActions(m) : null,
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
