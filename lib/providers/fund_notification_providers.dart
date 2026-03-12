import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/dio_provider.dart';
import '../repos/fund_notification_repository.dart';

/// Repo notifications – dùng chung trong app
final fundNotificationRepositoryProvider =
Provider<FundNotificationRepository>((ref) {
  final dio = ref.read(dioProvider);
  return FundNotificationRepository(dio: dio);
});

/// Danh sách thông báo (simple, chưa load-more)
final notificationsProvider =
FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  final repo = ref.watch(fundNotificationRepositoryProvider);
  return repo.getNotifications(page: 1);
});
