import 'dart:async'; // <— thêm
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/session.dart';
import '../repos/invoice_repository.dart';
import 'invoice_detail_page.dart';
import '../services/network.dart';

class InvoicesPage extends ConsumerStatefulWidget {
  const InvoicesPage({super.key});
  @override
  ConsumerState<InvoicesPage> createState() => _InvoicesPageState();
}

class _InvoicesPageState extends ConsumerState<InvoicesPage> {
  List<Map<String, dynamic>> _items = [];
  String? _err;
  bool _loading = true;

  Timer? _pollTimer;          // <— timer polling
  int? _pollingInvoiceId;     // <— đang theo dõi hóa đơn nào
  int _pollTries = 0;         // <— số lần hỏi lại

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
      debugPrint('DioException: ${e.response?.data}');
    } catch (e) {
      if (mounted) {
        setState(() {
          _err = 'Lỗi: ${e.runtimeType}';
          _items = const [];
        });
      }
      debugPrint('Exception: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'paid':
        return Colors.green;
      case 'verified':
        return Colors.blue;
      case 'submitted':
        return Colors.orange;
      default:
        return Colors.redAccent;
    }
  }

  Future<void> _openDetail(int invoiceId) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => InvoiceDetailPage(invoiceId: invoiceId)),
    );

    // Nếu Detail báo đã "submit" xong (pop(true)), ta reload nhanh để thấy trạng thái submitted
    if (changed == true) {
      await _load();
      // Và kích hoạt polling theo dõi hóa đơn này để bắt chuyển sang verified
      _startPolling(invoiceId);
    }
  }

  void _startPolling(int invoiceId) {
    _pollTimer?.cancel();
    _pollingInvoiceId = invoiceId;
    _pollTries = 0;

    // 10 lần * 2 giây ≈ 20 giây (tùy bạn chỉnh)
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
        // Hỏi chi tiết 1 hóa đơn để giảm tải
        final detail = await ref
            .read(invoiceRepositoryProvider)
            .invoiceDetail(classId, _pollingInvoiceId!);

        final newStatus = (detail['status'] ?? '').toString();
        // Nếu đã khác submitted (verified/paid/rejected...) => cập nhật danh sách + dừng polling
        if (newStatus != 'submitted' && newStatus.isNotEmpty) {
          // cập nhật item trong danh sách
          final idx = _items.indexWhere((e) => (e['id'] as num).toInt() == _pollingInvoiceId);
          if (idx != -1) {
            final feeCycle = detail['fee_cycle'] as Map<String, dynamic>?;
            final title = (detail['title'] as String?) ??
                (feeCycle?['name'] as String?) ??
                'Invoice #${detail['id']}';
            setState(() {
              _items[idx] = {
                ..._items[idx],
                ...detail,
                'title': title,
              };
            });
          } else {
            // fallback: reload toàn bộ nếu không tìm thấy
            await _load();
          }
          t.cancel();
          _pollingInvoiceId = null;
        } else if (_pollTries >= 10) {
          // Hết thời gian chờ: dừng polling
          t.cancel();
          _pollingInvoiceId = null;
        }
      } catch (_) {
        // lỗi tạm thời → thử lại cho tới khi hết số lần
        if (_pollTries >= 10) {
          t.cancel();
          _pollingInvoiceId = null;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Hóa đơn của tôi')),
      body: RefreshIndicator(
        onRefresh: () async {
          await _load();
          // Nếu sau refresh vẫn còn item submitted đang theo dõi, tiếp tục polling
          if (_pollingInvoiceId != null) _startPolling(_pollingInvoiceId!);
        },
        child: _err != null
            ? ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_err!, style: const TextStyle(color: Colors.red)),
            ),
          ],
        )
            : (_items.isEmpty)
            ? ListView(
          children: const [
            Padding(
              padding: EdgeInsets.all(16),
              child: Text('Không có hóa đơn.'),
            ),
          ],
        )
            : ListView.separated(
          itemCount: _items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final it = _items[i];
            final id = (it['id'] as num).toInt();
            final amount = it['amount'];
            final status = (it['status'] ?? '').toString();
            final title = (it['title'] as String?) ??
                (it['fee_cycle']?['name'] as String?) ??
                'Invoice #$id';

            final c = _statusColor(status);
            return ListTile(
              leading: const Icon(Icons.receipt_long),
              title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('Số tiền: $amount'),
              trailing: Chip(
                label: Text(status),
                backgroundColor: c.withOpacity(.15),
                labelStyle: TextStyle(color: c),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onTap: () => _openDetail(id),
            );
          },
        ),
      ),
    );
  }
}
