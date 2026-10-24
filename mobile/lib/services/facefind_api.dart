import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/scan_result.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}

class FaceFindApi {
  // Set at build time: --dart-define=FACEFIND_API_URL=https://your-backend
  static const String _baseUrl = String.fromEnvironment('FACEFIND_API_URL');
  static const Duration _timeout = Duration(seconds: 45);

  static bool get isConfigured => _baseUrl.startsWith('https://');

  final http.Client _client = http.Client();

  void close() => _client.close();

  Uri _uri(String path) {
    final String base = _baseUrl.endsWith('/')
        ? _baseUrl.substring(0, _baseUrl.length - 1)
        : _baseUrl;
    return Uri.parse('$base$path');
  }

  Future<ScanState> createScan(File image) async {
    // One key per upload so a retry can never create a second paid scan.
    final String key = 'ff-${DateTime.now().microsecondsSinceEpoch}';
    final http.MultipartRequest request =
        http.MultipartRequest('POST', _uri('/api/scans'))
          ..headers['Idempotency-Key'] = key
          ..files.add(await http.MultipartFile.fromPath('image', image.path));
    try {
      final http.StreamedResponse streamed =
          await _client.send(request).timeout(_timeout);
      final http.Response res = await http.Response.fromStream(streamed);
      return _parse(res);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException('The request timed out. Please try again.');
    } on SocketException {
      throw ApiException('No internet connection. Please check your network.');
    } catch (_) {
      throw ApiException('Could not reach the server. Please try again.');
    }
  }

  Future<ScanState> getScan(String id) async {
    try {
      final http.Response res = await _client
          .get(_uri('/api/scans/${Uri.encodeComponent(id)}'))
          .timeout(_timeout);
      return _parse(res);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException('The request timed out. Please try again.');
    } on SocketException {
      throw ApiException('No internet connection. Please check your network.');
    } catch (_) {
      throw ApiException('Could not reach the server. Please try again.');
    }
  }

  ScanState _parse(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final dynamic body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is Map<String, dynamic>) return ScanState.fromJson(body);
      throw ApiException('Unexpected response from the server.');
    }
    switch (res.statusCode) {
      case 400:
        throw ApiException('The request was invalid. Please try another photo.');
      case 401:
        throw ApiException('The service is not authorized. Please contact support.');
      case 402:
        throw ApiException('Not enough credits to run this scan.');
      case 404:
        throw ApiException('This scan could not be found.');
      case 409:
        throw ApiException('This scan is no longer available.');
      case 413:
        throw ApiException('The photo is too large. Maximum size is 10 MB.');
      case 422:
        throw ApiException('The photo could not be used. Please try a clearer photo of one face.');
      case 429:
        final String? wait = res.headers['retry-after'];
        throw ApiException(wait == null
            ? 'Too many requests. Please wait a moment and try again.'
            : 'Too many requests. Please try again in $wait seconds.');
      default:
        throw ApiException('The service is unavailable right now. Please try again later.');
    }
  }
}
