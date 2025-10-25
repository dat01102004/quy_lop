// lib/screens/class_list_page.dart
import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repos/class_repository.dart';
import '../services/session.dart';
import '../services/network.dart';

class ClassListPage extends ConsumerStatefulWidget {
  const ClassListPage({super.key});

  @override
  ConsumerState<ClassListPage> createState() => _ClassListPageState();
}

class _ClassListPageState extends ConsumerState<ClassListPage> {
  List<Map<String, dynamic>> _classes = [];
  String? _err;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _err = null;
      });
    }
    try {
      final list = await ref.read(classRepositoryProvider).myClasses();
      if (!mounted) return;
      setState(() => _classes = list);
    } on DioException catch (e) {
      final msg = prettyDioError(e);
      if (!mounted) return;
      setState(() => _err = msg);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      if (!mounted) return;
      const msg = 'Không tải được danh sách lớp';
      setState(() => _err = msg);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectClass(Map<String, dynamic> c) async {
    final classIdAny = c['id'] ?? c['class_id'];
    if (classIdAny == null) return;

    final role = (c['role'] ?? 'member').toString();
    final notifier = ref.read(sessionProvider.notifier);

    if (classIdAny is int) {
      await notifier.setClass(classIdAny);
    } else {
      final idInt = int.tryParse(classIdAny.toString());
      if (idInt != null) await notifier.setClass(idInt);
    }
    await notifier.setRole(role);

    if (!mounted) return;
    Navigator.of(context).pop(c);
  }

  void _copyToClipboard(BuildContext context, String text, {String? msg}) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(msg ?? 'Đã sao chép: $text'), duration: const Duration(seconds: 1)),
      );
  }

  Future<void> _createClassDialog() async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tạo lớp'),
        content: TextField(
          controller: ctl,
          decoration: const InputDecoration(
            labelText: 'Tên lớp',
            hintText: 'VD: CNTT K25',
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => Navigator.of(ctx).pop(true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Tạo')),
        ],
      ),
    );

    if (ok != true) return;
    final name = ctl.text.trim();
    if (name.isEmpty) return;

    try {
      final res = await ref.read(classRepositoryProvider).createClass(name);
      final Map<String, dynamic> cls =
      (res['class'] is Map) ? Map<String, dynamic>.from(res['class']) : Map<String, dynamic>.from(res);

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (ctx) {
          final code = (cls['code'] ?? '').toString();
          return AlertDialog(
            title: const Text('Tạo lớp thành công'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tên lớp: ${cls['name'] ?? '-'}'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Mã lớp: ', style: TextStyle(fontWeight: FontWeight.w600)),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black12.withOpacity(.06),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(code.isNotEmpty ? code : '-', style: const TextStyle(letterSpacing: 1.2)),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Sao chép mã lớp',
                      icon: const Icon(Icons.copy_rounded),
                      onPressed: code.isNotEmpty
                          ? () => _copyToClipboard(ctx, code, msg: 'Đã sao chép mã lớp')
                          : null,
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Đóng')),
            ],
          );
        },
      );

      await _load();
    } on DioException catch (e) {
      final msg = prettyDioError(e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $msg')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tạo lớp thất bại')));
    }
  }

  void _goJoinByCode() {
    Navigator.of(context).pushNamed('/join').then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final hasToken = (session.token != null && session.token!.isNotEmpty);
    final bool canCreate = hasToken;
    final bool canJoin = true;

    final isDark = Theme.of(context).brightness == Brightness.dark;

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
          title: const Text('Danh sách lớp đã tham gia'),
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                if (_err != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(_err!, style: const TextStyle(color: Colors.red)),
                  ),
                if (_classes.isEmpty)
                  _GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Chưa có lớp nào',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text(
                          'Bạn có thể tham gia bằng mã hoặc tạo lớp mới.',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: Theme.of(context).colorScheme.outline),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            if (canJoin)
                              OutlinedButton.icon(
                                onPressed: _goJoinByCode,
                                icon: const Icon(Icons.group_add_outlined),
                                label: const Text('Tham gia bằng mã'),
                              ),
                            const SizedBox(width: 12),
                            if (canCreate)
                              FilledButton.icon(
                                onPressed: _createClassDialog,
                                icon: const Icon(Icons.add),
                                label: const Text('Tạo lớp'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ..._classes.map((c) => _ClassCard(
                  data: c,
                  onSelect: () => _selectClass(c),
                  onCopy: (code) => _copyToClipboard(context, code, msg: 'Đã sao chép mã lớp'),
                )),
              ],
            ),
          ),
        ),
        floatingActionButton: _RoleFab(
          showJoin: canJoin,
          showCreate: canCreate,
          onJoin: _goJoinByCode,
          onCreate: _createClassDialog,
        ),
      ),
    );
  }
}

/// ======= Cards & Widgets =======

class _ClassCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onSelect;
  final void Function(String code) onCopy;

  const _ClassCard({
    required this.data,
    required this.onSelect,
    required this.onCopy,
  });

  String _roleLabel(String role) {
    switch (role) {
      case 'owner':
        return 'Owner';
      case 'treasurer':
        return 'Thủ quỹ';
      default:
        return 'Thành viên';
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = (data['name'] ?? '').toString();
    final code = (data['code'] ?? '').toString();
    final roleStr = (data['role'] ?? 'member').toString();

    return _GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onSelect,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // leading icon box
            Container(
              height: 44,
              width: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.class_),
            ),
            const SizedBox(width: 12),
            // title + subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name.isEmpty ? 'Lớp #${data['id']}' : name,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  GestureDetector(
                    onLongPress: () {
                      if (code.isNotEmpty) onCopy(code);
                    },
                    child: Text(
                      code.isNotEmpty ? 'Mã: $code' : 'ID: ${data['id']}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Theme.of(context).colorScheme.outline),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // role chip + copy
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                _roleLabel(roleStr),
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: 'Sao chép mã lớp',
              child: IconButton(
                icon: const Icon(Icons.copy_rounded),
                onPressed: code.isNotEmpty ? () => onCopy(code) : null,
              ),
            ),
          ],
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
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: padding,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: cs.surface.withOpacity(.75),
            borderRadius: BorderRadius.circular(18),
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

class _RoleFab extends StatelessWidget {
  final bool showJoin;
  final bool showCreate;
  final VoidCallback onJoin;
  final VoidCallback onCreate;

  const _RoleFab({
    required this.showJoin,
    required this.showCreate,
    required this.onJoin,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[];

    if (showJoin) {
      buttons.add(
        FloatingActionButton.extended(
          heroTag: 'fab-join',
          onPressed: onJoin,
          icon: const Icon(Icons.group_add),
          label: const Text('Tham gia lớp'),
        ),
      );
    }
    if (showCreate) {
      if (buttons.isNotEmpty) buttons.add(const SizedBox(height: 12));
      buttons.add(
        FloatingActionButton.extended(
          heroTag: 'fab-create',
          onPressed: onCreate,
          icon: const Icon(Icons.add),
          label: const Text('Tạo lớp'),
        ),
      );
    }

    if (buttons.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: buttons,
    );
  }
}
