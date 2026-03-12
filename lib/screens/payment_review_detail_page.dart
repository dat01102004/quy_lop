// lib/screens/payment_review_detail_page.dart
import 'dart:ui';

import 'package:quylop/services/api.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../repos/payment_comment_repository.dart';
import '../repos/payment_repository.dart';
import '../services/network.dart';
import '../services/session.dart';
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(msg)));
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
      final msg = prettyDioError(e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      setState(() => err = msg);
    } catch (_) {
      const msg = 'Thao tác thất bại';
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(msg)));
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
    final base = ref.read(dioProvider).options.baseUrl;
    final host =
    base.endsWith('/api') ? base.substring(0, base.length - 4) : base;
    if (proofPath.startsWith('/')) return '$host$proofPath';
    return '$host/$proofPath';
  }

  void _openFullImage(BuildContext context, String url, String heroTag) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullImageScreen(imageUrl: url, heroTag: heroTag),
      ),
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
    final num amountNum = d['amount'] is num
        ? d['amount'] as num
        : int.tryParse('${d['amount']}') ?? 0;
    final method = (d['method'] ?? '').toString();
    final status = (d['status'] ?? '').toString();
    final invoiceId = d['invoice_id'];
    final proofUrl = _fullProofUrl(d['proof_path'] as String?);
    final createdAt = (d['created_at'] ?? '').toString();
    final verifiedBy = (d['verified_by_name'] ?? '').toString();
    final cycleName = (d['cycle_name'] ?? '').toString();

    final canReview = !(status == 'verified' || status == 'invalid');
    final proofHeroTag = 'proof_${widget.paymentId}';

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
                    onPressed:
                    loading || !canReview ? null : () => _doReview(true),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Xác nhận'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                    loading || !canReview ? null : () => _doReview(false),
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
                        Text(
                          payer.isEmpty ? '(Người nộp)' : payer,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
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
            _GlassCard(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (invoiceId != null)
                    _MetaChip(
                      icon: Icons.receipt_long_outlined,
                      text: 'Invoice #$invoiceId',
                    ),
                  if (cycleName.isNotEmpty)
                    _MetaChip(icon: Icons.event, text: cycleName),
                  if (method.isNotEmpty)
                    _MetaChip(icon: Icons.payments_outlined, text: method),
                  if (createdAt.isNotEmpty)
                    _MetaChip(icon: Icons.access_time, text: createdAt),
                  if (verifiedBy.isNotEmpty)
                    _MetaChip(
                      icon: Icons.verified_user_outlined,
                      text: 'Duyệt: $verifiedBy',
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (proofUrl.isNotEmpty)
              _GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ảnh minh chứng',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: GestureDetector(
                        onTap: () =>
                            _openFullImage(context, proofUrl, proofHeroTag),
                        child: Hero(
                          tag: proofHeroTag,
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
            _GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ghi chú (tuỳ chọn)',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
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
            const SizedBox(height: 12),
            PaymentCommentsSection(paymentId: widget.paymentId),
          ],
        ),
      ),
    );
  }
}

class PaymentCommentsSection extends ConsumerStatefulWidget {
  final int paymentId;

  const PaymentCommentsSection({super.key, required this.paymentId});

  @override
  ConsumerState<PaymentCommentsSection> createState() =>
      _PaymentCommentsSectionState();
}

