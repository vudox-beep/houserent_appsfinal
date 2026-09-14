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

    final apiMessage = _apiMessage(error);
    if (apiMessage != null) {
      return sanitizePublicText(apiMessage, fallback: fallback);
    }

    final msg = error.toString().toLowerCase();
    if (msg.contains('login_required') ||
        msg.contains('please log in') ||
        msg.contains('not authenticated') ||
        (msg.contains('invalid or missing token') &&
            !msg.contains('booking token'))) {
      return 'Your session expired. Please log in again.';
    }
    if (msg.contains('unauthorized') || msg.contains('forbidden')) {
      return 'Your session expired. Please log in again.';
    }

    return fallback;
  }

  static String? _apiMessage(Object error) {
    final raw = error.toString();
    final message = raw.startsWith('Exception: ')
        ? raw.substring('Exception: '.length).trim()
        : raw.trim();
    if (message.isEmpty) return null;

    final lower = message.toLowerCase();
    if (lower.contains('sqlstate') ||
        lower.contains('sqlite') ||
        lower.contains('no such table') ||
        lower.contains('database is not configured')) {
      return 'The moving service is not fully set up on the server yet. '
          'Please try again later or contact support.';
    }

    if (lower.contains('could not reach the moving api') ||
        lower.contains('moving api blocked') ||
        lower.contains('add pickup') ||
        lower.contains('choose today') ||
        lower.contains('fare must be at least') ||
        lower.contains('contact phone') ||
        lower.contains('account type') ||
        lower.contains('not available for your account')) {
      return message;
    }

    if (message.length <= 180 &&
        !lower.contains('exception') &&
        !lower.contains('stacktrace')) {
      return sanitizePublicText(message);
    }

    return null;
  }

  /// Strip API URLs and server paths so they never appear in the Flutter UI.
  static String sanitizePublicText(
    String raw, {
    String fallback = 'Something went wrong. Please try again.',
  }) {
    var text = raw.replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
    if (text.isEmpty) return fallback;

    final lowerRaw = text.toLowerCase();
    if (lowerRaw.contains('http://') ||
        lowerRaw.contains('https://') ||
        lowerRaw.contains('houseforrent.site') ||
        lowerRaw.contains('php_backend') ||
        lowerRaw.contains('uri=')) {
      return fallback;
    }

    text = text.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    return text.isEmpty ? fallback : text;
  }
}
