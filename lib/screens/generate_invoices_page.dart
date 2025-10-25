// lib/pages/generate_invoices_page.dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/session.dart';
import '../repos/fee_cycle_repository.dart';
import '../services/network.dart'; // prettyDioError, formatDateOnly
import 'package:intl/intl.dart';

class GenerateInvoicesPage extends ConsumerStatefulWidget {
  const GenerateInvoicesPage({super.key});
  @override
  ConsumerState<GenerateInvoicesPage> createState() => _GenerateInvoicesPageState();
}

class _GenerateInvoicesPageState extends ConsumerState<GenerateInvoicesPage> {
  // Data
  List<Map<String, dynamic>> _cycles = [];
  int? _selectedId; // id của kỳ nếu tên gõ trùng
  bool _loading = true;
  String? _err;
  Map<String, dynamic>? _lastResult;

  // Inputs
  final _cycleNameCtl = TextEditingController();
  final _amountCtl = TextEditingController(); // để trống => dùng default của kỳ
  DateTime? _dueDate; // chỉ dùng khi tạo kỳ mới
  bool _allowLate = false; // chỉ dùng khi tạo kỳ mới

  @override
  void initState() {
    super.initState();
    _loadCycles();
  }

  @override
  void dispose() {
    _cycleNameCtl.dispose();
    _amountCtl.dispose();
    super.dispose();
  }

