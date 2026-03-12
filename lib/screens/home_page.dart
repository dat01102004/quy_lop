// lib/screens/home_page.dart
import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../repos/auth_repository.dart';
import '../repos/class_repository.dart';
import '../repos/fund_account_repository.dart';
import '../services/session.dart';
import '../services/network.dart';        // prettyDioError
import '../services/dio_provider.dart';   // dioProvider
import '../providers/unread_notification_provider.dart';

import 'profile/profile_page.dart';
import 'class_list_page.dart';
import 'class_members_page.dart';
import 'profile/fund_account_sheet.dart';
import '../providers/fund_notification_providers.dart';

/// ================== UI CONFIG (đúng tên icon trong assets/icon) ==================
const _kIcon = (
myInvoices: 'assets/icon/hoadoncuatoi.png',
reviewPayments: 'assets/icon/duyetphieunop.png',
approved: 'assets/icon/hoadondaduyet.png',
notPaid: 'assets/icon/danhsachchuanop.png',
expenses: 'assets/icon/khoanchi.png',
generate: 'assets/icon/phathoadon.png',
members: 'assets/icon/thanhvienlop.png',
fund: 'assets/icon/taikhoanquy.png',
clazz: null, // ko có file riêng -> fallback icon
);

/// Mini icons “Tài khoản quỹ”
const List<String> _kFundAccountMiniIcons = [
  'assets/icon/taikhoanquy.png',
];

/// ====== Model thông báo rất gọn ======
/// ====== Model thông báo rất gọn (khớp bảng notifications) ======
class _Notif {
  final int id;
  final String type;   // due_reminder | income | expense | expense_comment...
  final String title;
  final String body;   // nội dung chi tiết (cột body)
  final int amount;    // lấy từ cột amount nếu có, hoặc parse từ body
  final DateTime createdAt;
  bool read;

  _Notif({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.amount,
    required this.createdAt,
    this.read = false,
  });

  factory _Notif.fromJson(Map<String, dynamic> j) {
    int amount = _toInt(j['amount']); // nếu bảng không có amount -> sẽ là 0

    // Nếu amount = 0 thì thử parse trong body kiểu: "Số tiền: 100000 - Hạn: ..."
    final body = (j['body'] ?? '').toString();
    if (amount == 0 && body.isNotEmpty) {
      final m = RegExp(r'Số tiền:\s*([0-9]+)').firstMatch(body);
      if (m != null) {
        amount = int.tryParse(m.group(1)!) ?? 0;
      }
    }

    final createdRaw = (j['sent_at'] ?? j['created_at'] ?? '').toString();
    DateTime created;
    try {
      created = DateTime.parse(createdRaw).toLocal();
    } catch (_) {
      created = DateTime.now();
    }

    final isReadRaw = j['is_read'] ?? j['read'] ?? 0;
    final isRead = switch (isReadRaw) {
      bool b => b,
      num n => n != 0,
      _ => isReadRaw.toString() == '1',
    };

    return _Notif(
      id: _toInt(j['id']),
      type: (j['type'] ?? '').toString(),
      title: (j['title'] ?? '').toString(),
      body: body,
      amount: amount,
      createdAt: created,
      read: isRead,
    );
  }

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}


