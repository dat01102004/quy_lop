import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../repos/fund_account_repository.dart';
class FundAccountSheet extends ConsumerStatefulWidget {
  final int classId;
  const FundAccountSheet({super.key, required this.classId});

  @override
  ConsumerState<FundAccountSheet> createState() => _FundAccountSheetState();
}

class _FundAccountSheetState extends ConsumerState<FundAccountSheet> {
  final _f = GlobalKey<FormState>();
  final _bankCtl = TextEditingController();
  final _accCtl  = TextEditingController();
  final _nameCtl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  Future<void> _prefill() async {
    try {
      final cur = await ref.read(fundAccountRepositoryProvider)
          .getFundAccount(classId: widget.classId);
      if (cur.isNotEmpty) {
        _bankCtl.text = cur['bank_code'] ?? '';
        _accCtl.text  = cur['account_number'] ?? '';
        _nameCtl.text = cur['account_name'] ?? '';
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _bankCtl.dispose(); _accCtl.dispose(); _nameCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.only(bottom: insets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Form(
          key: _f,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Tài khoản quỹ lớp', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              TextFormField(
                controller: _bankCtl,
                decoration: const InputDecoration(
                  labelText: 'Mã ngân hàng (VD: VCB, TCB, BIDV...)',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.characters,
                validator: (v) => (v==null||v.trim().isEmpty) ? 'Nhập mã ngân hàng' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _accCtl,
                decoration: const InputDecoration(labelText: 'Số tài khoản', border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
                validator: (v) => (v==null||v.trim().isEmpty) ? 'Nhập số tài khoản' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _nameCtl,
                decoration: const InputDecoration(labelText: 'Chủ tài khoản', border: OutlineInputBorder()),
                validator: (v) => (v==null||v.trim().isEmpty) ? 'Nhập chủ tài khoản' : null,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : () async {
                    if (!_f.currentState!.validate()) return;
                    setState(() => _saving = true);
                    try {
                      await ref.read(fundAccountRepositoryProvider).upsert(
                        classId: widget.classId,
                        bankCode: _bankCtl.text.trim().toUpperCase(),
                        accountNumber: _accCtl.text.trim(),
                        accountName: _nameCtl.text.trim().toUpperCase(),
                      );
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Đã lưu tài khoản quỹ lớp')),
                      );
                      Navigator.pop(context, true);
                    } on DioException catch (e) {
                      final msg = e.response?.data?['message']?.toString() ?? 'Lưu thất bại';
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                      }
                    } finally {
                      if (mounted) setState(() => _saving = false);
                    }
                  },
                  icon: const Icon(Icons.save),
                  label: const Text('Lưu'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
