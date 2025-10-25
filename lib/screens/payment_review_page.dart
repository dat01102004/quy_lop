import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/session.dart';
import '../repos/payment_repository.dart';
import '../services/network.dart';
import 'payment_review_detail_page.dart';

class PaymentReviewPage extends ConsumerStatefulWidget {
  const PaymentReviewPage({super.key});
  @override
  ConsumerState<PaymentReviewPage> createState() => _PaymentReviewPageState();
}

class _PaymentReviewPageState extends ConsumerState<PaymentReviewPage> {
  List<Map<String, dynamic>> groups = [];
  String? err;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final classId = ref.read(sessionProvider).classId;
    if (classId == null) {
      if (!mounted) return;
      setState(() {
        err = 'Chưa có lớp hiện tại';
        loading = false;
      });
      return;
    }

    if (mounted) setState(() => loading = true);

    try {
      final list =
      await ref.read(paymentRepositoryProvider).listPaymentsGrouped(classId);
      if (!mounted) return;
      setState(() {
        groups = list;
        err = null;
      });
    } on DioException catch (e) {
      final msg = prettyDioError(e);
      if (!mounted) return;
      setState(() => err = msg);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      const msg = 'Tải danh sách phiếu nộp thất bại';
      setState(() => err = msg);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading && groups.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Phiếu nộp chờ duyệt')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: groups.length + (err != null ? 1 : 0),
          itemBuilder: (_, i) {
            // Nếu có lỗi, hiển thị 1 item đầu để báo lỗi
            if (err != null && i == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(err!, style: const TextStyle(color: Colors.red)),
              );
            }

            final idx = err != null ? i - 1 : i;
            final g = groups[idx];
            final payments = (g['payments'] as List?) ?? const [];

            return Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 12),
              child: ExpansionTile(
                title: Text(g['cycle_name']?.toString() ?? 'Kỳ thu'),
                subtitle: Text('${payments.length} phiếu chờ duyệt'),
                children: [
                  for (final p in payments)
                    ListTile(
                      title: Text(p['payer_name']?.toString() ?? ''),
                      subtitle: Text(
                          'Invoice #${p['invoice_id']} • Số tiền: ${p['amount']}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context)
                            .push(
                          MaterialPageRoute(
                            builder: (_) => PaymentReviewDetailPage(
                              paymentId: (p['id'] as num).toInt(),
                            ),
                          ),
                        )
                            .then((changed) {
                          if (changed == true) _load();
                        });
                      },
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
