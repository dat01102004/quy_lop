import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/session.dart';
import '../services/api.dart';
import '../repos/payment_repository.dart';
import '../services/network.dart';

class PaymentReviewDetailPage extends ConsumerStatefulWidget {
  final int paymentId;
  const PaymentReviewDetailPage({super.key, required this.paymentId});

  @override
  ConsumerState<PaymentReviewDetailPage> createState() =>
      _PaymentReviewDetailPageState();
}

class _PaymentReviewDetailPageState extends ConsumerState<PaymentReviewDetailPage> {
  Map<String, dynamic>? data;
  String? err;
  bool loading = true;
  final _noteCtl = TextEditingController();

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
    } catch (e) {
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approve ? 'Đã xác nhận thanh toán' : 'Đã từ chối thanh toán',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } on DioException catch (e) {
      final msg = prettyDioError(e);                 // 👈 dùng helper
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      setState(() => err = msg);
    } catch (e) {
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
    // proof_path BE trả kiểu "/storage/..." => ghép host (bỏ /api)
    final base = ref.read(dioProvider).options.baseUrl; // ví dụ http://10.0.2.2:8000/api
    final host = base.endsWith('/api') ? base.substring(0, base.length - 4) : base;
    if (proofPath.startsWith('/')) {
      return '$host$proofPath';
    }
    return '$host/$proofPath';
  }

  void _openFullImage(BuildContext context, String url) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullImageScreen(imageUrl: url),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading && data == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final d = data ?? {};
    final payerName = (d['payer_name'] ?? d['user_name'] ?? '') as String;
    final amount = (d['amount'] ?? '').toString();
    final method = (d['method'] ?? '').toString();
    final status = (d['status'] ?? '').toString();
    final invoiceId = d['invoice_id'];
    final proofUrl = _fullProofUrl(d['proof_path'] as String?);
    final createdAt = (d['created_at'] ?? '').toString();
    final verifiedBy = (d['verified_by_name'] ?? '').toString();
    final cycleName = (d['cycle_name'] ?? '').toString();

    return Scaffold(
      appBar: AppBar(title: Text('Duyệt phiếu #${widget.paymentId}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (err != null) ...[
            Text(err!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
          ],

          // Thông tin chính
          Text('Người nộp: $payerName', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('Số tiền: $amount'),
          const SizedBox(height: 6),
          Text('Phương thức: $method'),
          const SizedBox(height: 6),
          if (cycleName.isNotEmpty) Text('Kỳ thu: $cycleName'),
          if (invoiceId != null) Text('Invoice: #$invoiceId'),
          const SizedBox(height: 6),
          if (createdAt.isNotEmpty) Text('Nộp lúc: $createdAt'),
          const SizedBox(height: 6),
          if (status.isNotEmpty) Text('Trạng thái hiện tại: $status'),
          if (verifiedBy.isNotEmpty) Text('Người duyệt: $verifiedBy'),

          // Ảnh chứng từ (nhấn để phóng to)
          if (proofUrl.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Ảnh minh chứng', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: GestureDetector(
                onTap: () => _openFullImage(context, proofUrl),
                child: Hero(
                  tag: proofUrl,
                  child: Image.network(
                    proofUrl,
                    height: 240,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                    const Text('Không tải được ảnh minh chứng'),
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),
          TextField(
            controller: _noteCtl,
            decoration: const InputDecoration(
              labelText: 'Ghi chú (tuỳ chọn)',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 16),

          // Nút hành động
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: loading ? null : () => _doReview(true),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Xác nhận'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: loading ? null : () => _doReview(false),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Từ chối'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ======= Trang xem ảnh full-screen (zoom/pan) =======
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
          tag: imageUrl,
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
