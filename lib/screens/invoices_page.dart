// lib/screens/invoices_page.dart
import 'dart:async';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../services/session.dart';
import '../repos/invoice_repository.dart';
import 'invoice_detail_page.dart';
import '../services/network.dart';
import '../theme/app_theme.dart';

class InvoicesPage extends ConsumerStatefulWidget {
  const InvoicesPage({super.key});
  @override
  ConsumerState<InvoicesPage> createState() => _InvoicesPageState();
}

class _InvoicesPageState extends ConsumerState<InvoicesPage> {
  List<Map<String, dynamic>> _items = [];
  String? _err;
  bool _loading = true;

  Timer? _pollTimer;
  int? _pollingInvoiceId;
  int _pollTries = 0;

  final NumberFormat _money = NumberFormat.decimalPattern('vi_VN');
  String _vnd(num v) => '${_money.format(v)} đ';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);

    final s = ref.read(sessionProvider);
    final classId = s.classId;
    if (classId == null) {
      if (mounted) {
        setState(() {
          _err = 'Bạn chưa tham gia lớp nào';
          _items = const [];
          _loading = false;
        });
      }
      return;
    }

    try {
      final list = await ref.read(invoiceRepositoryProvider).myInvoices(classId);

      final mapped = list.map<Map<String, dynamic>>((it) {
        final feeCycle = it['fee_cycle'] as Map<String, dynamic>?;
        final idStr = (it['id'] ?? '').toString();
        final title =
            (it['title'] as String?) ?? (feeCycle?['name'] as String?) ?? 'Invoice #$idStr';
        return {...it, 'title': title};
      }).toList();

      if (mounted) {
        setState(() {
          _items = mapped;
          _err = null;
        });
      }
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final msg = prettyDioError(e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
      if (mounted) {
        setState(() {
          _err = status != null ? 'Lỗi $status: $msg' : msg;
          _items = const [];
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _err = 'Lỗi: ${e.runtimeType}';
          _items = const [];
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ===== helpers: overdue + màu trạng thái =====
  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }

  bool _isOverdue(Map<String, dynamic> it) {
    final status = (it['status'] ?? '').toString().toLowerCase();
    if (status == 'paid' || status == 'verified') return false;
    final due = _parseDate(it['due_date']);
    if (due == null) return false;
    final now = DateTime.now();
    return due.isBefore(DateTime(now.year, now.month, now.day)); // quá hạn (so sánh theo ngày)
  }

  Color _statusColor(String status, {required bool overdue}) {
    final s = status.toLowerCase();
    if (overdue) return Colors.grey; // chỉ invoice quá hạn mới xám
    switch (s) {
      case 'paid':
        return Colors.green;
      case 'verified':
        return Colors.blue;
      case 'submitted':
        return Colors.amber.shade800;
      case 'rejected':
      case 'invalid':
        return Colors.redAccent;
      case 'unpaid':
      default:
        return Colors.redAccent; // unpaid = đỏ
    }
  }

  String _statusLabel(String s) {
    switch (s.toLowerCase()) {
      case 'paid':
        return 'ĐÃ THANH TOÁN';
      case 'verified':
        return 'ĐÃ DUYỆT';
      case 'submitted':
        return 'CHỜ DUYỆT';
      case 'rejected':
      case 'invalid':
        return 'TỪ CHỐI';
      case 'unpaid':
        return 'CHƯA NỘP';
      default:
        return s.toUpperCase();
    }
  }

  Future<void> _openDetail(int invoiceId) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => InvoiceDetailPage(invoiceId: invoiceId)),
    );

    if (changed == true) {
      await _load();
      _startPolling(invoiceId);
    }
  }

  void _startPolling(int invoiceId) {
    _pollTimer?.cancel();
    _pollingInvoiceId = invoiceId;
    _pollTries = 0;

    _pollTimer = Timer.periodic(const Duration(seconds: 2), (t) async {
      _pollTries++;
      if (!mounted) {
        t.cancel();
        return;
      }

      final classId = ref.read(sessionProvider).classId;
      if (classId == null) {
        t.cancel();
        return;
      }

      try {
        final detail =
        await ref.read(invoiceRepositoryProvider).invoiceDetail(classId, _pollingInvoiceId!);

        final newStatus = (detail['status'] ?? '').toString();
        if (newStatus != 'submitted' && newStatus.isNotEmpty) {
          final idx = _items.indexWhere((e) => (e['id'] as num).toInt() == _pollingInvoiceId);
          if (idx != -1) {
            final feeCycle = detail['fee_cycle'] as Map<String, dynamic>?;
            final title = (detail['title'] as String?) ??
                (feeCycle?['name'] as String?) ??
                'Invoice #${detail['id']}';
            setState(() {
              _items[idx] = {..._items[idx], ...detail, 'title': title};
            });
          } else {
            await _load();
          }
          t.cancel();
          _pollingInvoiceId = null;
        } else if (_pollTries >= 10) {
          t.cancel();
          _pollingInvoiceId = null;
        }
      } catch (_) {
        if (_pollTries >= 10) {
          t.cancel();
          _pollingInvoiceId = null;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final gradient = Theme.of(context).extension<AppGradients>()?.background;

    if (_loading) {
      return Container(
        decoration: gradient == null ? null : BoxDecoration(gradient: gradient),
        child: const Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return Container(
      decoration: gradient == null ? null : BoxDecoration(gradient: gradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          scrolledUnderElevation: 0,
          backgroundColor: Colors.transparent,
          title: const Text('Hóa đơn của tôi'),
          actions: [
            if (_pollingInvoiceId != null)
              Padding(
                padding: const EdgeInsets.only(right: 12),

              ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            await _load();
            if (_pollingInvoiceId != null) _startPolling(_pollingInvoiceId!);
          },
          child: _err != null
              ? ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _GlassCard(
                child: Text(_err!, style: const TextStyle(color: Colors.red)),
              ),
            ],
          )
              : (_items.isEmpty)
              ? ListView(
            padding: const EdgeInsets.all(16),
            children: const [
              _GlassCard(child: Text('Không có hóa đơn.')),
            ],
          )
              : ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            itemCount: _items.length,
            itemBuilder: (_, i) {
              final it = _items[i];
              final id = (it['id'] as num).toInt();
              final title = (it['title'] as String?) ??
                  (it['fee_cycle']?['name'] as String?) ??
                  'Invoice #$id';

              final status = (it['status'] ?? '').toString();
              final overdue = _isOverdue(it);
              final color = _statusColor(status, overdue: overdue);
              final label = _statusLabel(status);

              final num amountNum = (it['amount'] is num)
                  ? (it['amount'] as num)
                  : (int.tryParse('${it['amount']}') ?? 0);

              // (tuỳ chọn) hiển thị hạn / thời điểm thanh toán dòng 3
              final due = (it['due_date'] ?? '').toString();
              final paidAt = (it['paid_at'] ?? '').toString();
              final infoLine = paidAt.isNotEmpty
                  ? 'Thanh toán: $paidAt'
                  : (due.isNotEmpty ? 'Hạn: $due' : '');

              return _GlassCard(
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _openDetail(id),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        height: 48,
                        width: 48,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.receipt_long, size: 26),
                      ),
                      const SizedBox(width: 12),
                      // ==== Center: Title + Amount (bên trái) ====
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _vnd(amountNum), // số tiền dưới tên
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            if (infoLine.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                infoLine,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      // ==== Right: chỉ có trạng thái ====
                      _StatusPill(label: label, color: color),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// ====== Small UI bits ======

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        border: Border.all(color: color.withValues(alpha: .45)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _GlassCard({required this.child, this.padding = const EdgeInsets.all(14)});

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surface.withValues(alpha: .78);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: base,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .22),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .05),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