  Future<void> _loadCycles() async {
    final classId = ref.read(sessionProvider).classId;
    if (classId == null) {
      if (!mounted) return;
      setState(() {
        _err = 'Chưa có lớp hiện tại';
        _loading = false;
      });
      return;
    }
    if (mounted) setState(() => _loading = true);

    try {
      final list = await ref.read(feeCycleRepositoryProvider).listCycles(classId);
      if (!mounted) return;
      setState(() {
        _cycles = list;
        if (_cycles.isNotEmpty) {
          _cycleNameCtl.text = (_cycles.first['name'] ?? '').toString();
          _selectedId = (_cycles.first['id'] as num?)?.toInt();
          _amountCtl.text = (_cycles.first['amount_per_member'] ?? '').toString();
        }
        _err = null;
      });
    } on DioException catch (e) {
      final msg = prettyDioError(e);
      if (!mounted) return;
      setState(() => _err = msg);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _err = 'Không tải được danh sách kỳ thu');
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Không tải được danh sách kỳ thu')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _syncSelectedIdByName(String name) {
    final hit = _cycles.firstWhere(
          (c) => (c['name'] ?? '').toString() == name,
      orElse: () => {},
    );
    if (hit.isNotEmpty) {
      _selectedId = (hit['id'] as num?)?.toInt();
      _amountCtl.text = (hit['amount_per_member'] ?? '').toString();
    } else {
      _selectedId = null; // tên mới -> sẽ tạo kỳ mới
      // reset thông tin tạo mới
      _allowLate = false;
      _dueDate ??= DateTime.now();
    }
    if (mounted) setState(() {});
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 5), // cho phép chọn cả quá khứ nếu muốn
      lastDate: DateTime(now.year + 5),
      initialDate: _dueDate ?? now,
    );
    if (picked != null && mounted) setState(() => _dueDate = picked);
  }

  Map<String, dynamic>? _selectedCycle() {
    if (_selectedId == null) return null;
    return _cycles.firstWhere(
          (c) => (c['id'] as num?)?.toInt() == _selectedId,
      orElse: () => {},
    );
  }

  bool _isOverdue(Map<String, dynamic>? cycle) {
    if (cycle == null) return false;
    final dueStr = cycle['due_date']?.toString();
    if (dueStr == null || dueStr.isEmpty) return false;
    final due = DateTime.tryParse(dueStr);
    if (due == null) return false;
    final today = DateTime.now();
    return DateTime(today.year, today.month, today.day)
        .isAfter(DateTime(due.year, due.month, due.day));
  }

  Future<void> _generate() async {
    final classId = ref.read(sessionProvider).classId!;
    final name = _cycleNameCtl.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập tên kỳ thu')),
      );
      return;
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _lastResult = null;
        _err = null;
      });
    }

    try {
      // Nếu không trùng kỳ nào -> tạo kỳ mới (cần hạn nộp)
      int cycleId;
      if (_selectedId != null) {
        cycleId = _selectedId!;
      } else {
        if (_dueDate == null) {
          if (mounted) setState(() => _loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Chọn hạn nộp để tạo kỳ thu mới')),
          );
          return;
        }

        final amountPerMember =
            num.tryParse(_amountCtl.text.trim().isEmpty ? '0' : _amountCtl.text.trim()) ?? 0;

        final created = await ref.read(feeCycleRepositoryProvider).createCycle(
          classId: classId,
          name: name,
          amountPerMember: amountPerMember,
          dueDateIso: _dueDate!.toIso8601String().substring(0, 10), // yyyy-MM-dd
          allowLate: _allowLate, // gửi allow_late lên BE
        );

        // lấy id từ response (tuỳ BE)
        cycleId = (created['id'] ?? (created['fee_cycle']?['id'])) as int;

        // thêm vào list local để lần sau gợi ý
        _cycles.insert(0, {
          'id': cycleId,
          'name': name,
          'amount_per_member': amountPerMember,
          'due_date': _dueDate!.toIso8601String().substring(0, 10),
          'allow_late': _allowLate,
        });
        _selectedId = cycleId;
      }

      // Phát hóa đơn (cho phép override amountPerMember nếu muốn)
      final amountOverride = int.tryParse(_amountCtl.text.trim());
      final res = await ref.read(feeCycleRepositoryProvider).generateInvoices(
        classId: classId,
        cycleId: cycleId,
        amountPerMember: amountOverride,
      );

      if (!mounted) return;
      setState(() => _lastResult = res);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã phát: ${res['created']} • bỏ qua: ${res['skipped']}')),
      );
    } on DioException catch (e) {
      final msg = prettyDioError(e);
      if (!mounted) return;
      setState(() => _err = msg);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      const msg = 'Phát hóa đơn thất bại';
      if (!mounted) return;
      setState(() => _err = msg);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _cycles.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final selected = _selectedCycle();
    final overdue = _isOverdue(selected);
    final allowLateSelected = (selected?['allow_late'] == true);

    return Scaffold(
      appBar: AppBar(title: const Text('Phát hóa đơn')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_err != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_err!, style: const TextStyle(color: Colors.red)),
            ),

          // ===== Nhập tên kỳ thu (Autocomplete từ kỳ có sẵn) =====
          Text('Tên kỳ thu', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Autocomplete<String>(
            optionsBuilder: (TextEditingValue text) {
              final q = text.text.trim().toLowerCase();
              if (q.isEmpty) return const Iterable<String>.empty();
              return _cycles
                  .map((c) => (c['name'] ?? '').toString())
                  .where((n) => n.toLowerCase().contains(q));
            },
            onSelected: (val) {
              _cycleNameCtl.text = val;
              _syncSelectedIdByName(val);
            },
            fieldViewBuilder: (ctx, textCtl, focus, onSubmit) {
              textCtl.text = _cycleNameCtl.text;
              textCtl.selection = TextSelection.fromPosition(
                TextPosition(offset: textCtl.text.length),
              );
              return TextField(
                controller: textCtl,
                focusNode: focus,
                decoration: const InputDecoration(
                  hintText: 'Nhập tên kỳ thu ',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) {
                  _cycleNameCtl.text = v;
                  _syncSelectedIdByName(v);
                },
              );
            },
          ),

          const SizedBox(height: 12),

          // ===== Số tiền / thành viên =====
          TextField(
            controller: _amountCtl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Số tiền / thành viên (bỏ trống = dùng mặc định của kỳ)',
              border: OutlineInputBorder(),
            ),
          ),

          // ===== Nếu chọn KỲ CŨ: show info due_date + allow_late =====
          if (_selectedId != null && selected != null) ...[
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Thông tin kỳ đã chọn',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Text('Hạn nộp: ${formatDateOnly(selected['due_date']?.toString())}'),
                    Text('Cho phép nộp muộn: ${allowLateSelected ? 'Có' : 'Không'}'),
                    if (overdue && !allowLateSelected) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Kỳ đã quá hạn và KHÔNG cho phép nộp muộn — các phiếu nộp sẽ bị chặn.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],

          // ===== Nếu TẠO KỲ MỚI: chọn hạn nộp + switch allow late =====
          if (_selectedId == null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickDueDate,
              icon: const Icon(Icons.event),
              label: Text(
                _dueDate == null
                    ? 'Chọn hạn nộp cho kỳ mới'
                    : 'Hạn nộp: ${DateFormat('yyyy-MM-dd').format(_dueDate!)}',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Cho phép nộp muộn'),
              value: _allowLate,
              onChanged: (v) => setState(() => _allowLate = v),
            ),
            const SizedBox(height: 4),
            Text(
              'Tên kỳ chưa trùng với kỳ nào → tạo kỳ mới (cần hạn nộp).',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
          ],

          const SizedBox(height: 16),

          // ===== Submit =====
          ElevatedButton.icon(
            onPressed: _loading ? null : _generate,
            icon: const Icon(Icons.send),
            label: const Text('Phát hóa đơn'),
          ),

          if (_lastResult != null) ...[
            const SizedBox(height: 16),
            Text(
              'Kết quả: tạo mới ${_lastResult!['created']}, '
                  'bỏ qua ${_lastResult!['skipped']} / tổng ${_lastResult!['total_members']}',
            ),
          ],
        ],
      ),
    );
  }
}
