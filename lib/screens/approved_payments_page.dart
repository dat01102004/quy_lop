// lib/screens/approved_payments_page.dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../repos/payment_repository.dart';
import '../repos/fee_cycle_repository.dart';
import '../services/session.dart';
import '../services/network.dart';
import 'approved_payment_detail_page.dart';

class ApprovedPaymentsPage extends ConsumerStatefulWidget {
  final int classId;
  const ApprovedPaymentsPage({super.key, required this.classId});

  @override
  ConsumerState<ApprovedPaymentsPage> createState() => _ApprovedPaymentsPageState();
}

class _ApprovedPaymentsPageState extends ConsumerState<ApprovedPaymentsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  bool _loadingCycles = true;
  String? _errCycles;

  final NumberFormat _money = NumberFormat.decimalPattern('vi_VN');

  List<Map<String, dynamic>> _cycles = [];
  int? _feeCycleId;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadCycles();
  }

  Future<void> _loadCycles() async {
    setState(() {
      _loadingCycles = true;
      _errCycles = null;
    });
    try {
      final cycles =
      await ref.read(feeCycleRepositoryProvider).listCycles(widget.classId);
      if (!mounted) return;
      setState(() {
        _cycles = cycles;
      });
    } on DioException catch (e) {
      final msg = prettyDioError(e);
      if (!mounted) return;
      setState(() => _errCycles = msg);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      if (!mounted) return;
      const msg = 'Không tải được danh sách kỳ thu';
      setState(() => _errCycles = msg);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _loadingCycles = false);
    }
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  void _showImage(String url) {
    if (url.isEmpty) return;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: InteractiveViewer(
          minScale: .5,
          maxScale: 4,
          child: Image.network(url, fit: BoxFit.contain),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // để khi đổi quyền/lớp thì rebuild
    ref.watch(sessionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Danh sách đã duyệt'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Hợp lệ'),
            Tab(text: 'Không hợp lệ'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Bộ lọc kỳ thu
          Padding(
            padding: const EdgeInsets.all(12),
            child: _buildCycleFilter(),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _ListApprovedTab(
                  classId: widget.classId,
                  feeCycleId: _feeCycleId,
                  money: _money,
                  showImage: _showImage,
                  invalidMode: false,
                ),
                _ListApprovedTab(
                  classId: widget.classId,
                  feeCycleId: _feeCycleId,
                  money: _money,
                  showImage: _showImage,
                  invalidMode: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCycleFilter() {
    if (_loadingCycles) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errCycles != null) {
      return Text(_errCycles!, style: const TextStyle(color: Colors.red));
    }
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Chọn kỳ thu',
        border: OutlineInputBorder(),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: _feeCycleId,
          isDense: true,
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('Tất cả kỳ')),
            ..._cycles.map(
                  (c) => DropdownMenuItem<int?>(
                value: c['id'] as int,
                child: Text(c['name']?.toString() ?? 'Kỳ'),
              ),
            ),
          ],
          onChanged: (v) {
            setState(() => _feeCycleId = v);
          },
        ),
      ),
    );
  }
}

// ================== Child list tab ==================

class _ListApprovedTab extends ConsumerStatefulWidget {
  final int classId;
  final int? feeCycleId;
  final NumberFormat money;
  final void Function(String url) showImage;
  final bool invalidMode; // false: verified/paid, true: invalid

  const _ListApprovedTab({
    required this.classId,
    required this.feeCycleId,
    required this.money,
    required this.showImage,
    required this.invalidMode,
  });

  @override
  ConsumerState<_ListApprovedTab> createState() => _ListApprovedTabState();
}

class _ListApprovedTabState extends ConsumerState<_ListApprovedTab> {
  bool _loading = true;
  String? _err;
  List<Map<String, dynamic>> _items = [];

  @override
  void didUpdateWidget(covariant _ListApprovedTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.feeCycleId != widget.feeCycleId ||
        oldWidget.invalidMode != widget.invalidMode) {
      _reload();
    }
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final repo = ref.read(paymentRepositoryProvider);

      // Repo nên hỗ trợ status nullable -> truyền 'invalid' khi ở tab Không hợp lệ
      final items = await repo.listApproved(
        classId: widget.classId,
        feeCycleId: widget.feeCycleId,
        status: widget.invalidMode ? 'invalid' : null,
      );

      if (!mounted) return;
      setState(() => _items = items);
    } on DioException catch (e) {
      final msg = prettyDioError(e);
      if (!mounted) return;
      setState(() => _err = msg);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      if (!mounted) return;
      const msg = 'Không tải được danh sách';
      setState(() => _err = msg);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_err != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_err!, style: const TextStyle(color: Colors.red)),
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(child: Text('Chưa có phiếu.'));
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: _items.length,
        itemBuilder: (_, i) => _buildTile(_items[i]),
      ),
    );
  }

  Widget _buildTile(Map<String, dynamic> e) {
    final id = (e['id'] as num?)?.toInt() ?? 0;

    // Người nộp
    final who =
    (e['payer_name'] ?? e['member_name'] ?? e['payer_email'] ?? '').toString();

    // Số tiền
    final num amountNum = (e['amount'] is num)
        ? (e['amount'] as num)
        : (int.tryParse('${e['amount']}') ?? 0);
    final amount = widget.money.format(amountNum);

    // Kỳ, nội dung, thời điểm
    final cycleName =
    (e['cycle_name'] ?? e['invoice']?['cycle']?['name'] ?? e['title'] ?? '')
        .toString();

    final note = (e['txn_ref'] ?? e['invalid_reason'] ?? e['note'] ?? '').toString();

    final whenRaw = (e['approved_at'] ??
        e['invalidated_at'] ??
        e['verified_at'] ??
        e['created_at'] ??
        '')
        .toString();
    final when = formatDateTime(whenRaw);

    // Ảnh minh chứng
    final url = (e['proof_path'] ?? e['proof_url'] ?? '').toString();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        onTap: () async {
          final ok = await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ApprovedPaymentDetailPage(paymentId: id),
            ),
          );
          if (ok == true && mounted) {
            await _reload();
          }
        },
        leading: url.isEmpty
            ? const Icon(Icons.receipt_long_outlined)
            : InkWell(
          onTap: () => widget.showImage(url),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.network(
              url,
              width: 44,
              height: 44,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
              const Icon(Icons.image_not_supported_outlined),
            ),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                '$who • $amount đ',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (widget.invalidMode)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(.12),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: Colors.red.withOpacity(.5)),
                ),
                child: const Text(
                  'KHÔNG HỢP LỆ',
                  style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
        subtitle: Text([
          if (cycleName.isNotEmpty) 'Kỳ: $cycleName',
          if (note.isNotEmpty) (widget.invalidMode ? 'Lý do: ' : 'Nội dung: ') + note,
          if (when.isNotEmpty) 'Lúc: $when',
        ].join('\n')),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
