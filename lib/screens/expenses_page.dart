// lib/screens/expenses_page.dart
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../repos/expense_repository.dart';
import '../repos/fee_cycle_repository.dart';
import '../services/api.dart';
import '../services/session.dart';
import '../services/network.dart';
import '../theme/app_theme.dart';

class ExpensesPage extends ConsumerStatefulWidget {
  final int classId; // có thể = 0 để fallback session
  final int? feeCycleId; // lọc theo kỳ (nullable)

  const ExpensesPage({
    super.key,
    required this.classId,
    this.feeCycleId,
  });

  @override
  ConsumerState<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends ConsumerState<ExpensesPage> {
  bool loading = true;
  String? err;
  List<Map<String, dynamic>> expenses = [];

  // dữ liệu kỳ thu (để dropdown trong form)
  List<Map<String, dynamic>> _cycles = [];
  bool _loadingCycles = false;

  final CancelToken _cancelToken = CancelToken();

  final NumberFormat _money = NumberFormat.decimalPattern('vi_VN');
  String _formatMoney(num v) => '${_money.format(v)} đ';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (!_cancelToken.isCancelled) {
      _cancelToken.cancel('disposed');
    }
    super.dispose();
  }

  int _effectiveClassId() {
    if (widget.classId > 0) return widget.classId;
    return ref.read(sessionProvider).classId ?? 0;
  }

