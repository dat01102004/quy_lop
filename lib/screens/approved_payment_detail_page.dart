import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../repos/payment_repository.dart';
import '../services/session.dart';
import '../services/network.dart';

class ApprovedPaymentDetailPage extends ConsumerStatefulWidget {
  final int paymentId;
  const ApprovedPaymentDetailPage({super.key, required this.paymentId});

  @override
  ConsumerState<ApprovedPaymentDetailPage> createState() =>
      _ApprovedPaymentDetailPageState();
}

class _ApprovedPaymentDetailPageState
    extends ConsumerState<ApprovedPaymentDetailPage> {
  bool _loading = true;
  String? _err;
  Map<String, dynamic>? _data;

  final _money = NumberFormat.decimalPattern('vi_VN');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final classId = ref.read(sessionProvider).classId;
    if (classId == null) {
      setState(() {
        _err = 'Chưa có lớp hiện tại';
        _loading = false;
      });
      return;
    }
    try {
      final res = await ref.read(paymentRepositoryProvider).approvedDetail(
        classId: classId,
        paymentId: widget.paymentId,
      );
      setState(() {
        _data = res;
        _err = null;
      });
    } on DioException catch (e) {
      setState(() => _err = prettyDioError(e));
    } catch (_) {
      setState(() => _err = 'Không tải được chi tiết phiếu.');
    } finally {
      setState(() => _loading = false);
    }
  }

  bool get _canInvalidate {
    final role = ref.read(sessionProvider).role ?? 'member';
    final status = (_data?['status'] ?? '').toString();
    final allowRole = role == 'owner' || role == 'treasurer';
    final allowStatus = status == 'verified' || status == 'paid';
    return allowRole && allowStatus;
  }

  Future<void> _invalidatePayment() async {
    if (!_canInvalidate) return;

    final reasonCtl = TextEditingController();
    final noteCtl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Đánh dấu KHÔNG HỢP LỆ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: reasonCtl,
              decoration: const InputDecoration(
                labelText: 'Lý do (bắt buộc)',
                hintText: 'VD: Minh chứng sai/số tiền nhầm kỳ thu...',
              ),
              maxLength: 120,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: noteCtl,
              decoration: const InputDecoration(
                labelText: 'Ghi chú (tuỳ chọn)',
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    final reason = reasonCtl.text.trim();
    final note = noteCtl.text.trim().isEmpty ? null : noteCtl.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập lý do.')),
      );
      return;
    }

    final classId = ref.read(sessionProvider).classId!;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await ref.read(paymentRepositoryProvider).invalidatePayment(
        classId: classId,
        paymentId: widget.paymentId,
        reason: reason,
        note: note,
      );
      if (!mounted) return;
      Navigator.of(context).pop(); // close spinner
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã chuyển phiếu sang KHÔNG HỢP LỆ và cập nhật sổ quỹ.'),
        ),
      );
      Navigator.of(context).pop(true); // về list -> trigger reload
    } on DioException catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(prettyDioError(e))),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Thao tác thất bại: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final d = _data ?? {};
    final status = (d['status'] ?? '').toString();

    final who = (d['payer_name'] ?? d['member_name'] ?? d['payer_email'] ?? '').toString();
    final method = (d['method'] ?? '').toString();
    final amountNum = (d['amount'] is num)
        ? (d['amount'] as num)
        : (int.tryParse('${d['amount']}') ?? 0);
    final amount = _money.format(amountNum);
    final cycleName = (d['cycle_name'] ?? '').toString();
    final invoiceId = (d['invoice_id'] ?? '').toString();
    final when = (d['approved_at'] ??
        d['invalidated_at'] ??
        d['verified_at'] ??
        d['created_at'] ??
        '')
        .toString();
    final note = (d['note'] ?? d['add_info'] ?? d['txn_ref'] ?? '').toString();
    final proof = (d['proof_path'] ?? d['proof_url'] ?? '').toString();

    // invalid meta
    final invalidReason = (d['invalid_reason'] ?? '').toString();
    final invalidNote = (d['invalid_note'] ?? '').toString();
    final invalidBy = (d['invalidated_by_name'] ?? '').toString();
    final invalidAt = (d['invalidated_at'] ?? '').toString();

    return Scaffold(
      appBar: AppBar(
        title: Text('Phiếu đã duyệt #${widget.paymentId}'),
        actions: [
          if (_canInvalidate)
            IconButton(
              icon: const Icon(Icons.block),
              tooltip: 'Đánh dấu KHÔNG HỢP LỆ',
              onPressed: _invalidatePayment,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              if (status == 'invalid')
                Chip(
                  label: const Text('invalid'),
                  backgroundColor: Colors.red.withOpacity(.12),
                  side: BorderSide(color: Colors.red.withOpacity(.5)),
                  labelStyle:
                  const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
                )
              else
                Chip(
                  label: Text(status.isEmpty ? 'verified' : status),
                  backgroundColor: Theme.of(context).colorScheme.surface,
                ),
            ],
          ),
          const SizedBox(height: 12),
          _kv('Người nộp', who),
          _kv('Số tiền', '$amount đ'),
          if (method.isNotEmpty) _kv('Phương thức', method),
          if (cycleName.isNotEmpty) _kv('Kỳ thu', cycleName),
          if (invoiceId.isNotEmpty) _kv('Invoice', '#$invoiceId'),
          if (when.isNotEmpty)
            _kv(status == 'invalid' ? 'Thời điểm đánh dấu' : 'Duyệt lúc', when),
          if (note.isNotEmpty && status != 'invalid') _kv('Ghi chú/Nội dung', note),

          // Thông tin KHÔNG HỢP LỆ (nếu có)
          if (status == 'invalid') ...[
            const SizedBox(height: 8),
            if (invalidReason.isNotEmpty) _kv('Lý do', invalidReason),
            if (invalidNote.isNotEmpty) _kv('Ghi chú', invalidNote),
            if (invalidBy.isNotEmpty) _kv('Người đánh dấu', invalidBy),
            if (invalidAt.isNotEmpty) _kv('Thời điểm', invalidAt),
          ],

          const SizedBox(height: 12),
          if (proof.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: GestureDetector(
                onTap: () => _openFullImage(context, proof),
                child: Hero(
                  tag: proof,
                  child: Image.network(
                    proof,
                    height: 220,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(
                      height: 220,
                      child: Center(child: Text('Không hiển thị được ảnh')),
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 24),

          if (_canInvalidate)
            FilledButton.icon(
              icon: const Icon(Icons.block),
              label: const Text('Đánh dấu KHÔNG HỢP LỆ'),
              onPressed: _invalidatePayment,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
            ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: RichText(
      text: TextSpan(
        style: const TextStyle(color: Colors.black87),
        children: [
          TextSpan(text: '$k: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          TextSpan(text: v),
        ],
      ),
    ),
  );

  // ======= Phóng to ảnh (zoom/pan) =======
  void _openFullImage(BuildContext context, String url) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullImageScreen(imageUrl: url),
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
