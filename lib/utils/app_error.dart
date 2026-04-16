import 'dart:async';
import 'dart:io';

class AppError {
  static bool isNetworkError(Object error) {
    if (error is SocketException || error is TimeoutException) return true;
    final msg = error.toString().toLowerCase();
    return msg.contains('socketexception') ||
        msg.contains('failed host lookup') ||
        msg.contains('network is unreachable') ||
        msg.contains('connection refused') ||
        msg.contains('connection reset') ||
        msg.contains('timed out') ||
        msg.contains('timeout') ||
        msg.contains('network');
  }

  static String userMessage(
    Object error, {
    String fallback = 'Something went wrong. Please try again.',
  }) {
    if (isNetworkError(error)) {
      return 'No internet connection. Please check your network and try again.';
    }
    final msg = error.toString().toLowerCase();
    if (msg.contains('unauthorized') || msg.contains('forbidden') || msg.contains('token')) {
      return 'Your session expired. Please log in again.';
    }
    return fallback;
  }
}
