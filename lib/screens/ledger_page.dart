// lib/screens/ledger_page.dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../repos/fund_account_repository.dart';
import '../repos/fee_cycle_repository.dart';
import '../services/network.dart';

class LedgerPage extends ConsumerStatefulWidget {
  final int classId;
  const LedgerPage({super.key, required this.classId});
  @override
  ConsumerState<LedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends ConsumerState<LedgerPage> {
  bool _loading = true;
  String? _err;
  int? _feeCycleId;
  List<Map<String, dynamic>> _cycles = [];
  Map<String, dynamic> _data = {};

  final _money = NumberFormat.decimalPattern('vi_VN');

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (mounted) setState(() { _loading = true; _err = null; });
    try {
      _cycles = await ref.read(feeCycleRepositoryProvider).listCycles(widget.classId);
      await _load();
    } on DioException catch (e) {
      final msg = prettyDioError(e);
      if (!mounted) return;
      _err = msg;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      _err = e.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không tải được dữ liệu kỳ thu')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(fundAccountRepositoryProvider);
      final d = await repo.getLedger(classId: widget.classId, feeCycleId: _feeCycleId);
      if (!mounted) return;
      setState(() {
        _data = d;
        _err = null;
      });
    } on DioException catch (e) {
      final msg = prettyDioError(e);
      if (!mounted) return;
      setState(() => _err = msg);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = 'Không tải được sổ thu chi');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không tải được sổ thu chi')),
      );
    }
  }

  // ===== Helpers =====
  String _typeLower(Map<String, dynamic> e) =>
      (e['type'] ?? e['entry_type'] ?? '').toString().toLowerCase();

  bool _isInvalid(Map<String, dynamic> e) =>
      _typeLower(e) == 'invalid_payment' || (e['invalid'] == true);

  bool _isIncome(Map<String, dynamic> e) {
    if (e['is_income'] == true) return true;
    final t = _typeLower(e);
    // coi các loại sau là thu
    if (t == 'income' || t == 'payment' || t == 'deposit') return true;
    // invalid_payment luôn coi là chi (đảo quỹ)
    return false;
  }

  String _typeLabel(Map<String, dynamic> e) {
    if (_isInvalid(e)) return 'Không hợp lệ';
    return _isIncome(e) ? 'Thu' : 'Chi';
  }

  num _asNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    if (v is String) {
      final cleaned = v.replaceAll(RegExp(r'[^\d\-,\.]'), '');
      final vn = num.tryParse(cleaned.replaceAll('.', '').replaceAll(',', '.'));
      return vn ?? num.tryParse(cleaned) ?? 0;
    }
    return 0;
  }

  num _getNum(List<String> keys) {
    for (final k in keys) {
      if (_data.containsKey(k) && _data[k] != null) return _asNum(_data[k]);
    }
    return 0;
  }

  /// Trả về (opening, income, expense, invalid, closing)
  ({num opening, num income, num expense, num invalid, num closing}) _summary() {
    final items = List<Map<String, dynamic>>.from(_data['items'] ?? const []);
    num opening  = _getNum(['opening_balance', 'openingBalance', 'opening']);
    num income   = _getNum(['total_income',   'totalIncome',   'income']);
    num expense  = _getNum(['total_expense',  'totalExpense',  'expense']);
    num closing  = _getNum(['closing_balance','closingBalance','closing']);
    num invalid  = 0;

    // nếu BE không trả sẵn tổng, tự tính
    if (income == 0 || expense == 0 || closing == 0) {
      num inc = 0, exp = 0, lastBal = 0;
      for (final e in items) {
        final amt = _asNum(e['amount']);
        final isIncome = _isIncome(e);
        if (_isInvalid(e)) {
          invalid += amt;
        }
        if (isIncome) inc += amt; else exp += amt;
        if (e['balance_after'] != null) lastBal = _asNum(e['balance_after']);
        if (e['balanceAfter'] != null)  lastBal = _asNum(e['balanceAfter']);
      }
      if (income == 0)  income  = inc;
      if (expense == 0) expense = exp;
      if (closing == 0) closing = lastBal;
    } else {
      // nếu BE có trường invalid_total thì lấy luôn
      invalid = _getNum(['invalid_total', 'invalidTotal', 'invalid']);
    }

    // nếu chưa có opening mà có các số khác => suy ra
    if (opening == 0 && (income != 0 || expense != 0 || closing != 0)) {
      opening = closing - income + expense;
    }

    return (opening: opening, income: income, expense: expense, invalid: invalid, closing: closing);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Phiếu thu chi')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _err != null
          ? Center(child: Text(_err!, style: const TextStyle(color: Colors.red)))
          : RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            // Filter kỳ thu
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Chọn kỳ thu',
                border: OutlineInputBorder(),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int?>(
                  value: _feeCycleId,
                  isDense: true,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Tất cả kỳ')),
                    ..._cycles.map((c) => DropdownMenuItem<int?>(
                      value: c['id'] as int,
                      child: Text(c['name']?.toString() ?? 'Kỳ'),
                    )),
                  ],
                  onChanged: (v) {
                    setState(() => _feeCycleId = v);
                    _load();
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ===== Tổng quan =====
            Builder(builder: (context) {
              final sm = _summary();
              return Card(
                child: ListTile(
                  title: const Text('Tổng quan'),
                  subtitle: Text([
                    'Tổng thu: ${_money.format(sm.income)} đ',
                    'Tổng chi: ${_money.format(sm.expense)} đ',
                    if (sm.invalid > 0)
                      'Không hợp lệ (đã trừ): ${_money.format(sm.invalid)} đ',
                    'Số dư cuối kỳ: ${_money.format(sm.closing)} đ',
                  ].join('\n')),
                ),
              );
            }),
            const SizedBox(height: 8),

            // Bảng dòng thu/chi
            _buildTable(context),
          ],
        ),
      ),
    );
  }

  Widget _buildTable(BuildContext context) {
    final items = List<Map<String, dynamic>>.from(_data['items'] ?? const []);
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('Chưa có giao dịch.')),
      );
    }

    final cellStyle = Theme.of(context).textTheme.bodySmall!;
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Ngày')),
            DataColumn(label: Text('ID')),
            DataColumn(label: Text('Nội dung')),
            DataColumn(label: Text('Thành Viên')),
            DataColumn(label: Text('Số tiền')),
            DataColumn(label: Text('Loại')),
            DataColumn(label: Text('Số dư')),
          ],
          rows: items.map((e) {
            final isIncome = _isIncome(e);
            final isInvalid = _isInvalid(e);
            final amt = _asNum(e['amount']);
            final bal = _asNum(e['balance_after'] ?? e['balanceAfter']);
            final typeLabel = _typeLabel(e);
            final note = (e['note'] ?? '').toString();

            return DataRow(
              color: isInvalid
                  ? MaterialStatePropertyAll(Colors.red.withOpacity(0.035))
                  : null,
              cells: [
                DataCell(Text((e['occurred_at'] ?? e['occurredAt'] ?? '').toString(),
                    style: cellStyle)),
                DataCell(Text(e['id'].toString(), style: cellStyle)),
                DataCell(Text(note, style: cellStyle)),
                DataCell(Text('${e['subject_name'] ?? e['subjectName'] ?? ''} ',
                    style: cellStyle)),
                DataCell(Text(
                  _money.format(amt),
                  style: TextStyle(
                    color: isIncome ? Colors.green : Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                )),
                DataCell(Text(
                  typeLabel,
                  style: TextStyle(
                    color: isInvalid ? Colors.red : null,
                    fontStyle: isInvalid ? FontStyle.italic : FontStyle.normal,
                  ),
                )),
                DataCell(Text(_money.format(bal), style: cellStyle)),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}