class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});
  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  Map<String, dynamic>? me;
  String? err;

  String? _className;
  num? _balance;

  // ====== state thông báo
  List<_Notif> _notifs = const [];
  bool get _hasUnread => _notifs.any((n) => !n.read);

  @override
  void initState() {
    super.initState();
    _loadMe().then((_) async {
      await _loadCurrentClassInfo();
      await _loadNotifications(); // tải thông báo
    });
  }

  Future<void> _fallbackHydrateIfNeeded() async {
    final s = ref.read(sessionProvider);
    if (s.token != null && s.classId == null) {
      try {
        final classes = await ref.read(classRepositoryProvider).myClasses();
        if (classes.isNotEmpty) {
          Map<String, dynamic> picked = classes.first;
          for (final c in classes) {
            if ((c['member_status'] ?? 'active') == 'active') {
              picked = c;
              break;
            }
          }
          final classIdAny = (picked['id'] ?? picked['class_id']);
          final role = (picked['role'] ?? 'member').toString();
          if (classIdAny != null) {
            final idInt = classIdAny is int
                ? classIdAny
                : int.tryParse(classIdAny.toString());
            if (idInt != null) {
              await ref.read(sessionProvider.notifier).setClass(idInt);
              await ref.read(sessionProvider.notifier).setRole(role);
            }
          }
          if (mounted) setState(() {});
        }
      } catch (_) {}
    }
  }

  Future<void> _loadMe() async {
    try {
      final data = await ref.read(authRepositoryProvider).me();
      if (!mounted) return;
      setState(() {
        me = data;
        err = null;
      });
      await _fallbackHydrateIfNeeded();
    } on DioException catch (e) {
      final msg = prettyDioError(e);
      if (mounted) {
        setState(() => err = msg);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (_) {
      const msg = 'Có lỗi xảy ra';
      if (mounted) {
        setState(() => err = msg);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text(msg)));
      }
    }
  }

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  Future<void> _loadCurrentClassInfo() async {
    final s = ref.read(sessionProvider);
    if (s.classId == null) {
      setState(() {
        _className = null;
        _balance = null;
      });
      return;
    }
    try {
      final summary = await ref
          .read(fundAccountRepositoryProvider)
          .getSummary(classId: s.classId!);
      final balance = _toInt(summary['balance']);
      setState(() => _balance = balance);

      if (_className == null) {
        final classes = await ref.read(classRepositoryProvider).myClasses();
        final hit = classes.firstWhere(
              (c) => (c['id'] == s.classId),
          orElse: () => {},
        );
        if (hit.isNotEmpty) {
          setState(() => _className = (hit['name'] ?? '').toString());
        }
      }
    } catch (_) {}
  }

  /// ====== LOAD thông báo thu/chi
  /// ====== LOAD thông báo (dùng FundNotificationRepository) ======
  Future<void> _loadNotifications() async {
    try {
      final repo = ref.read(fundNotificationRepositoryProvider);
      final list = await repo.getNotifications(page: 1);
      if (!mounted) return;

      final items = list
          .map((e) => _Notif.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      setState(() => _notifs = items);
      // _hasUnread dùng _notifs để hiện chấm đỏ ở icon chuông
    } catch (_) {
      // Có thể log hoặc hiển thị SnackBar nếu muốn
    }
  }


  /// Đánh dấu tất cả thông báo đang hiển thị là đã đọc (trên client)
  void _markAllRead() {
    setState(() {
      for (final n in _notifs) {
        n.read = true;
      }
    });

    // Đồng bộ badge: để FutureProvider tự gọi lại API getUnreadCount()
    ref.invalidate(unreadNotificationCountProvider);

    // (Tuỳ ý) nếu BE có API mark-all-read thì gọi thêm:
    // final dio = ref.read(dioProvider);
    // dio.post('/notifications/read-all');
  }

  void _openNotificationsSheet() {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _NotificationsSheet(
        items: _notifs,
        onMarkAllRead: () {
          _markAllRead();
          Navigator.pop(context);
        },
        onOpenLedger: () {
          Navigator.pop(context);
          Navigator.of(context).pushNamed('/reports/ledger');
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider);
    final displayName = s.name ?? (me?['name'] as String?) ?? '';
    final isTreasurer = (s.role == 'treasurer' || s.role == 'owner');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        gradient: isDark
            ? const LinearGradient(
          colors: [Color(0xFF2F1156), Color(0xFF0F172A)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        )
            : const LinearGradient(
          colors: [Color(0xFFF2F5FF), Color(0xFFFFFFFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          scrolledUnderElevation: 0,
          backgroundColor: Colors.transparent,
          title: const Text('QUỸ LỚP',
              style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [
            IconButton(
              tooltip: 'Sổ quỹ',
              icon: const Icon(Icons.menu_book_outlined),
              onPressed: () =>
                  Navigator.of(context).pushNamed('/reports/ledger'),
            ),
            IconButton(
              tooltip: 'Làm mới',
              onPressed: () async {
                await _loadMe();
                await _loadCurrentClassInfo();
                await _loadNotifications();
              },
              icon: const Icon(Icons.refresh),
            ),

            // 🔔 Chuông thông báo (thay menu 3 chấm)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    tooltip: 'Thông báo thu/chi',
                    onPressed: _openNotificationsSheet,
                    icon: const Icon(Icons.notifications_none_rounded),
                  ),
                  if (_hasUnread)
                    Positioned(
                      right: 8,
                      top: 10,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            await _loadMe();
            await _loadCurrentClassInfo();
            await _loadNotifications();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              if (err != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child:
                  Text(err!, style: const TextStyle(color: Colors.red)),
                ),

              _GreetingCardModern(
                name: displayName,
                email: s.email ?? (me?['email'] as String?) ?? '',
                role: s.role ?? 'member',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ProfilePage(),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              if (s.classId == null)
                _EmptyClassCardModern(
                    onJoin: () => Navigator.of(context).pushNamed('/join'))
              else
                _CurrentClassCardModern(
                  classId: s.classId!,
                  className: _className ?? 'Lớp đã tham gia',
                  balance: _balance,
                  showFundShortcuts:
                  isTreasurer, // Owner/Thủ quỹ mới có icon mini
                  fundMiniIcons: _kFundAccountMiniIcons,
                  onPickClass: () async {
                    final picked =
                    await Navigator.of(context).push<Map<String, dynamic>>(
                      MaterialPageRoute(
                        builder: (_) => const ClassListPage(),
                      ),
                    );
                    if (picked != null) {
                      setState(() =>
                      _className = (picked['name'] ?? '').toString());
                      await _loadCurrentClassInfo();
                    }
                  },
                  // luôn hiển thị nút thành viên
                  onOpenMembers: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          ClassMembersPage(classId: s.classId!),
                    ),
                  ),
                ),

              const SizedBox(height: 18),
              const _SectionTitle(title: 'Tính năng nhanh'),
              const SizedBox(height: 10),

              // Lưới Ô VUÔNG (icon to + text dưới)
              _ActionsSquareGrid(
                children: [
                  _ActionSquareCard(
                    assetIcon: _kIcon.myInvoices,
                    fallbackIcon: Icons.receipt_long,
                    title: 'Hóa đơn của tôi',
                    subtitle: 'Theo dõi & thanh toán',
                    onTap: () =>
                        Navigator.of(context).pushNamed('/invoices'),
                  ),
                  if (isTreasurer)
                    _ActionSquareCard(
                      assetIcon: _kIcon.reviewPayments,
                      fallbackIcon: Icons.verified,
                      title: 'Duyệt phiếu nộp',
                      subtitle: 'Xử lý chứng từ',
                      onTap: () => Navigator.of(context)
                          .pushNamed('/payments/review'),
                    ),
                  _ActionSquareCard(
                    assetIcon: _kIcon.approved,
                    fallbackIcon: Icons.fact_check,
                    title: 'Hoá đơn đã duyệt',
                    subtitle: 'Danh sách đã thanh toán',
                    onTap: () => Navigator.of(context)
                        .pushNamed('/payments/approved'),
                  ),
                  if (isTreasurer)
                    _ActionSquareCard(
                      assetIcon: _kIcon.notPaid,
                      fallbackIcon: Icons.fact_check,
                      title: 'Danh sách chưa nộp',
                      subtitle: 'Thành viên chưa nộp',
                      onTap: () =>
                          Navigator.of(context).pushNamed('/reports/fee'),
                    ),
                  _ActionSquareCard(
                    assetIcon: _kIcon.expenses,
                    fallbackIcon: Icons.payments_outlined,
                    title: 'Khoản chi',
                    subtitle: 'Ghi & xem chi',
                    onTap: () =>
                        Navigator.of(context).pushNamed('/expenses'),
                  ),
                  if (isTreasurer)
                    _ActionSquareCard(
                      assetIcon: _kIcon.generate,
                      fallbackIcon: Icons.upload_file,
                      title: 'Phát hóa đơn',
                      subtitle: 'Tạo kỳ thu nhanh',
                      onTap: () => Navigator.of(context)
                          .pushNamed('/fee-cycles/generate'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ================== NOTIFICATIONS SHEET ==================
class _NotificationsSheet extends StatelessWidget {
  final List<_Notif> items;
  final VoidCallback onMarkAllRead;
  final VoidCallback onOpenLedger;
  const _NotificationsSheet({
    required this.items,
    required this.onMarkAllRead,
    required this.onOpenLedger,
  });

  String _fmtVn(int v) =>
      '${NumberFormat.decimalPattern('vi_VN').format(v)} đ';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text('Thông báo thu/chi',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const Spacer(),
                TextButton.icon(
                  onPressed: onOpenLedger,
                  icon: const Icon(Icons.menu_book_outlined, size: 18),
                  label: const Text('Xem sổ quỹ'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Flexible(
              child: items.isEmpty
                  ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Chưa có thông báo'),
              )
                  : ListView.separated(
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: cs.outlineVariant),
                itemBuilder: (ctx, i) {
                  final n = items[i];
                  final isIncome = n.type == 'income' || n.type == 'due_reminder';
                  final icon = isIncome ? Icons.trending_up : Icons.trending_down;
                  final color = isIncome ? Colors.green : Colors.red;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: cs.primaryContainer,
                      child: Icon(icon, color: color),
                    ),
                    title: Text(n.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      n.body.isNotEmpty
                          ? n.body
                          : '${n.createdAt.hour.toString().padLeft(2, '0')}:'
                          '${n.createdAt.minute.toString().padLeft(2, '0')} '
                          '${n.createdAt.day.toString().padLeft(2, '0')}/'
                          '${n.createdAt.month.toString().padLeft(2, '0')}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: cs.outline),
                    ),

                    trailing: Text(
                      (isIncome ? '+ ' : '- ') + _fmtVn(n.amount),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onMarkAllRead,
                    icon: const Icon(Icons.done_all),
                    label: const Text('Đánh dấu đã đọc'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Đóng'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// ================== WIDGETS DÙNG CHUNG ==================

class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color? color;
  const _GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 20,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final base =
    (color ?? Theme.of(context).colorScheme.surface).withOpacity(.75);
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          decoration: BoxDecoration(
            color: base,
            border: Border.all(
              color: Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withOpacity(.25),
            ),
            borderRadius: BorderRadius.circular(borderRadius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _GreetingCardModern extends StatelessWidget {
  final String name;
  final String email;
  final String role;
  final VoidCallback? onTap;
  const _GreetingCardModern({
    required this.name,
    required this.email,
    required this.role,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final roleLabel = switch (role) {
      'owner' => 'Owner',
      'treasurer' => 'Thủ quỹ',
      _ => 'Thành viên',
    };

    return _GlassCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor:
              Theme.of(context).colorScheme.primaryContainer,
              child: Text(
                (name.isNotEmpty ? name[0] : '?').toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Xin chào, $name',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    email,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                roleLabel,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyClassCardModern extends StatelessWidget {
  final VoidCallback onJoin;
  const _EmptyClassCardModern({required this.onJoin});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Bạn chưa tham gia lớp nào',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            'Nhấn “Tham gia bằng mã” để vào lớp.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onJoin,
            icon: const Icon(Icons.group_add),
            label: const Text('Tham gia bằng mã'),
          ),
        ],
      ),
    );
  }
}

class _CurrentClassCardModern extends StatelessWidget {
  final int classId;
  final String className;
  final num? balance;
  final bool showFundShortcuts;
  final List<String> fundMiniIcons;
  final VoidCallback onPickClass;
  final VoidCallback onOpenMembers;

  const _CurrentClassCardModern({
    required this.classId,
    required this.className,
    required this.balance,
    required this.showFundShortcuts,
    required this.fundMiniIcons,
    required this.onPickClass,
    required this.onOpenMembers,
  });

  String _formatVn(num v) {
    final s = v.toStringAsFixed(0);
    return s.replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
  }

  @override
  Widget build(BuildContext context) {
    final balanceText = balance == null ? '—' : '${_formatVn(balance!)} đ';

    Future<void> _openFundSheet() async {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => FundAccountSheet(classId: classId),
      );
    }

    return _GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _AssetIconBox.square(
                  asset: _kIcon.clazz, fallback: Icons.class_, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(className,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('Mã lớp: $classId',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                          color:
                          Theme.of(context).colorScheme.outline,
                        )),
                  ],
                ),
              ),
              FilledButton.tonal(
                onPressed: onPickClass,
                child: const Text('Đổi lớp'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withOpacity(.9),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.savings_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Số dư hiện tại: $balanceText',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                IconButton(
                  tooltip: 'Thành viên lớp',
                  onPressed: onOpenMembers,
                  icon: const Icon(Icons.group_outlined),
                ),
              ],
            ),
          ),
          if (showFundShortcuts) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: fundMiniIcons.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (ctx, i) => _MiniCircleIcon(
                  asset: fundMiniIcons[i],
                  onTap: _openFundSheet,
                  tooltip: 'Cấu hình tài khoản quỹ',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniCircleIcon extends StatelessWidget {
  final String asset;
  final VoidCallback? onTap;
  final String? tooltip;
  const _MiniCircleIcon({required this.asset, this.onTap, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).colorScheme.primaryContainer;
    final avatar = CircleAvatar(
      radius: 20,
      backgroundColor: bg,
      child: _SafeAssetIcon(
          asset: asset, size: 22, fallback: Icons.account_balance),
    );
    final ink = Material(
      type: MaterialType.transparency,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 44, height: 44, child: Center(child: avatar)),
      ),
    );
    return tooltip == null ? ink : Tooltip(message: tooltip!, child: ink);
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});
  @override
  Widget build(BuildContext context) {
    return Text(title,
        style: Theme.of(context)
            .textTheme
            .titleLarge
            ?.copyWith(fontWeight: FontWeight.w800));
  }
}

/// ===== LƯỚI Ô VUÔNG (icon to + text phía dưới)
class _ActionsSquareGrid extends StatelessWidget {
  final List<Widget> children;
  const _ActionsSquareGrid({required this.children});
  @override
  Widget build(BuildContext context) {
    return GridView(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: 162, // chiều cao lớn, không mất chữ
      ),
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      children: children,
    );
  }
}

class _ActionSquareCard extends StatelessWidget {
  final String? assetIcon;
  final IconData fallbackIcon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _ActionSquareCard({
    required this.assetIcon,
    required this.fallbackIcon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.all(14),
      borderRadius: 18,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              height: 70,
              width: 70,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(18),
              ),
              child: _SafeAssetIcon(
                  asset: assetIcon, size: 40, fallback: fallbackIcon),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// ================== ICON HELPERS ==================

class _AssetIconBox extends StatelessWidget {
  final String? asset;
  final IconData fallback;
  final double size;
  final double radius;

  const _AssetIconBox._({
    required this.asset,
    required this.fallback,
    required this.size,
    required this.radius,
  });

  factory _AssetIconBox.rounded({
    required String? asset,
    required IconData fallback,
    double size = 44,
  }) =>
      _AssetIconBox._(asset: asset, fallback: fallback, size: size, radius: 14);

  factory _AssetIconBox.square({
    required String? asset,
    required IconData fallback,
    double size = 44,
  }) =>
      _AssetIconBox._(asset: asset, fallback: fallback, size: size, radius: 12);

  @override
  Widget build(BuildContext context) {
    final containerColor = Theme.of(context).colorScheme.primaryContainer;
    return Container(
      height: size,
      width: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: _SafeAssetIcon(
        asset: asset,
        size: size * .56,
        fallback: fallback,
      ),
    );
  }
}

class _SafeAssetIcon extends StatelessWidget {
  final String? asset;
  final IconData fallback;
  final double size;
  const _SafeAssetIcon({
    required this.asset,
    required this.fallback,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    if (asset == null) return Icon(fallback, size: size);
    return Image.asset(
      asset!,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Icon(fallback, size: size),
    );
  }
}
