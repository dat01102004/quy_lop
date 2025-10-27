// lib/screens/payment_review_page.dart
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../services/session.dart';
import '../repos/payment_repository.dart';
import '../services/network.dart';
import '../theme/app_theme.dart';
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

  final NumberFormat _money = NumberFormat.decimalPattern('vi_VN');
  String _vnd(num v) => '${_money.format(v)} đ';

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
      final list = await ref.read(paymentRepositoryProvider).listPaymentsGrouped(classId);
      if (!mounted) return;
      setState(() {
        groups = list;
        err = null;
      });
    } on DioException catch (e) {
      final msg = prettyDioError(e);
      if (!mounted) return;
      setState(() => err = msg);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      if (!mounted) return;
      const msg = 'Tải danh sách phiếu nộp thất bại';
      setState(() => err = msg);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gradient = Theme.of(context).extension<AppGradients>()?.background;

    if (loading && groups.isEmpty) {
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
          title: const Text('Phiếu nộp chờ duyệt'),
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: groups.isEmpty ? 1 : groups.length + (err != null ? 1 : 0),
            itemBuilder: (_, i) {
              // không có dữ liệu
              if (groups.isEmpty) {
                return _EmptyCard(message: err ?? 'Chưa có phiếu chờ duyệt.');
              }

              // item báo lỗi (nếu có)
              if (err != null && i == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(err!, style: const TextStyle(color: Colors.red)),
                );
              }

              final idx = err != null ? i - 1 : i;
              final g = groups[idx];
              final payments = (g['payments'] as List?) ?? const [];

              return _GroupCard(
                title: g['cycle_name']?.toString() ?? 'Kỳ thu',
                count: payments.length,
                children: [
                  for (final p in payments)
                    _PaymentRow(
                      data: Map<String, dynamic>.from(p),
                      money: _vnd,
                      onTap: () async {
                        final changed = await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PaymentReviewDetailPage(
                              paymentId: (p['id'] as num).toInt(),
                            ),
                          ),
                        );
                        if (changed == true) _load();
                      },
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// ================== UI bits ==================

class _GroupCard extends StatefulWidget {
  final String title;
  final int count;
  final List<Widget> children;
  const _GroupCard({
    required this.title,
    required this.count,
    required this.children,
  });

  @override
  State<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends State<_GroupCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text('${widget.count} phiếu',
                      style: Theme.of(context).textTheme.labelMedium),
                ),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: _expanded ? .5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.expand_more),
                ),
              ],
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              children: [
                const SizedBox(height: 8),
                for (int i = 0; i < widget.children.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      color: Theme.of(context).colorScheme.outlineVariant.withOpacity(.4),
                    ),
                  widget.children[i],
                ],
              ],
            ),
            crossFadeState:
            _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  final Map<String, dynamic> data;
  final String Function(num) money;
  final VoidCallback onTap;
  const _PaymentRow({
    required this.data,
    required this.money,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // fields có thể có
    final payer = (data['payer_name'] ??
        data['member_name'] ??
        data['payer_email'] ??
        '')
        .toString();

    final num amountNum = (data['amount'] is num)
        ? (data['amount'] as num)
        : (int.tryParse('${data['amount']}') ?? 0);

    final invId = (data['invoice_id']?.toString() ?? '');
    final when = (data['created_at'] ?? '').toString();
    final proof = (data['proof_url'] ?? data['proof_path'] ?? '').toString();

    String _initial(String s) => s.isEmpty ? '?' : s.trim()[0].toUpperCase();

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // avatar / proof thumb
            SizedBox(
              width: 48,
              height: 48,
              child: proof.isEmpty
                  ? CircleAvatar(
                backgroundColor:
                Theme.of(context).colorScheme.primaryContainer,
                child: Text(
                  _initial(payer),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              )
                  : ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  proof,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => CircleAvatar(
                    backgroundColor:
                    Theme.of(context).colorScheme.primaryContainer,
                    child: Text(
                      _initial(payer),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // texts
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // payer + amount
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          payer.isEmpty ? '(Người nộp)' : payer,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        money(amountNum),
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (invId.isNotEmpty)
                        _MetaChip(
                          icon: Icons.receipt_long_outlined,
                          text: 'Hóa đơn #$invId',
                        ),
                      if (when.isNotEmpty) const SizedBox(width: 6),
                      if (when.isNotEmpty)
                        _MetaChip(
                          icon: Icons.access_time,
                          text: when,
                        ),
                      const Spacer(),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _MetaChip({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(.9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: cs.outline),
          const SizedBox(width: 4),
          Text(text, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String message;
  const _EmptyCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Row(
        children: [
          const Icon(Icons.inbox_outlined, size: 28),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surface.withOpacity(.78);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            decoration: BoxDecoration(
              color: base,
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant.withOpacity(.22),
              ),
              borderRadius: BorderRadius.circular(16),
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
      ),
    );
  }
}
