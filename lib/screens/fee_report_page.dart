import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../repos/fee_cycle_repository.dart';
import '../repos/invoice_repository.dart';
import '../services/session.dart';
import '../services/network.dart';

class UnpaidMembersPage extends ConsumerStatefulWidget {
  const UnpaidMembersPage({super.key});

  @override
  ConsumerState<UnpaidMembersPage> createState() => _UnpaidMembersPageState();
}

class _UnpaidMembersPageState extends ConsumerState<UnpaidMembersPage> {
  bool _loading = true;
  String? _err;

  List<Map<String, dynamic>> _cycles = [];
  int? _selectedId;

  Map<String, dynamic>? _cycleMeta; // name/due_date/allow_late
  List<Map<String, dynamic>> _items = [];

  final _money = NumberFormat.decimalPattern('vi_VN');

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final classId = ref.read(sessionProvider).classId;
    if (classId == null) {
      setState(() {
        _loading = false;
        _err = 'Chưa có lớp hiện tại';
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final list = await ref.read(feeCycleRepositoryProvider).listCycles(classId);
      setState(() {
        _cycles = list;
        _selectedId = list.isNotEmpty ? (list.first['id'] as num).toInt() : null;
      });
      if (_selectedId != null) {
        await _load();
      } else {
        setState(() => _loading = false);
      }
    } on DioException catch (e) {
      final msg = prettyDioError(e);
      setState(() {
        _loading = false;
        _err = msg;
      });
    }
  }

  Future<void> _load() async {
    final classId = ref.read(sessionProvider).classId!;
    final cycleId = _selectedId;
    if (cycleId == null) return;

    setState(() {
      _loading = true;
      _err = null;
    });

    try {
      final res = await ref.read(invoiceRepositoryProvider).unpaidMembers(
        classId: classId,
        cycleId: cycleId,
      );

      final items = List<Map<String, dynamic>>.from(
        (res['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
      setState(() {
        _cycleMeta = Map<String, dynamic>.from(res['cycle'] as Map);
        _items = items;
      });
    } on DioException catch (e) {
      setState(() => _err = prettyDioError(e));
    } catch (_) {
      setState(() => _err = 'Không tải được danh sách chưa nộp');
    } finally {
      setState(() => _loading = false);
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'submitted': return Colors.orange;
      case 'unpaid': return Colors.redAccent;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(sessionProvider); // rebuild khi đổi lớp

    return Scaffold(
      appBar: AppBar(title: const Text('Danh sách chưa nộp')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (_err != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_err!, style: const TextStyle(color: Colors.red)),
              ),

            // Chọn kỳ thu
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Chọn kỳ thu',
                border: OutlineInputBorder(),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int?>(
                  value: _selectedId,
                  isDense: true,
                  items: _cycles
                      .map((c) => DropdownMenuItem<int?>(
                    value: (c['id'] as num).toInt(),
                    child: Text(c['name']?.toString() ?? 'Kỳ'),
                  ))
                      .toList(),
                  onChanged: (v) async {
                    setState(() {
                      _selectedId = v;
                      _loading = true;
                    });
                    await _load();
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Info kỳ
            if (_cycleMeta != null) ...[
              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_cycleMeta!['name']?.toString() ?? '',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      if (_cycleMeta!['due_date'] != null)
                        Text('Hạn nộp: ${formatDateOnly(_cycleMeta!['due_date'].toString())}'),
                      Text('Cho phép nộp muộn: ${(_cycleMeta!['allow_late'] == true) ? 'Có' : 'Không'}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],

            if (_items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('Tất cả đã hoàn thành 👍')),
              )
            else
              ..._items.map((e) {
                final name = (e['user_name'] ?? e['user_email'] ?? '').toString();
                final phone = (e['user_phone'] ?? '').toString();
                final status = (e['status'] ?? '').toString();
                final id = (e['invoice_id'] as num?)?.toInt() ?? 0;

                final num amountNum = (e['amount'] is num)
                    ? (e['amount'] as num)
                    : (int.tryParse('${e['amount']}') ?? 0);
                final amount = _money.format(amountNum);

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: ListTile(
                    leading: const Icon(Icons.person),
                    title: Text(name.isEmpty ? 'Thành viên #$id' : name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text([
                      'Số tiền: $amount đ',
                      if (phone.isNotEmpty) 'Điện thoại: $phone',
                    ].join('\n')),
                    trailing: Chip(
                      label: Text(status),
                      backgroundColor: _statusColor(status).withOpacity(.12),
                      labelStyle: TextStyle(color: _statusColor(status)),
                    ),
                    onTap: () {
                      // (tuỳ bạn) mở chi tiết hoá đơn:
                      // Navigator.push(context, MaterialPageRoute(
                      //   builder: (_) => InvoiceDetailPage(invoiceId: id),
                      // ));
                    },
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
