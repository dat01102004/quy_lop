import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../repos/expense_repository.dart';
import '../repos/fee_cycle_repository.dart';
import '../services/api.dart';
import '../services/session.dart';
import '../services/network.dart';

class ExpensesPage extends ConsumerStatefulWidget {
  final int classId;        // có thể = 0 để fallback session
  final int? feeCycleId;    // lọc theo kỳ (nullable)

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

  @override
  void initState() {
    super.initState();
    _load(); // tải lần đầu khi vào trang
  }

  @override
  void dispose() {
    if (!_cancelToken.isCancelled) {
      _cancelToken.cancel('disposed');
    }
    super.dispose();
  }

  /// Lấy classId hiệu lực: ưu tiên param route (>0), nếu không thì lấy từ session
  int _effectiveClassId() {
    if (widget.classId > 0) return widget.classId;
    return ref.read(sessionProvider).classId ?? 0;
  }

  /// Chuẩn hoá proof/receipt path thành URL đầy đủ
  String _fullUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) return path;

    final base = ref.read(dioProvider).options.baseUrl; // vd http://10.0.2.2:8000/api
    final host = base.endsWith('/api') ? base.substring(0, base.length - 4) : base;

    // BE có thể trả "receipts/xxx.jpg" hoặc "/storage/receipts/xxx.jpg"
    if (path.startsWith('/')) {
      return '$host$path';
    }
    return '$host/$path';
  }

  Future<void> _loadCycles(int classId) async {
    if (mounted) setState(() => _loadingCycles = true);
    try {
      final list = await ref.read(feeCycleRepositoryProvider).listCycles(classId);
      if (!mounted) return;
      setState(() => _cycles = list);
    } on DioException catch (_) {
      // im lặng theo đúng ý đồ (form sẽ hiển thị "chưa có kỳ thu")
      // final msg = prettyDioError(_); // nếu cần log nội bộ
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

    // load cycles cho form (không chặn UI)
    _loadCycles(classId);

    try {
      final repo = ref.read(expenseRepositoryProvider);
      final list = await repo.listExpenses(
        classId: classId,
        feeCycleId: widget.feeCycleId,
        cancelToken: _cancelToken,
      );

      // Nếu đang lọc theo kỳ mà rỗng, thử lấy all để cảnh báo user
      if (widget.feeCycleId != null && list.isEmpty) {
        final all = await repo.listExpenses(
          classId: classId,
          cancelToken: _cancelToken,
        );
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
      final msg = prettyDioError(e); // 👈 dùng helper
      setState(() {
        err = msg;
        loading = false;
      });
      // Thông báo thêm nếu 401
      if (e.response?.statusCode == 401) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Phiên đã hết/thiếu token. Vui lòng đăng nhập lại.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
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

    // cycle & date & receipt
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
                  // Tiêu đề
                  TextFormField(
                    controller: titleCtl,
                    decoration: const InputDecoration(labelText: 'Tiêu đề'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập tiêu đề' : null,
                  ),
                  const SizedBox(height: 8),

                  // Số tiền
                  TextFormField(
                    controller: amountCtl,
                    decoration: const InputDecoration(labelText: 'Số tiền'),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final raw = (v ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                      if (raw.isEmpty) return 'Nhập số tiền';
                      if (int.tryParse(raw) == null) return 'Số tiền không hợp lệ';
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),

                  // Kỳ thu
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
                          ..._cycles.map((c) => DropdownMenuItem<int?>(
                            value: c['id'] as int,
                            child: Text(c['name']?.toString() ?? 'Kỳ'),
                          )),
                        ],
                        onChanged: (v) => setLocal(() => selectedCycleId = v),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Ngày mua (ghi tạm vào note)
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
                          if (picked != null) {
                            setLocal(() => purchaseDate = picked);
                          }
                        },
                        icon: const Icon(Icons.event),
                        label: const Text('Chọn ngày'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Ghi chú
                  TextFormField(
                    controller: noteCtl,
                    decoration: const InputDecoration(labelText: 'Ghi chú'),
                  ),
                  const SizedBox(height: 8),

                  // Upload hóa đơn
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
      // nối ngày mua vào note (tạm) để không cần đổi BE
      final extraNote = purchaseDate != null ? 'Ngày mua: ${_formatDate(purchaseDate!)}' : null;
      final finalNote = [
        if ((noteCtl.text.trim().isNotEmpty)) noteCtl.text.trim(),
        if (extraNote != null) extraNote,
      ].join(' • ').trim();

      try {
        if (expense == null) {
          // Tạo mới
          final created = await repo.createExpense(
            classId: classId,
            title: titleCtl.text.trim(),
            amount: amount,
            feeCycleId: selectedCycleId,
            note: finalNote.isEmpty ? null : finalNote,
          );

          // Thử upload hoá đơn nếu có và server trả id
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
          // Cập nhật
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
        final msg = prettyDioError(e); // 👈 dùng helper
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      } catch (e) {
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
      final msg = prettyDioError(e); // 👈 dùng helper
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi xoá: $msg')));
    } catch (e) {
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
      final msg = prettyDioError(e); // 👈 dùng helper
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload lỗi: $msg')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upload biên nhận thất bại')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // ✅ Riverpod listen
    ref.listen<SessionState>(sessionProvider, (prev, next) {
      if (!mounted) return;
      final tokenChanged = prev?.token != next.token;
      final classChanged = prev?.classId != next.classId;
      if (tokenChanged || classChanged) {
        _load();
      }
    });

    final s = ref.watch(sessionProvider);
    final role = (s.role ?? '').toLowerCase();
    final canManage = role == 'owner' || role == 'treasurer';

    return Scaffold(
      appBar: AppBar(title: const Text('Khoản chi')),
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
          ? const Center(child: Text('Chưa có khoản chi'))
          : RefreshIndicator(
        onRefresh: _load,
        child: ListView.builder(
          itemCount: expenses.length,
          itemBuilder: (_, i) {
            final e = expenses[i];
            final id = e['id'];
            final title = e['title']?.toString() ?? '';
            final amount = e['amount']?.toString() ?? '0';

            final receiptUrl = (() {
              final direct = (e['receipt_url'] as String?)?.trim();
              if (direct != null && direct.isNotEmpty) return direct;
              return _fullUrl(e['receipt_path']?.toString());
            })();

            final sub = [
              if ((e['note'] ?? '').toString().isNotEmpty) 'Ghi chú: ${e['note']}',
              if ((e['created_by_name'] ?? '').toString().isNotEmpty)
                'Bởi: ${e['created_by_name']}',
              if ((e['cycle_name'] ?? '').toString().isNotEmpty)
                'Kỳ: ${e['cycle_name']}',
            ].join('\n');

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: ListTile(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ExpenseDetailPage(
                        expense: e,
                        imageUrl: receiptUrl,
                        heroTag: 'exp_$id',
                      ),
                    ),
                  );
                },
                leading: receiptUrl.isEmpty
                    ? const Icon(Icons.receipt_long_outlined)
                    : Hero(
                  tag: 'exp_$id',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(
                      receiptUrl,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) =>
                      const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
                title: Text('$title • ${amount}đ'),
                subtitle: sub.isEmpty ? null : Text(sub),
                trailing: canManage
                    ? PopupMenuButton<String>(
                  onSelected: (val) {
                    if (val == 'edit') {
                      _showForm(expense: e);
                    } else if (val == 'delete') {
                      _deleteExpense(e['id'] as int);
                    } else if (val == 'receipt') {
                      _uploadReceipt(e['id'] as int);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Sửa')),
                    PopupMenuItem(value: 'delete', child: Text('Xoá')),
                    PopupMenuItem(value: 'receipt', child: Text('Tải biên nhận')),
                  ],
                )
                    : null,
              ),
            );
          },
        ),
      ),
      floatingActionButton:
      canManage ? FloatingActionButton(onPressed: () => _showForm(), child: const Icon(Icons.add)) : null,
    );
  }
}

/// Trang chi tiết khoản chi (xem ảnh full & thông tin)
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
    final title = (expense['title'] ?? '').toString();
    final amount = (expense['amount'] ?? '').toString();
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
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$title • ${amount}đ',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  if (note.isNotEmpty) ...[
                    const Text('Ghi chú:', style: TextStyle(fontWeight: FontWeight.w600)),
                    Text(note),
                    const SizedBox(height: 8),
                  ],
                  if (cycle.isNotEmpty) Text('Kỳ: $cycle'),
                  if (who.isNotEmpty) Text('Bởi: $who'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
