import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:http/http.dart' as http;

/// Turns a caught error into text a person can act on.
///
/// `BackendService` throws `Exception('Failed to …: {"error": "…"}')`; shown
/// raw, that put a JSON dump and the word "Exception" on screen. This pulls
/// out the backend's own message, and names the two failures that have
/// nothing to do with the request itself (no connection, server too slow).
String errorText(Object error) {
  if (error is TimeoutException) return 'common.timeout_error'.tr();
  if (error is SocketException || error is http.ClientException) {
    return 'common.network_error'.tr();
  }

  var text = error.toString();
  if (text.startsWith('Exception: ')) text = text.substring(11);

  final brace = text.indexOf('{');
  if (brace >= 0) {
    try {
      final body = jsonDecode(text.substring(brace));
      if (body is Map && body['error'] is String) {
        return body['error'] as String;
      }
    } catch (_) {
      // Not JSON after all — fall through to the plain text.
    }
  }
  return text;
}
