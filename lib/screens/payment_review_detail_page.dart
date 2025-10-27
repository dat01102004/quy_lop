// lib/screens/payment_review_detail_page.dart
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../services/session.dart';
import '../services/api.dart';
import '../repos/payment_repository.dart';
import '../services/network.dart';
import '../theme/app_theme.dart';

class PaymentReviewDetailPage extends ConsumerStatefulWidget {
  final int paymentId;
  const PaymentReviewDetailPage({super.key, required this.paymentId});

  @override
  ConsumerState<PaymentReviewDetailPage> createState() =>
      _PaymentReviewDetailPageState();
}

class _PaymentReviewDetailPageState
    extends ConsumerState<PaymentReviewDetailPage> {
  Map<String, dynamic>? data;
  String? err;
  bool loading = true;
  final _noteCtl = TextEditingController();

  final NumberFormat _money = NumberFormat.decimalPattern('vi_VN');
  String _vnd(num v) => '${_money.format(v)} đ';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _noteCtl.dispose();
    super.dispose();
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
      final detail = await ref
          .read(paymentRepositoryProvider)
          .paymentDetail(classId: classId, paymentId: widget.paymentId);

      if (!mounted) return;
      setState(() {
        data = detail;
        err = null;
      });
    } on DioException catch (e) {
      final msg = prettyDioError(e);
      if (!mounted) return;
      setState(() => err = msg);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      const msg = 'Tải chi tiết phiếu thất bại';
      if (!mounted) return;
      setState(() => err = msg);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _doReview(bool approve) async {
    final classId = ref.read(sessionProvider).classId!;
    if (mounted) setState(() => loading = true);

    try {
      await ref.read(paymentRepositoryProvider).verifyPayment(
        classId: classId,
        paymentId: widget.paymentId,
        approve: approve,
        note: _noteCtl.text.trim().isEmpty ? null : _noteCtl.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
        Text(approve ? 'Đã xác nhận thanh toán' : 'Đã từ chối thanh toán'),
      ));
      Navigator.of(context).pop(true);
    } on DioException catch (e) {
      final msg = prettyDioError(e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      setState(() => err = msg);
    } catch (_) {
      const msg = 'Thao tác thất bại';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(msg)));
      setState(() => err = msg);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String _fullProofUrl(String? proofPath) {
    if (proofPath == null || proofPath.isEmpty) return '';
    if (proofPath.startsWith('http://') || proofPath.startsWith('https://')) {
      return proofPath;
    }
    final base = ref.read(dioProvider).options.baseUrl; // http://x/api
    final host = base.endsWith('/api') ? base.substring(0, base.length - 4) : base;
    if (proofPath.startsWith('/')) return '$host$proofPath';
    return '$host/$proofPath';
  }

  void _openFullImage(BuildContext context, String url) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _FullImageScreen(imageUrl: url)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gradient = Theme.of(context).extension<AppGradients>()?.background;

    if (loading && data == null) {
      return Container(
        decoration: gradient == null ? null : BoxDecoration(gradient: gradient),
        child: const Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final d = data ?? {};
    final payer = (d['payer_name'] ?? d['user_name'] ?? '') as String? ?? '';
    final num amountNum =
    d['amount'] is num ? d['amount'] as num : int.tryParse('${d['amount']}') ?? 0;
    final method = (d['method'] ?? '').toString();
    final status = (d['status'] ?? '').toString();
    final invoiceId = d['invoice_id'];
    final proofUrl = _fullProofUrl(d['proof_path'] as String?);
    final createdAt = (d['created_at'] ?? '').toString();
    final verifiedBy = (d['verified_by_name'] ?? '').toString();
    final cycleName = (d['cycle_name'] ?? '').toString();

    final canReview = !(status == 'verified' || status == 'invalid');

    return Container(
      decoration: gradient == null ? null : BoxDecoration(gradient: gradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          scrolledUnderElevation: 0,
          backgroundColor: Colors.transparent,
          title: Text('Duyệt phiếu #${widget.paymentId}'),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: loading || !canReview ? null : () => _doReview(true),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Xác nhận'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: loading || !canReview ? null : () => _doReview(false),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Từ chối'),
                  ),
                ),
              ],
            ),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
          children: [
            if (err != null) ...[
              Text(err!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
            ],

            // ===== Header card =====
            _GlassCard(
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor:
                    Theme.of(context).colorScheme.primaryContainer,
                    child: Text(
                      (payer.isEmpty ? '?' : payer.trim()[0]).toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(payer.isEmpty ? '(Người nộp)' : payer,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        _StatusChip(status: status),
                      ],
                    ),
                  ),
                  Text(
                    _vnd(amountNum),
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ===== Meta card =====
            _GlassCard(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (invoiceId != null)
                    _MetaChip(icon: Icons.receipt_long_outlined, text: 'Invoice #$invoiceId'),
                  if (cycleName.isNotEmpty)
                    _MetaChip(icon: Icons.event, text: cycleName),
                  if (method.isNotEmpty)
                    _MetaChip(icon: Icons.payments_outlined, text: method),
                  if (createdAt.isNotEmpty)
                    _MetaChip(icon: Icons.access_time, text: createdAt),
                  if (verifiedBy.isNotEmpty)
                    _MetaChip(icon: Icons.verified_user_outlined, text: 'Duyệt: $verifiedBy'),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ===== Proof card =====
            if (proofUrl.isNotEmpty)
              _GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ảnh minh chứng',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: GestureDetector(
                        onTap: () => _openFullImage(context, proofUrl),
                        child: Hero(
                          tag: 'proof_${widget.paymentId}',
                          child: Image.network(
                            proofUrl,
                            height: 260,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Padding(
                              padding: EdgeInsets.all(12),
                              child: Text('Không tải được ảnh minh chứng'),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 12),

            // ===== Note card =====
            _GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ghi chú (tuỳ chọn)',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _noteCtl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'Ví dụ: kiểm tra giao dịch, khớp nội dung...',
                      border: OutlineInputBorder(),
                    ),
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

/// ====== Small UI helpers ======

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    Color bg, fg, br;
    switch (s) {
      case 'verified':
      case 'paid':
        bg = Colors.green.withOpacity(.12);
        fg = Colors.green.shade800;
        br = Colors.green.withOpacity(.4);
        break;
      case 'invalid':
        bg = Colors.red.withOpacity(.12);
        fg = Colors.red.shade800;
        br = Colors.red.withOpacity(.4);
        break;
      default:
        bg = Colors.amber.withOpacity(.15);
        fg = Colors.amber.shade900;
        br = Colors.amber.withOpacity(.45);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: br),
      ),
      child: Text(
        (status.isEmpty ? 'pending' : status).toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(.9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: cs.outline),
          const SizedBox(width: 6),
          Text(text, style: Theme.of(context).textTheme.labelMedium),
        ],
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

// ======= Full-screen image viewer =======
class _FullImageScreen extends StatelessWidget {
  final String imageUrl;
  const _FullImageScreen({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Ảnh minh chứng', style: TextStyle(color: Colors.white)),
      ),
      body: Center(
        child: Hero(
          tag: 'proof_${ModalRoute.of(context)!.settings.arguments ?? imageUrl}',
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 5.0,
            child: Image.network(
              imageUrl,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Không tải được ảnh', style: TextStyle(color: Colors.white)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
