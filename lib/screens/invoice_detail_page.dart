import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../repos/invoice_repository.dart';
import '../repos/fee_cycle_repository.dart';
import '../repos/fund_account_repository.dart';
import '../services/session.dart';
import '../services/network.dart';

class InvoiceDetailPage extends ConsumerStatefulWidget {
  final int invoiceId;
  const InvoiceDetailPage({super.key, required this.invoiceId});

  @override
  ConsumerState<InvoiceDetailPage> createState() => _InvoiceDetailPageState();
}

class _InvoiceDetailPageState extends ConsumerState<InvoiceDetailPage> {
  Map<String, dynamic>? data;
  String? err;
  bool loading = true;

  final _amountCtl = TextEditingController();
  String _method = 'bank';
  File? _proof;

  // tránh double-tap
  bool _submitting = false;

  // ====== Bank transfer state ======
  Map<String, String>? _bank; // {bank_code, account_number, account_name}
  bool _loadingBank = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amountCtl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x != null) setState(() => _proof = File(x.path));
  }

  Future<void> _load() async {
    final s = ref.read(sessionProvider);
    final classId = s.classId;
    if (classId == null) {
      setState(() {
        err = 'Bạn chưa tham gia lớp nào';
        loading = false;
      });
      return;
    }

    try {
      final detail = await ref.read(invoiceRepositoryProvider).invoiceDetail(classId, widget.invoiceId);

      // ---- AppBar title: ưu tiên tên kỳ thu, fallback gọi listCycles nếu thiếu
      final fc = (detail['fee_cycle'] ?? detail['cycle']) as Map<String, dynamic>?;
      final idStr = (detail['id'] ?? '').toString();

      String? title = (detail['title'] as String?) ?? (fc?['name'] as String?);
      if (title == null) {
        final cycleId = detail['fee_cycle_id'] ?? detail['cycle_id'] ?? fc?['id'];
        if (cycleId != null) {
          title = await _tryFetchCycleName(classId, cycleId);
        }
      }
      title ??= 'Invoice #$idStr';

      setState(() {
        data = {...detail, 'title': title};
        err = null;
      });

      _amountCtl.text = (detail['amount'] ?? '').toString();

      // Nếu đang ở chế độ chuyển khoản thì nạp thông tin TK ngay
      if (_method == 'bank') {
        await _ensureBankLoaded(classId);
      }
    } on DioException catch (e) {
      final msg = prettyDioError(e);
      setState(() => err = msg);
    } catch (e) {
      setState(() => err = e.toString());
    } finally {
      setState(() => loading = false);
    }
  }

  /// Fallback: gọi danh sách kỳ thu để tìm tên theo id
  Future<String?> _tryFetchCycleName(int classId, dynamic cycleId) async {
    try {
      final cycles = await ref.read(feeCycleRepositoryProvider).listCycles(classId);
      final cidStr = cycleId.toString();
      final picked = cycles.firstWhere(
            (e) => e['id'].toString() == cidStr,
        orElse: () => const {},
      );
      final name = picked['name'];
      return (name is String && name.isNotEmpty) ? name : null;
    } catch (_) {
      return null;
    }
  }

  // ===== Bank helpers =====

  Future<void> _ensureBankLoaded(int classId) async {
    if (_bank != null && (_bank!['account_number']?.isNotEmpty ?? false)) return;
    setState(() => _loadingBank = true);
    try {
      final resp = await ref.read(fundAccountRepositoryProvider).getFundAccount(classId: classId);
      setState(() {
        _bank = {
          'bank_code': (resp['bank_code'] ?? '').toString(),
          'account_number': (resp['account_number'] ?? '').toString(),
          'account_name': (resp['account_name'] ?? '').toString(),
        };
      });
    } catch (_) {
      // giữ im lặng, UI sẽ báo "chưa cấu hình" bên dưới
    } finally {
      if (mounted) setState(() => _loadingBank = false);
    }
  }

  String _vietQrUrl({
    required String bankCode,
    required String accountNumber,
    required int? amount,
    required String addInfo,
    required String accountName,
  }) {
    final q = <String, String>{
      if (amount != null && amount > 0) 'amount': amount.toString(),
      'addInfo': addInfo,
      'accountName': accountName,
    }.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');

    // compact2 = QR kèm thông tin gọn; có thể đổi 'compact'/'qr_only'
    return 'https://img.vietqr.io/image/$bankCode-$accountNumber-compact2.png?$q';
  }

  String _suggestedAddInfo(Map<String, dynamic> d) {
    // gợi ý nội dung CK: mã hoá đơn + tên người nộp (nếu có)
    final id = d['id']?.toString() ?? widget.invoiceId.toString();
    final who = (d['for_user_name'] ?? d['student_name'] ?? '').toString();
    return who.isNotEmpty ? 'Lop $id - $who' : 'Lop $id';
  }

  Widget _kv(String k, String v) => RichText(
    text: TextSpan(
      style: const TextStyle(color: Colors.black87),
      children: [
        TextSpan(text: '$k: ', style: const TextStyle(fontWeight: FontWeight.w600)),
        TextSpan(text: v),
      ],
    ),
  );

  // ====== TÍNH QUÁ HẠN & CHO PHÉP NỘP MUỘN ======
  bool _isOverdueDisallowed(Map<String, dynamic> d) {
    final fc = d['fee_cycle'] as Map<String, dynamic>?;
    if (fc == null) return false;

    final dueStr = fc['due_date']?.toString();
    if (dueStr == null || dueStr.isEmpty) return false;

    final due = DateTime.tryParse(dueStr);
    if (due == null) return false;

    final allowLateVal = fc['allow_late'];
    final allowLate = allowLateVal == true ||
        allowLateVal == 1 ||
        (allowLateVal is String && allowLateVal.toLowerCase() == 'true');

    // so sánh đến hết ngày hạn nộp
    final dueEnd = DateTime(due.year, due.month, due.day, 23, 59, 59);
    final now = DateTime.now();

    final isOverdue = now.isAfter(dueEnd);
    return isOverdue && !allowLate;
  }

  Future<void> _submitPayment() async {
    if (_submitting) return;

    final s = ref.read(sessionProvider);
    final classId = s.classId!;
    final amount = int.tryParse(_amountCtl.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Số tiền không hợp lệ')),
      );
      return;
    }

    setState(() => _submitting = true);

    // Hiển thị spinner modal
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await ref.read(invoiceRepositoryProvider).submitPayment(
        classId: classId,
        invoiceId: widget.invoiceId,
        amount: amount,
        method: _method,
        proofImage: _proof,
      );

      if (!mounted) return;

      // đóng spinner
      Navigator.of(context).pop();

      // pop về màn danh sách và báo đã thay đổi để refresh
      Navigator.of(context).pop(true);
    } on DioException catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // đóng spinner
      final msg = prettyDioError(e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // đóng spinner
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nộp tiền thất bại: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ===== Fullscreen helpers =====
  void _openFullImageFile(File file) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _FullImageFileScreen(file: file)),
    );
  }

  void _openFullImageNetwork(String url) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _FullImageNetworkScreen(imageUrl: url)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading && data == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final d = data ?? {};
    final status = (d['status'] ?? '').toString();
    final title = (d['title'] ?? 'Invoice #${widget.invoiceId}').toString();
    final amount = d['amount'];
    final role = ref.watch(sessionProvider).role ?? 'member';
    final IsTreasurerLike = role == 'owner' || role == 'treasurer';
    final canSubmitServer = d['can_submit'] == true;

    // FE tự chặn thêm nếu quá hạn & không cho nộp muộn
    final overdueDisallowed = _isOverdueDisallowed(d);
    final canSubmit = canSubmitServer && !overdueDisallowed;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (err != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(err!, style: const TextStyle(color: Colors.red)),
            ),

          Row(
            children: [
              Chip(
                label: Text(status.isEmpty ? 'unknown' : status),
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            ],
          ),

          const SizedBox(height: 8),
          Text('Số tiền phải nộp: ${amount ?? '-'}'),
          if (d['fee_cycle']?['term'] != null) ...[
            const SizedBox(height: 4),
            Text('Kỳ thu: ${d['fee_cycle']['term']}'),
          ],
          if (d['fee_cycle']?['due_date'] != null) ...[
            const SizedBox(height: 4),
            Text('Hạn nộp: ${formatDateOnly(d['fee_cycle']['due_date']?.toString())}'),
            // hoặc muốn cả giờ: formatDateTime(...)
          ],

          const SizedBox(height: 12),

          // ====== Banner quá hạn ======
          if (overdueDisallowed) ...[
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Theme.of(context).colorScheme.onErrorContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Kỳ thu đã quá hạn và KHÔNG cho phép nộp muộn. Vui lòng liên hệ thủ quỹ/owner.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],

          const Divider(),
          const SizedBox(height: 8),

          if (!canSubmitServer && !overdueDisallowed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Hoá đơn đã được duyệt.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),


          const Text('Nộp tiền', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _amountCtl,
            enabled: canSubmit,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Số tiền',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) {
              if (_method == 'bank') setState(() {});
            },
          ),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Phương thức',
              border: OutlineInputBorder(),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _method,
                isDense: true,
                items: const [
                  DropdownMenuItem(value: 'bank', child: Text('Chuyển khoản ngân hàng')),
                  DropdownMenuItem(value: 'cash', child: Text('Tiền mặt')),
                ],
                onChanged: canSubmit
                    ? (v) async {
                  final next = v ?? 'bank';
                  setState(() => _method = next);
                  if (next == 'bank') {
                    final clsId = ref.read(sessionProvider).classId ?? 0;
                    if (clsId > 0) {
                      await _ensureBankLoaded(clsId);
                    }
                  }
                }
                    : null,
              ),
            ),
          ),

          // ===== Bank card + QR =====
          if (canSubmit && _method == 'bank') ...[
            const SizedBox(height: 12),
            _bankCard(d),
          ],

          // ===== Preview ảnh minh chứng (tap để fullscreen) =====
          if (_proof != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: GestureDetector(
                onTap: () => _openFullImageFile(_proof!),
                child: Hero(
                  tag: _proof!.path,
                  child: Image.file(
                    _proof!,
                    height: 240,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: 12),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: canSubmit ? _pickImage : null,
                icon: const Icon(Icons.image),
                label: const Text('Chọn ảnh minh chứng'),
              ),
              const SizedBox(width: 12),
              if (_proof != null)
                Expanded(
                  child: Text(
                    _proof!.path.split('/').last,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: (!canSubmit || status == 'paid' || status == 'verified' || _submitting)
                ? null
                : _submitPayment,
            icon: const Icon(Icons.send),
            label: const Text('Gửi phiếu nộp'),
          ),
        ],
      ),
    );
  }

  Widget _bankCard(Map<String, dynamic> invoice) {
    if (_loadingBank) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (_bank == null || (_bank!['account_number']?.isEmpty ?? true)) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text('Chưa cấu hình tài khoản quỹ lớp. Liên hệ thủ quỹ/owner.'),
        ),
      );
    }

    final bankCode = _bank!['bank_code']!;
    final accNo = _bank!['account_number']!;
    final accName = _bank!['account_name']!;
    final amount = int.tryParse(_amountCtl.text.replaceAll(RegExp(r'[^0-9]'), ''));
    final addInfo = _suggestedAddInfo(invoice);

    final qrUrl = _vietQrUrl(
      bankCode: bankCode,
      accountNumber: accNo,
      amount: amount,
      addInfo: addInfo,
      accountName: accName,
    );

    return Card(
      elevation: 0,
      color: const Color(0xFFF6F2FA),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Thông tin chuyển khoản',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  _kv('Ngân hàng', bankCode),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(child: _kv('Số tài khoản', accNo)),
                      IconButton(
                        tooltip: 'Copy STK',
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: accNo));
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Đã sao chép số tài khoản')),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _kv('Chủ TK', accName),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(child: _kv('Nội dung CK', addInfo)),
                      IconButton(
                        tooltip: 'Copy nội dung',
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: addInfo));
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Đã sao chép nội dung')),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // QR (tap để fullscreen)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: GestureDetector(
                onTap: () => _openFullImageNetwork(qrUrl),
                child: Hero(
                  tag: qrUrl,
                  child: Image.network(
                    qrUrl,
                    width: 148,
                    height: 148,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(
                      width: 148,
                      height: 148,
                      child: Center(child: Text('QR lỗi')),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ======= Screens xem ảnh full-screen =======

class _FullImageNetworkScreen extends StatelessWidget {
  final String imageUrl;
  const _FullImageNetworkScreen({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Xem ảnh', style: TextStyle(color: Colors.white)),
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

class _FullImageFileScreen extends StatelessWidget {
  final File file;
  const _FullImageFileScreen({required this.file});

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
          tag: file.path,
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 5.0,
            child: Image.file(
              file,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Không mở được ảnh', style: TextStyle(color: Colors.white)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
