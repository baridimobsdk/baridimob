import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'errors.dart';
import 'types.dart';

/// Official BaridiMob server.
const String defaultBaseUrl = 'https://baridimob.poste.dz/mobilebank/service';

/// Protocol revision sent in the `spec-revision` header.
const String defaultSpecRevision = '29200428';

/// User agent of the official Android app.
const String defaultUserAgent =
    'Dalvik/2.1.0 (Linux; U; Android 9; V2229A Build/PQ3B.190801.12191611)';

class SendResult {
  SendResult(this.status, this.data, [this.bytes]);

  final int status;
  final Object? data;
  final Uint8List? bytes;
}

class _RetryableHttpError implements Exception {
  _RetryableHttpError(this.status);

  final int status;

  @override
  String toString() => 'Server responded $status';
}

/// Sends requests and keeps the session cookies.
class HttpTransport {
  HttpTransport({
    required this.baseUrl,
    required this.specRevision,
    required this.locale,
    required this.timeout,
    required this.retries,
    required this.userAgent,
    required this.client,
  });

  final String baseUrl;
  final String specRevision;
  final BaridiMobLocale locale;
  final Duration timeout;
  final int retries;
  final String userAgent;
  final http.Client client;
  final Map<String, String> _cookies = {};

  String cookieHeader() =>
      _cookies.entries.map((entry) => '${entry.key}=${entry.value}').join('; ');

  Map<String, String> cookieSnapshot() => Map.of(_cookies);

  void restoreCookies(Map<String, String> cookies) {
    _cookies.clear();
    cookies.forEach((name, value) {
      if (name.isNotEmpty) _cookies[name] = value;
    });
  }

  void clearCookies() => _cookies.clear();

  /// Sends a request. Safe requests are retried on network errors, timeouts,
  /// HTTP 5xx and 429; unsafe ones (OTP, payments, transfers) never are.
  Future<SendResult> send({
    required String method,
    required String endpoint,
    String? query,
    String? body,
    String? contentType,
    bool safe = true,
    bool binary = false,
  }) async {
    final attempts = safe ? max(0, retries) + 1 : 1;
    for (var attempt = 0;; attempt++) {
      try {
        return await _attempt(
            method, endpoint, query, body, contentType, binary);
      } catch (error, stack) {
        final retryable = error is _RetryableHttpError ||
            error is NetworkError ||
            error is TimeoutError;
        if (retryable && attempt < attempts - 1) continue;
        Error.throwWithStackTrace(_toPublicError(error), stack);
      }
    }
  }

  Object _toPublicError(Object error) {
    if (error is _RetryableHttpError) {
      return ServerError(
          error.status, {'httpStatus': error.status}, error.toString());
    }
    return error;
  }

  Future<SendResult> _attempt(
    String method,
    String endpoint,
    String? query,
    String? body,
    String? contentType,
    bool binary,
  ) async {
    final hasQuery = query != null && query.isNotEmpty;
    final request = http.Request(
        method, Uri.parse('$baseUrl/$endpoint${hasQuery ? '?$query' : ''}'))
      ..followRedirects = false
      ..headers.addAll({
        'accept': 'application/json, application/*+json',
        'platform': 'android',
        'spec-revision': specRevision,
        'accept-language': locale.acceptLanguage,
        'user-agent': userAgent,
      });
    if (body != null) {
      request
        ..headers['content-type'] =
            contentType ?? 'application/x-www-form-urlencoded'
        ..bodyBytes = utf8.encode(body);
    }
    final cookie = cookieHeader();
    if (cookie.isNotEmpty) request.headers['cookie'] = cookie;

    Future<http.Response> exchange() async =>
        http.Response.fromStream(await client.send(request));

    final http.Response response;
    try {
      response = await exchange().timeout(timeout);
    } on TimeoutException {
      throw TimeoutError('Request timed out after ${timeout.inMilliseconds}ms');
    } on BaridiMobError {
      rethrow;
    } catch (error) {
      if (error is Error) rethrow;
      throw NetworkError('Network request failed', cause: error);
    }

    _absorbCookies(response.headers['set-cookie']);

    if (response.statusCode >= 500 || response.statusCode == 429) {
      throw _RetryableHttpError(response.statusCode);
    }

    final bytes = response.bodyBytes;
    if (bytes.isEmpty) {
      return SendResult(response.statusCode, <String, Object?>{});
    }
    final type = response.headers['content-type'] ?? '';
    if (binary && !type.contains('json')) {
      return SendResult(response.statusCode, null, bytes);
    }

    final text = utf8.decode(bytes, allowMalformed: true);
    if (text.trim().isEmpty) {
      return SendResult(response.statusCode, <String, Object?>{});
    }
    try {
      return SendResult(response.statusCode, jsonDecode(text));
    } on FormatException {
      throw ServerError(
        -1,
        {'body': text.length > 500 ? text.substring(0, 500) : text},
        'Response is not valid JSON',
      );
    }
  }

  void _absorbCookies(String? header) {
    if (header == null || header.isEmpty) return;
    // Several Set-Cookie headers arrive joined with commas; split on the
    // commas that start a new `name=` pair (not those inside Expires dates).
    for (final entry in header.split(RegExp(r',(?=\s*[^;,=\s]+=)'))) {
      final pair = entry.split(';').first;
      final index = pair.indexOf('=');
      if (index <= 0) continue;
      final name = pair.substring(0, index).trim();
      if (name.isNotEmpty) _cookies[name] = pair.substring(index + 1).trim();
    }
  }
}
