// lib/services/network.dart
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

final connectivityStreamProvider =
StreamProvider<List<ConnectivityResult>>((ref) {
  return Connectivity().onConnectivityChanged;
});

/// Provider: true nếu KHÔNG có kết nối (tất cả phần tử đều none)
final isOfflineProvider = Provider<bool>((ref) {
  final async = ref.watch(connectivityStreamProvider);
  return async.maybeWhen(
    data: (list) =>
    list.isEmpty || list.every((r) => r == ConnectivityResult.none),
    orElse: () => false,
  );
});


/// Nhận diện DioException là lỗi offline
bool isOfflineDioError(DioException e) {
  if (e.type == DioExceptionType.connectionError) return true;
  if (e.error is SocketException) return true;

  final msg = (e.message ?? '').toLowerCase();
  return msg.contains('failed host lookup') ||
      msg.contains('no address associated with hostname') ||
      msg.contains('network is unreachable');
}

String formatDateOnly(String? iso) {
  if (iso == null || iso.trim().isEmpty) return '-';
  try {
    final dt = DateTime.parse(iso).toLocal();
    return DateFormat('yyyy-MM-dd').format(dt);
  } catch (_) {
    return iso.split('T').first;
  }
}

String formatDateTime(String? iso) {
  if (iso == null || iso.trim().isEmpty) return '-';
  try {
    final dt = DateTime.parse(iso).toLocal();
    return DateFormat('yyyy-MM-dd HH:mm').format(dt);
  } catch (_) {
    return iso.replaceFirst('T', ' ').split('.').first;
  }
}

/// Chuyển DioException -> message thân thiện
String prettyDioError(DioException e) {
  if (isOfflineDioError(e)) {
    return 'Không có kết nối Internet. Vui lòng kiểm tra mạng và thử lại.';
  }

  switch (e.type) {
    case DioExceptionType.connectionTimeout:
      return 'Kết nối quá thời gian. Hãy thử lại.';
    case DioExceptionType.receiveTimeout:
      return 'Quá thời gian nhận dữ liệu. Hãy thử lại.';
    case DioExceptionType.sendTimeout:
      return 'Gửi dữ liệu quá thời gian. Hãy thử lại.';
    case DioExceptionType.badResponse:
      final code = e.response?.statusCode ?? 0;
      final msg =
      (e.response?.data is Map && e.response?.data['message'] != null)
          ? e.response!.data['message'].toString()
          : 'Máy chủ trả về lỗi ($code).';
      return msg;
    default:
      return e.message ?? 'Đã xảy ra lỗi không xác định.';
  }
}