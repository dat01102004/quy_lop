import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'services/session.dart';
import 'repos/auth_repository.dart';
import 'repos/class_repository.dart';

// Screens
import 'screens/login_page.dart';
import 'screens/register_page.dart';
import 'screens/home_page.dart';
import 'screens/join_class_page.dart';
import 'screens/invoices_page.dart';
import 'screens/payment_review_page.dart';
import 'screens/fee_report_page.dart';
import 'screens/generate_invoices_page.dart';
import 'screens/class_list_page.dart';
import 'screens/class_management_page.dart';
import 'screens/expenses_page.dart';
import 'screens/approved_payments_page.dart';
import 'screens/ledger_page.dart';

import 'theme/app_theme.dart';

void main() {
  // Bắt mọi lỗi build để tránh “màn hình đen”
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    // ignore: avoid_print
    print('FlutterError: ${details.exceptionAsString()}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    // ignore: avoid_print
    print('Uncaught: $error\n$stack');
    return true;
  };
  ErrorWidget.builder = (FlutterErrorDetails d) => Material(
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          d.exceptionAsString(),
          style: const TextStyle(color: Colors.red),
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );

  runApp(const ProviderScope(child: LopFundApp()));
}

class LopFundApp extends ConsumerWidget {
  const LopFundApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Dùng ref trong các route builder (closures)
    final r = ref;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6C4AD1)),
        extensions: <ThemeExtension<dynamic>>[
          AppGradients.light(),   // nền light
        ],
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6C4AD1), brightness: Brightness.light),
        extensions: <ThemeExtension<dynamic>>[
          AppGradients.dark(),    // nền dark
        ],
      ),
      themeMode: ThemeMode.system, // hoặc ThemeMode.light/dark
      title: 'Lop Fund',
      routes: {
        '/login': (_) => const LoginPage(),
        '/register': (_) => const RegisterPage(),
        '/home': (_) => const HomePage(),
        '/join': (_) => const JoinClassPage(),
        '/invoices': (_) => const InvoicesPage(),
        '/payments/review': (_) => const PaymentReviewPage(),
        '/reports/fee': (_) => const UnpaidMembersPage(),
        '/reports/ledger': (ctx) {
          final s = r.read(sessionProvider);
          final id = s.classId ?? 0;
          if (id <= 0) {
            return const Scaffold(
              body: Center(child: Text('Chưa chọn lớp — không thể mở Sổ quỹ')),
            );
          }
          return LedgerPage(classId: id); // classId bắt buộc
        },
        '/fee-cycles/generate': (_) => const GenerateInvoicesPage(),
        '/classes': (_) => const ClassListPage(),
        '/class-management': (_) => const ClassManagementPage(),
        '/payments/approved': (ctx) {
          final s = r.read(sessionProvider);
          final id = s.classId ?? 0;
          if (id <= 0) {
            return const Scaffold(
              body: Center(
                  child: Text('Chưa chọn lớp — không thể mở danh sách đã duyệt')),
            );
          }
          return ApprovedPaymentsPage(classId: id);
        },

        // /expenses nhận optional arguments: { classId?: int, feeCycleId?: int }
        '/expenses': (ctx) {
          final args =
          ModalRoute.of(ctx)?.settings.arguments as Map<String, dynamic>?;
          final sess = r.read(sessionProvider);
          final int classId = (args?['classId'] as int?) ?? (sess.classId ?? 0);
          final int? feeCycleId = args?['feeCycleId'] as int?;

          if (classId <= 0) {
            return const Scaffold(
              body:
              Center(child: Text('Chưa chọn lớp — không thể mở Khoản chi')),
            );
          }
          return ExpensesPage(classId: classId, feeCycleId: feeCycleId);
        },
      },

      // Quyết định Login/Home sau khi hydrate
      home: const StartupGate(),
    );
  }
}

/// “Cổng khởi động”
/// - Chưa có token -> Login
/// - Có token nhưng thiếu class/role -> gọi hydrate (timeout) rồi hướng dẫn Join / Tạo lớp
/// - Đủ dữ liệu -> Home
class StartupGate extends ConsumerStatefulWidget {
  const StartupGate({super.key});
  @override
  ConsumerState<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends ConsumerState<StartupGate> {
  bool _loading = false;
  bool _hydratedOnce = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeHydrate());
  }

  Future<void> _maybeHydrate() async {
    if (_hydratedOnce) return;
    _hydratedOnce = true;

    final s = ref.read(sessionProvider);

    // Chưa đăng nhập -> không hydrate
    if (s.token == null || s.token!.isEmpty) return;

    final needHydrate =
        s.classId == null || (s.role == null || s.role!.isEmpty);
    if (!needHydrate) return;

    setState(() => _loading = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .hydrateAfterStartup()
          .timeout(const Duration(seconds: 6));
    } catch (e, st) {
      // ignore nhưng có log
      // ignore: avoid_print
      print('hydrateAfterStartup error: $e\n$st');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Mở dialog & tạo lớp
  Future<void> _openCreateClass(BuildContext context) async {
    final controller = TextEditingController();

    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tạo lớp mới'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Tên lớp',
            hintText: 'VD: CNTT K22',
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => Navigator.of(ctx).pop(controller.text.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Hủy')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Tạo'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;

    try {
      await ref.read(classRepositoryProvider).createClass(name);
      if (!mounted) return;
      // Sau khi repo đã set session (classId/role), vào Home
      Navigator.pushReplacementNamed(context, '/home');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tạo lớp thất bại: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider);

    // 1) chưa đăng nhập
    if (s.token == null || s.token!.isEmpty) {
      return const LoginPage();
    }

    // 2) đang hydrate: luôn có UI (không để trống)
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Đang đồng bộ lớp học…'),
              ],
            ),
          ),
        ),
      );
    }

    // 3) có token nhưng chưa có class/role -> mời join / tạo lớp
    if (s.classId == null || (s.role ?? '').isEmpty) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Bạn chưa tham gia lớp nào.'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () =>
                      Navigator.pushReplacementNamed(context, '/join'),
                  child: const Text('Tham gia lớp'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () =>
                      Navigator.pushReplacementNamed(context, '/classes'),
                  child: const Text('Danh sách lớp'),
                ),
                const SizedBox(height: 8),
                // ✅ thêm nút tạo lớp
                TextButton.icon(
                  onPressed: () => _openCreateClass(context),
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Tạo lớp mới'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 4) đủ dữ liệu
    return const HomePage();
  }
}
