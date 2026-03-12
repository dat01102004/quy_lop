import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/fund_notification_providers.dart';
import '../providers/unread_notification_provider.dart';

class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  IconData _iconForType(String type) {
    switch (type) {
      case 'income':
        return Icons.arrow_downward; // thu
      case 'expense':
        return Icons.arrow_upward; // chi
      case 'expense_comment':
        return Icons.chat_bubble_outline;
      default:
        return Icons.notifications;
    }
  }

  String _formatCreatedAt(String raw) {
    if (raw.isEmpty) return '';
    try {
      final dt = DateTime.parse(raw).toLocal();
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      final mo = dt.month.toString().padLeft(2, '0');
      final y = dt.year.toString();
      return '$h:$m  $d/$mo/$y';
    } catch (_) {
      return raw;
    }
  }

  int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncNotifs = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Thông báo'),
        actions: [
          IconButton(
            tooltip: 'Đánh dấu tất cả đã đọc',
            icon: const Icon(Icons.mark_email_read_outlined),
            onPressed: () async {
              try {
                final repo = ref.read(fundNotificationRepositoryProvider);
                await repo.markAllAsRead();

                // reload danh sách
                ref.invalidate(notificationsProvider);
                // cho badge chạy lại API getUnreadCount()
                ref.invalidate(unreadNotificationCountProvider);
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Lỗi đánh dấu đã đọc: $e')),
                );
              }
            },
          ),
        ],
      ),
      body: asyncNotifs.when(
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Text('Chưa có thông báo nào'),
            );
          }

          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final n = list[index];

              final id = _toInt(n['id']);
              final isRead = (n['is_read'] as bool?) ?? false;
              final type = (n['type'] as String?) ?? '';
              final title = (n['title'] as String?) ?? '';
              final message = (n['message'] as String?) ?? '';
              final createdAtRaw = (n['created_at'] as String?) ?? '';
              final createdAtText = _formatCreatedAt(createdAtRaw);

              return ListTile(
                leading: Icon(_iconForType(type)),
                title: Text(
                  title,
                  style: TextStyle(
                    fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  message.isNotEmpty ? message : createdAtText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: isRead
                    ? null
                    : const Icon(
                  Icons.circle,
                  size: 10,
                ),
                onTap: () async {
                  try {
                    final repo = ref.read(fundNotificationRepositoryProvider);
                    // đánh dấu 1 thông báo đã đọc
                    await repo.markAsRead(id);

                    // reload danh sách
                    ref.invalidate(notificationsProvider);
                    // và cho badge chạy lại getUnreadCount()
                    ref.invalidate(unreadNotificationCountProvider);

                    // TODO: sau này muốn điều hướng chi tiết thì xử lý ở đây
                    // dựa vào n['type'] / n['data']
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Lỗi cập nhật thông báo: $e')),
                    );
                  }
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(
          child: Text('Lỗi tải thông báo: $e'),
        ),
      ),
    );
  }
}