class _PaymentCommentsSectionState
    extends ConsumerState<PaymentCommentsSection> {
  final TextEditingController _textCtl = TextEditingController();

  bool _loading = false;
  bool _sending = false;
  String? _err;
  List<_CommentNode> _comments = [];

  XFile? _attachedImage;
  int? _replyToId;
  String? _replyToName;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _textCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final sess = ref.read(sessionProvider);
    final classId = sess.classId ?? 0;

    if (classId <= 0) {
      setState(() {
        _err = 'Chưa chọn lớp — không thể tải bình luận';
        _loading = false;
      });
      return;
    }

    setState(() {
      _loading = true;
      _err = null;
    });

    try {
      final repo = ref.read(paymentCommentRepositoryProvider);
      final list = await repo.listComments(
        classId: classId,
        paymentId: widget.paymentId,
      );
      debugPrint('COMMENTS RAW: $list');

      if (!mounted) return;

      setState(() {
        _comments = _CommentNode.buildTree(list);
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = prettyDioError(e);
      setState(() {
        _err = msg;
        _loading = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _err = 'Không tải được bình luận';
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không tải được bình luận')),
      );
    }
  }

  Future<void> _pickImage() async {
    if (_sending) return;
    final img = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (!mounted) return;
    setState(() => _attachedImage = img);
  }

  Future<void> _send() async {
    final text = _textCtl.text.trim();
    if (text.isEmpty || _sending) return;

    final sess = ref.read(sessionProvider);
    final classId = sess.classId ?? 0;

    if (classId <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chưa chọn lớp — không thể gửi bình luận'),
        ),
      );
      return;
    }

    setState(() => _sending = true);

    try {
      final repo = ref.read(paymentCommentRepositoryProvider);
      final parentId = _replyToId;
      final created = await repo.createComment(
        classId: classId,
        paymentId: widget.paymentId,
        body: text,
        parentId: parentId,
      );

      if (!mounted) return;

      final normalized = Map<String, dynamic>.from(created);
      normalized.putIfAbsent('parent_id', () => parentId);
      if ((normalized['user_name'] ?? '').toString().isEmpty) {
        normalized['user_name'] = sess.name ?? 'Bạn';
      }
      if ((normalized['body'] ?? '').toString().isEmpty) {
        normalized['body'] = text;
      }
      if ((normalized['created_at'] ?? '').toString().isEmpty) {
        normalized['created_at'] = DateTime.now().toString();
      }

      final updated = [..._CommentNode.flatten(_comments), _CommentNode.fromMap(normalized)];

      _textCtl.clear();
      setState(() {
        _comments = _CommentNode.buildTree(
          updated.map((e) => e.toMap()).toList(),
        );
        _sending = false;
        _attachedImage = null;
        _replyToId = null;
        _replyToName = null;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = prettyDioError(e);
      setState(() => _sending = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gửi bình luận thất bại')),
      );
    }
  }

  Future<void> _toggleLike(_CommentNode comment) async {
    final sess = ref.read(sessionProvider);
    final classId = sess.classId ?? 0;
    if (classId <= 0 || comment.id == null) return;

    final previous = comment.clone();
    final nextLiked = !comment.isLiked;
    setState(() {
      comment.isLiked = nextLiked;
      if (nextLiked) {
        if (!comment.likedUserNames.contains(comment.currentViewerName)) {
          comment.likedUserNames = [
            ...comment.likedUserNames,
            comment.currentViewerName,
          ];
        }
      } else {
        comment.likedUserNames = comment.likedUserNames
            .where((name) => name != comment.currentViewerName)
            .toList();
      }
      comment.likeCount = comment.likedUserNames.length > comment.likeCount
          ? comment.likedUserNames.length
          : (nextLiked
          ? comment.likeCount + 1
          : (comment.likeCount > 0 ? comment.likeCount - 1 : 0));
    });

    try {
      final payload = await ref.read(paymentCommentRepositoryProvider).setLike(
        classId: classId,
        paymentId: widget.paymentId,
        commentId: comment.id!,
        like: nextLiked,
      );
      if (!mounted) return;
      setState(() {
        comment.applyLikePayload(payload, fallbackLiked: nextLiked);
      });
    } on DioException catch (_) {
      if (!mounted) return;
      setState(() {
        comment.restoreFrom(previous);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'API like chưa khớp backend. Frontend đã sẵn sàng, cần map đúng endpoint ở server.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        comment.restoreFrom(previous);
      });
    }
  }

  void _startReply(_CommentNode comment) {
    final name = comment.userName.isEmpty ? 'Thành viên' : comment.userName;
    setState(() {
      _replyToId = comment.id;
      _replyToName = name;
    });
    if (_textCtl.text.trim().isEmpty) {
      _textCtl.text = '@$name ';
      _textCtl.selection =
          TextSelection.collapsed(offset: _textCtl.text.length);
    }
  }

  void _cancelReply() {
    setState(() {
      _replyToId = null;
      _replyToName = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.chat_bubble_outline, size: 18),
              const SizedBox(width: 6),
              const Text(
                'Bình luận',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              IconButton(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(minHeight: 2),
            )
          else if (_err != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                _err!,
                style: const TextStyle(color: Colors.red),
              ),
            )
          else if (_comments.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text('Chưa có bình luận nào'),
              )
            else
              Column(
                children: _comments
                    .map(
                      (comment) => _CommentTile(
                    comment: comment,
                    level: 0,
                    onLike: _toggleLike,
                    onReply: _startReply,
                    onShowLikedUsers: (comment) {
                      if (comment.likedUserNames.isEmpty) return;
                      showModalBottomSheet<void>(
                        context: context,
                        builder: (_) => SafeArea(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: 12),
                              Text(
                                'Đã thích',
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 8),
                              Flexible(
                                child: ListView.separated(
                                  shrinkWrap: true,
                                  itemCount: comment.likedUserNames.length,
                                  separatorBuilder: (_, __) => const Divider(
                                    height: 1,
                                  ),
                                  itemBuilder: (_, index) => ListTile(
                                    leading: const Icon(Icons.favorite),
                                    title: Text(comment.likedUserNames[index]),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                )
                    .toList(),
              ),
          const SizedBox(height: 8),
          if (_replyToId != null && _replyToName != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withOpacity(.55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.reply,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Đang trả lời $_replyToName',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  GestureDetector(
                    onTap: _cancelReply,
                    child: const Icon(Icons.close, size: 16),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (_attachedImage != null) ...[
            Row(
              children: [
                const Icon(Icons.image, size: 16),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _attachedImage!.name,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _attachedImage = null),
                  icon: const Icon(Icons.close, size: 16),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              IconButton(
                onPressed: _sending ? null : _pickImage,
                icon: const Icon(Icons.camera_alt_outlined),
              ),
              Expanded(
                child: TextField(
                  controller: _textCtl,
                  decoration: InputDecoration(
                    hintText: _replyToName == null
                        ? 'Nhập bình luận...'
                        : 'Trả lời $_replyToName...',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide:
                      BorderSide(color: theme.colorScheme.outline),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: BorderSide(
                        color: theme.colorScheme.primary,
                        width: 1.2,
                      ),
                    ),
                    isDense: true,
                  ),
                  minLines: 1,
                  maxLines: 3,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.send),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  final _CommentNode comment;
  final int level;
  final ValueChanged<_CommentNode> onLike;
  final ValueChanged<_CommentNode> onReply;
  final ValueChanged<_CommentNode> onShowLikedUsers;

  const _CommentTile({
    required this.comment,
    required this.level,
    required this.onLike,
    required this.onReply,
    required this.onShowLikedUsers,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final indent = level * 22.0;
    final isReply = level > 0;
    final likedLabel = comment.likeCount > 0
        ? '${comment.likeCount} lượt thích'
        : (comment.isLiked ? 'Đã thích' : 'Thích');

    return Padding(
      padding: EdgeInsets.only(left: indent, top: 10, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: isReply ? 14 : 16,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(
                  Icons.person_outline,
                  size: isReply ? 14 : 16,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isReply
                        ? theme.colorScheme.surfaceContainerHighest
                        .withOpacity(.55)
                        : theme.colorScheme.surfaceContainerHighest
                        .withOpacity(.78),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withOpacity(.24),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              comment.userName,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (comment.parentDisplayName != null)
                            Text(
                              'trả lời @${comment.parentDisplayName}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(comment.body, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 42, top: 4),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 4,
              children: [
                if (comment.createdAt.isNotEmpty)
                  Text(
                    comment.createdAt,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                InkWell(
                  onTap: () => onLike(comment),
                  borderRadius: BorderRadius.circular(999),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        comment.isLiked
                            ? Icons.favorite
                            : Icons.favorite_border,
                        size: 16,
                        color: comment.isLiked
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        likedLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: comment.isLiked
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outline,
                          fontWeight:
                          comment.isLiked ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () => onReply(comment),
                  child: Text(
                    'Trả lời',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (comment.likedUserNames.isNotEmpty)
                  InkWell(
                    onTap: () => onShowLikedUsers(comment),
                    child: Text(
                      'Ai đã thích',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          ...comment.replies.map(
                (reply) => _CommentTile(
              comment: reply,
              level: level + 1,
              onLike: onLike,
              onReply: onReply,
              onShowLikedUsers: onShowLikedUsers,
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentNode {
  int? id;
  final int? parentId;
  final String userName;
  final String body;
  final String createdAt;
  bool isLiked;
  int likeCount;
  List<String> likedUserNames;
  final String? parentDisplayName;
  final String currentViewerName;
  final List<_CommentNode> replies;

  _CommentNode({
    required this.id,
    required this.parentId,
    required this.userName,
    required this.body,
    required this.createdAt,
    required this.isLiked,
    required this.likeCount,
    required this.likedUserNames,
    required this.parentDisplayName,
    required this.currentViewerName,
    List<_CommentNode>? replies,
  }) : replies = replies ?? [];

  factory _CommentNode.fromMap(Map<String, dynamic> map) {
    final likedUsers = _extractLikedUsers(map);
    final likeCount = _extractLikeCount(map, likedUsers.length);
    return _CommentNode(
      id: _asInt(map['id']),
      parentId: _extractParentId(map),
      userName: ((map['user_name'] ?? map['name'] ?? 'Thành viên') as Object)
          .toString(),
      body: (map['body'] ?? '').toString(),
      createdAt: (map['created_at'] ?? '').toString(),
      isLiked: _extractIsLiked(map),
      likeCount: likeCount,
      likedUserNames: likedUsers,
      parentDisplayName: _extractParentDisplayName(map),
      currentViewerName:
      (map['current_user_name'] ?? map['viewer_name'] ?? 'Bạn').toString(),
    );
  }

  static List<_CommentNode> buildTree(List<Map<String, dynamic>> raw) {
    final nodes = raw.map(_CommentNode.fromMap).toList();
    final byId = <int, _CommentNode>{
      for (final node in nodes)
        if (node.id != null) node.id!: node,
    };

    for (final node in nodes) {
      node.replies.clear();
    }

    final roots = <_CommentNode>[];
    for (final node in nodes) {
      final parent = node.parentId == null ? null : byId[node.parentId!];
      if (parent == null) {
        roots.add(node);
      } else {
        parent.replies.add(node);
      }
    }

    roots.sort(_sortNodes);
    for (final node in roots) {
      _sortDeep(node.replies);
    }
    return roots;
  }

  static List<_CommentNode> flatten(List<_CommentNode> nodes) {
    final result = <_CommentNode>[];
    for (final node in nodes) {
      result.add(node);
      result.addAll(flatten(node.replies));
    }
    return result;
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'parent_id': parentId,
    'user_name': userName,
    'body': body,
    'created_at': createdAt,
    'is_liked': isLiked,
    'like_count': likeCount,
    'liked_users': likedUserNames,
    'reply_to_name': parentDisplayName,
    'current_user_name': currentViewerName,
  };

  _CommentNode clone() => _CommentNode(
    id: id,
    parentId: parentId,
    userName: userName,
    body: body,
    createdAt: createdAt,
    isLiked: isLiked,
    likeCount: likeCount,
    likedUserNames: [...likedUserNames],
    parentDisplayName: parentDisplayName,
    currentViewerName: currentViewerName,
    replies: replies.map((e) => e.clone()).toList(),
  );

  void restoreFrom(_CommentNode other) {
    isLiked = other.isLiked;
    likeCount = other.likeCount;
    likedUserNames = [...other.likedUserNames];
  }

  void applyLikePayload(Map<String, dynamic> payload, {required bool fallbackLiked}) {
    final likedUsers = _extractLikedUsers(payload);
    if (likedUsers.isNotEmpty) {
      likedUserNames = likedUsers;
    }
    final nextLikeCount = _extractLikeCount(payload, likedUserNames.length);
    likeCount = nextLikeCount > 0 ? nextLikeCount : likedUserNames.length;
    if (payload.isNotEmpty) {
      isLiked = _extractIsLiked(payload);
    } else {
      isLiked = fallbackLiked;
    }
  }

  static void _sortDeep(List<_CommentNode> nodes) {
    nodes.sort(_sortNodes);
    for (final node in nodes) {
      _sortDeep(node.replies);
    }
  }

  static int _sortNodes(_CommentNode a, _CommentNode b) {
    final aId = a.id ?? 0;
    final bId = b.id ?? 0;
    return aId.compareTo(bId);
  }

  static int? _extractParentId(Map<String, dynamic> map) {
    return _asInt(
      map['parent_id'] ?? map['reply_to_id'] ?? map['parent_comment_id'],
    );
  }

  static String? _extractParentDisplayName(Map<String, dynamic> map) {
    final value = map['reply_to_name'] ?? map['parent_user_name'];
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static List<String> _extractLikedUsers(Map<String, dynamic> map) {
    final raw = map['liked_users'] ?? map['likers'] ?? map['likes'];
    if (raw is! List) return <String>[];
    return raw.map((item) {
      if (item is Map) {
        return (item['name'] ?? item['user_name'] ?? item['full_name'] ?? '')
            .toString();
      }
      return item.toString();
    }).where((e) => e.trim().isNotEmpty).toList();
  }

  static int _extractLikeCount(Map<String, dynamic> map, int fallback) {
    return _asInt(map['like_count'] ?? map['likes_count'] ?? map['likes']) ??
        fallback;
  }

  static bool _extractIsLiked(Map<String, dynamic> map) {
    final value = map['is_liked'] ?? map['liked'] ?? map['viewer_liked'];
    if (value is bool) return value;
    return value.toString() == '1' || value.toString().toLowerCase() == 'true';
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    Color bg;
    Color fg;
    Color br;
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
                color:
                Theme.of(context).colorScheme.outlineVariant.withOpacity(.22),
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

class _FullImageScreen extends StatelessWidget {
  final String imageUrl;
  final String heroTag;
  const _FullImageScreen({required this.imageUrl, required this.heroTag});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Ảnh minh chứng',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: Center(
        child: Hero(
          tag: heroTag,
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 5.0,
            child: Image.network(
              imageUrl,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Không tải được ảnh',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