  String _fullUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) return path;

    final base = ref.read(dioProvider).options.baseUrl; // vd http://10.0.2.2:8000/api
    final host = base.endsWith('/api') ? base.substring(0, base.length - 4) : base;

    if (path.startsWith('/')) return '$host$path';
    return '$host/$path';
  }

  Future<void> _loadCycles(int classId) async {
    if (mounted) setState(() => _loadingCycles = true);
    try {
      final list = await ref.read(feeCycleRepositoryProvider).listCycles(classId);
      if (!mounted) return;
      setState(() => _cycles = list);
    } catch (_) {
      // im lặng
    } finally {
      if (mounted) setState(() => _loadingCycles = false);
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    final classId = _effectiveClassId();

    setState(() {
      loading = true;
      err = null;
    });

    if (classId <= 0) {
      setState(() {
        loading = false;
        err = 'Chưa chọn lớp — không thể tải Khoản chi';
      });
      return;
    }

    _loadCycles(classId);

    try {
      final repo = ref.read(expenseRepositoryProvider);
      final list = await repo.listExpenses(
        classId: classId,
        feeCycleId: widget.feeCycleId,
        cancelToken: _cancelToken,
      );

      if (widget.feeCycleId != null && list.isEmpty) {
        final all = await repo.listExpenses(classId: classId, cancelToken: _cancelToken);
        if (all.isNotEmpty && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Không có khoản chi thuộc kỳ đã chọn.')),
          );
        }
      }

      if (!mounted) return;
      setState(() {
        expenses = list;
        loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      if (CancelToken.isCancel(e)) {
        setState(() => loading = false);
        return;
      }
      final msg = prettyDioError(e);
      setState(() {
        err = msg;
        loading = false;
      });
      if (e.response?.statusCode == 401) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Phiên đã hết/thiếu token. Vui lòng đăng nhập lại.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        err = 'Không tải được danh sách khoản chi';
        loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không tải được danh sách khoản chi')),
      );
    }
  }

  Future<void> _showForm({Map<String, dynamic>? expense}) async {
    final classId = _effectiveClassId();

    final formKey = GlobalKey<FormState>();
    final titleCtl = TextEditingController(text: expense?['title']?.toString() ?? '');
    final amountCtl = TextEditingController(text: expense?['amount']?.toString() ?? '');
    final noteCtl = TextEditingController(text: expense?['note']?.toString() ?? '');

    int? selectedCycleId = expense?['fee_cycle_id'] as int? ?? widget.feeCycleId;
    DateTime? purchaseDate;
    XFile? pickedReceipt;

    String _formatDate(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(expense == null ? 'Thêm khoản chi' : 'Sửa khoản chi'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: titleCtl,
                    decoration: const InputDecoration(labelText: 'Tiêu đề'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập tiêu đề' : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: amountCtl,
                    decoration: const InputDecoration(labelText: 'Số tiền (VND)'),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final raw = (v ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                      if (raw.isEmpty) return 'Nhập số tiền';
                      if (int.tryParse(raw) == null) return 'Số tiền không hợp lệ';
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Kỳ thu',
                      border: OutlineInputBorder(),
                    ),
                    child: _loadingCycles
                        ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: LinearProgressIndicator(minHeight: 2),
                    )
                        : DropdownButtonHideUnderline(
                      child: DropdownButton<int?>(
                        isDense: true,
                        value: selectedCycleId,
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('— Không gán kỳ —'),
                          ),
                          ..._cycles.map(
                                (c) => DropdownMenuItem<int?>(
                              value: c['id'] as int,
                              child: Text(c['name']?.toString() ?? 'Kỳ'),
                            ),
                          ),
                        ],
                        onChanged: (v) => setLocal(() => selectedCycleId = v),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          purchaseDate == null
                              ? 'Ngày mua: (chưa chọn)'
                              : 'Ngày mua: ${_formatDate(purchaseDate!)}',
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: purchaseDate ?? now,
                            firstDate: DateTime(now.year - 2),
                            lastDate: DateTime(now.year + 2),
                          );
                          if (picked != null) setLocal(() => purchaseDate = picked);
                        },
                        icon: const Icon(Icons.event),
                        label: const Text('Chọn ngày'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: noteCtl,
                    decoration: const InputDecoration(labelText: 'Ghi chú'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () async {
                          final picker = ImagePicker();
                          final f = await picker.pickImage(
                            source: ImageSource.gallery,
                            imageQuality: 85,
                          );
                          if (f != null) setLocal(() => pickedReceipt = f);
                        },
                        icon: const Icon(Icons.receipt_long),
                        label: const Text('Chọn hoá đơn'),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          pickedReceipt?.name ?? 'Chưa chọn file',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      final repo = ref.read(expenseRepositoryProvider);
      final amount = int.parse(amountCtl.text.replaceAll(RegExp(r'[^0-9]'), ''));
      final extraNote = purchaseDate != null ? 'Ngày mua: ${_formatDate(purchaseDate!)}' : null;
      final finalNote = [
        if ((noteCtl.text.trim().isNotEmpty)) noteCtl.text.trim(),
        if (extraNote != null) extraNote,
      ].join(' • ').trim();

      try {
        if (expense == null) {
          final created = await repo.createExpense(
            classId: classId,
            title: titleCtl.text.trim(),
            amount: amount,
            feeCycleId: selectedCycleId,
            note: finalNote.isEmpty ? null : finalNote,
          );

          final newId = (created is Map)
              ? (created['expense']?['id'] ?? created['id'])
              : null;

          if (pickedReceipt != null && newId is int) {
            await repo.uploadReceipt(
              classId: classId,
              expenseId: newId,
              filePath: pickedReceipt!.path,
            );
          } else if (pickedReceipt != null) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Đã lưu. Hãy mở menu "Tải biên nhận" để tải hoá đơn.'),
                ),
              );
            }
          }
        } else {
          await repo.updateExpense(
            classId: classId,
            expenseId: expense['id'] as int,
            title: titleCtl.text.trim(),
            amount: amount,
            feeCycleId: selectedCycleId,
            note: finalNote.isEmpty ? null : finalNote,
          );
          if (pickedReceipt != null) {
            await repo.uploadReceipt(
              classId: classId,
              expenseId: expense['id'] as int,
              filePath: pickedReceipt!.path,
            );
          }
        }
        if (mounted) _load();
      } on DioException catch (e) {
        if (!mounted) return;
        final msg = prettyDioError(e);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lưu khoản chi thất bại')),
        );
      }
    }
  }

  Future<void> _deleteExpense(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xoá khoản chi'),
        content: const Text('Bạn có chắc chắn muốn xoá không?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xoá')),
        ],
      ),
    );
    if (ok != true) return;

    final repo = ref.read(expenseRepositoryProvider);
    try {
      await repo.deleteExpense(classId: _effectiveClassId(), expenseId: id);
      if (mounted) _load();
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = prettyDioError(e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi xoá: $msg')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không xoá được khoản chi')),
      );
    }
  }

  Future<void> _uploadReceipt(int expenseId) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file == null) return;

    final repo = ref.read(expenseRepositoryProvider);
    try {
      await repo.uploadReceipt(
        classId: _effectiveClassId(),
        expenseId: expenseId,
        filePath: file.path,
      );
      if (mounted) _load();
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = prettyDioError(e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload lỗi: $msg')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upload biên nhận thất bại')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // nghe thay đổi session để reload
    ref.listen<SessionState>(sessionProvider, (prev, next) {
      if (!mounted) return;
      final tokenChanged = prev?.token != next.token;
      final classChanged = prev?.classId != next.classId;
      if (tokenChanged || classChanged) _load();
    });

    final s = ref.watch(sessionProvider);
    final role = (s.role ?? '').toLowerCase();
    final canManage = role == 'owner' || role == 'treasurer';
    final gradient = Theme.of(context).extension<AppGradients>()?.background;

    return Container(
      decoration: gradient == null ? null : BoxDecoration(gradient: gradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          scrolledUnderElevation: 0,
          backgroundColor: Colors.transparent,
          title: const Text('Khoản chi'),
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : err != null
            ? Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(err!, style: const TextStyle(color: Colors.red)),
          ),
        )
            : expenses.isEmpty
            ? _EmptyState(
          canManage: canManage,
          onAdd: () => _showForm(),
        )
            : RefreshIndicator(
          onRefresh: _load,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: expenses.length,
            itemBuilder: (_, i) => _ExpenseTile(
              data: expenses[i],
              formatMoney: _formatMoney,
              fullUrl: _fullUrl,
              canManage: canManage,
              onEdit: () => _showForm(expense: expenses[i]),
              onDelete: () => _deleteExpense(expenses[i]['id'] as int),
              onUpload: () => _uploadReceipt(expenses[i]['id'] as int),
            ),
          ),
        ),
        floatingActionButton:
        canManage ? FloatingActionButton(onPressed: () => _showForm(), child: const Icon(Icons.add)) : null,
      ),
    );
  }
}

