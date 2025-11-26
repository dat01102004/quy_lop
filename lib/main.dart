// lib/main.dart
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

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

// Theme & App settings
import 'theme/app_theme.dart';            // lightTheme(), darkTheme(), AppGradients
import 'services/app_settings.dart';      // appSettingsProvider

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
    // Đọc cài đặt giao diện (màu/locale/scale/mode)
    final settings = ref.watch(appSettingsProvider);

    // Dùng ref trong các route builder (closures)
    final r = ref;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Lop Fund',

      // THEME theo seed color & mode người dùng chọn trong Profile/Settings
      theme: lightTheme(Color(settings.seed)),
      darkTheme: darkTheme(Color(settings.seed)),
      themeMode: settings.mode,

      // NGÔN NGỮ
      locale: Locale(settings.locale),
      supportedLocales: const [Locale('vi'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],

      // CỠ CHỮ (Text Scale)
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(settings.textScale)),
          child: child!,
        );
      },

      // ROUTES
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
          return LedgerPage(classId: id);
        },
        '/fee-cycles/generate': (_) => const GenerateInvoicesPage(),
        '/classes': (_) => const ClassListPage(),
        '/class-management': (_) => const ClassManagementPage(),
        '/payments/approved': (ctx) {
          final s = r.read(sessionProvider);
          final id = s.classId ?? 0;
          if (id <= 0) {
            return const Scaffold(
              body: Center(child: Text('Chưa chọn lớp — không thể mở danh sách đã duyệt')),
            );
          }
          return ApprovedPaymentsPage(classId: id);
        },
        // /expenses nhận optional arguments: { classId?: int, feeCycleId?: int }
        '/expenses': (ctx) {
          final args = ModalRoute.of(ctx)?.settings.arguments as Map<String, dynamic>?;
          final sess = r.read(sessionProvider);
          final int classId = (args?['classId'] as int?) ?? (sess.classId ?? 0);
          final int? feeCycleId = args?['feeCycleId'] as int?;

          if (classId <= 0) {
            return const Scaffold(
              body: Center(child: Text('Chưa chọn lớp — không thể mở Khoản chi')),
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

    final needHydrate = s.classId == null || (s.role == null || s.role!.isEmpty);
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
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(controller.text.trim()), child: const Text('Tạo')),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;

    try {
      await ref.read(classRepositoryProvider).createClass(name);
      if (!mounted) return;
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

    if (s.token == null || s.token!.isEmpty) {
      return const LoginPage();
    }

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
                  onPressed: () => Navigator.pushReplacementNamed(context, '/join'),
                  child: const Text('Tham gia lớp'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.pushReplacementNamed(context, '/classes'),
                  child: const Text('Danh sách lớp'),
                ),
                const SizedBox(height: 8),
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

    return const HomePage();
  }
}