/// ======= UI bits =======

class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  const _GlassCard({required this.child, this.padding = const EdgeInsets.all(16), this.radius = 16});

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surface.withOpacity(.78);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          decoration: BoxDecoration(
            color: base,
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant.withOpacity(.22),
            ),
            borderRadius: BorderRadius.circular(radius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(.05),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool canManage;
  final VoidCallback onAdd;
  const _EmptyState({required this.canManage, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: _GlassCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.receipt_long_outlined, size: 36),
            const SizedBox(height: 8),
            const Text('Chưa có khoản chi'),
            if (canManage) ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('Thêm khoản chi'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final String Function(num) formatMoney;
  final String Function(String?) fullUrl;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onUpload;

  const _ExpenseTile({
    required this.data,
    required this.formatMoney,
    required this.fullUrl,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
    required this.onUpload,
  });

  @override
  Widget build(BuildContext context) {
    final id = data['id'];
    final title = (data['title'] ?? '').toString();
    final num amountNum = (data['amount'] is num)
        ? data['amount'] as num
        : (int.tryParse('${data['amount']}') ?? 0);

    final receiptUrl = (() {
      final direct = (data['receipt_url'] as String?)?.trim();
      if (direct != null && direct.isNotEmpty) return direct;
      return fullUrl(data['receipt_path']?.toString());
    })();

    final note = (data['note'] ?? '').toString();
    final who = (data['created_by_name'] ?? '').toString();
    final cycle = (data['cycle_name'] ?? '').toString();

    return _GlassCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ExpenseDetailPage(
                expense: data,
                imageUrl: receiptUrl,
                heroTag: 'exp_$id',
              ),
            ),
          );
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // thumbnail
            _Thumb(url: receiptUrl, heroTag: 'exp_$id'),
            const SizedBox(width: 12),
            // texts
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title.isEmpty ? '(Chưa đặt tiêu đề)' : title,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        formatMoney(amountNum),
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (cycle.isNotEmpty)
                    _InfoRow(
                      icon: Icons.event_note,
                      text: 'Kỳ: $cycle',
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  if (note.isNotEmpty) const SizedBox(height: 2),
                  if (note.isNotEmpty)
                    _InfoRow(
                      icon: Icons.notes_outlined,
                      text: note,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  if (who.isNotEmpty) const SizedBox(height: 2),
                  if (who.isNotEmpty)
                    _InfoRow(
                      icon: Icons.person_outline,
                      text: 'Bởi: $who',
                      color: Theme.of(context).colorScheme.outline,
                    ),
                ],
              ),
            ),
            if (canManage)
              PopupMenuButton<String>(
                onSelected: (val) {
                  if (val == 'edit') onEdit();
                  if (val == 'delete') onDelete();
                  if (val == 'receipt') onUpload();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Sửa')),
                  PopupMenuItem(value: 'delete', child: Text('Xoá')),
                  PopupMenuItem(value: 'receipt', child: Text('Tải biên nhận')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final String url;
  final String heroTag;
  const _Thumb({required this.url, required this.heroTag});

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: 54,
      height: 54,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.receipt_long_outlined),
    );

    if (url.isEmpty) return box;

    return Hero(
      tag: heroTag,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          url,
          width: 54,
          height: 54,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => box,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  const _InfoRow({required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// Trang chi tiết khoản chi
class ExpenseDetailPage extends StatelessWidget {
  final Map<String, dynamic> expense;
  final String imageUrl;
  final String heroTag;

  const ExpenseDetailPage({
    super.key,
    required this.expense,
    required this.imageUrl,
    required this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    final NumberFormat money = NumberFormat.decimalPattern('vi_VN');
    String moneyStr(num v) => '${money.format(v)} đ';

    final title = (expense['title'] ?? '').toString();
    final num amountNum = (expense['amount'] is num)
        ? expense['amount'] as num
        : (int.tryParse('${expense['amount']}') ?? 0);
    final note = (expense['note'] ?? '').toString();
    final who = (expense['created_by_name'] ?? '').toString();
    final cycle = (expense['cycle_name'] ?? '').toString();

    return Scaffold(
      appBar: AppBar(title: const Text('Khoản chi')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (imageUrl.isNotEmpty) ...[
            Hero(
              tag: heroTag,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 9 / 16,
                  child: InteractiveViewer(
                    panEnabled: true,
                    minScale: 0.5,
                    maxScale: 4,
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Không tải được ảnh hóa đơn'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          _GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.isEmpty ? '(Chưa đặt tiêu đề)' : title,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  moneyStr(amountNum),
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                if (note.isNotEmpty) ...[
                  const Text('Ghi chú:', style: TextStyle(fontWeight: FontWeight.w600)),
                  Text(note),
                  const SizedBox(height: 10),
                ],
                if (cycle.isNotEmpty) Text('Kỳ: $cycle'),
                if (who.isNotEmpty) Text('Bởi: $who'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
