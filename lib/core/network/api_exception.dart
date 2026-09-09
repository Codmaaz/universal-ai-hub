import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../utils/secret_masker.dart';

/// Broad error categories mapped to user friendly guidance.
enum ApiErrorKind {
  configuration('Configuration problem'),
  invalidApiKey('Authentication failed'),
  rateLimited('Rate limited'),
  quotaExceeded('Quota exceeded'),
  invalidModel('Invalid model'),
  unsupportedEndpoint('Unsupported endpoint'),
  invalidRequest('Invalid request'),
  serverError('Server error'),
  streamingError('Streaming error'),
  network('Network error'),
  timeout('Request timed out'),
  ssl('Secure connection failed'),
  noInternet('No internet connection'),
  emptyResponse('Empty response'),
  parseError('Unexpected response'),
  cancelled('Cancelled');

  const ApiErrorKind(this.heading);
  final String heading;
}

/// Typed application exception carrying both a friendly message and an
/// optional expandable technical section. Never contains raw secrets.
class ApiException implements Exception {
  const ApiException({
    required this.kind,
    required this.message,
    this.tip,
    this.httpStatus,
    this.providerName,
    this.sanitizedBody,
    this.sanitizedUrl,
    this.durationMs,
    this.raw,
  });

  final ApiErrorKind kind;
  final String message;

  /// Short "what to do next" line.
  final String? tip;
  final int? httpStatus;
  final String? providerName;

  /// Sanitized excerpt of the response body shown under Technical Details.
  final String? sanitizedBody;
  final String? sanitizedUrl;
  final int? durationMs;

  /// Original error kept out of any logs/UI (used only for debugging in code).
  final Object? raw;

  bool get isCancellation => kind == ApiErrorKind.cancelled;

  String get kindLabel => kind.heading;

  /// Safe error classifier. Masks anything secret found in bodies/urls.
  factory ApiException.fromDio(DioException e, {String? providerName}) {
    final status = e.response?.statusCode;
    final data = e.response?.data;
    String? rawBody;
    if (data is String) {
      rawBody = data;
    } else if (data is ResponseBody) {
      rawBody = 'Binary/stream response body (not displayed as text).';
    } else if (data != null) {
      try {
        rawBody = jsonEncode(data);
      } catch (_) {
        rawBody = data.toString();
      }
    }
    final body = rawBody != null && rawBody.isNotEmpty
        ? _truncate(SecretMasker.scrubJsonBody(rawBody))
        : null;
    final url = SecretMasker.scrubSecrets(e.requestOptions.uri.toString());

    final kind = classifyDio(e, status);
    return ApiException(
      kind: kind,
      message: _friendlyMessage(kind, status),
      tip: _tipFor(kind, status),
      httpStatus: status,
      providerName: providerName,
      sanitizedBody: body,
      sanitizedUrl: url,
      raw: e,
    );
  }

  factory ApiException.fromSocket(Object e, {String? providerName}) {
    if (e is SocketException) {
      final kind = (e.message.contains('Failed host lookup') ||
              e.message.contains('lookup'))
          ? ApiErrorKind.noInternet
          : ApiErrorKind.network;
      return ApiException(
        kind: kind,
        message: kind == ApiErrorKind.noInternet
            ? 'Could not reach the provider. Check your connection.'
            : 'Network error while talking to the provider.',
        tip: kind == ApiErrorKind.noInternet
            ? 'Make sure you are online and the base URL is correct.'
            : 'Try again — the network may be temporarily unavailable.',
        providerName: providerName,
        raw: e,
      );
    }
    if (e is HandshakeException) {
      return ApiException(
        kind: ApiErrorKind.ssl,
        message: 'The secure connection to the provider could not be '
            'verified (SSL error).',
        tip: 'Check that the base URL uses a valid certificate.',
        providerName: providerName,
        raw: e,
      );
    }
    return ApiException(
      kind: ApiErrorKind.network,
      message: 'Unexpected network failure.',
      providerName: providerName,
      raw: e,
    );
  }

  factory ApiException.message(ApiErrorKind kind, String message,
          {String? tip, String? providerName, int? httpStatus, String? sanitizedBody}) =>
      ApiException(
        kind: kind,
        message: message,
        tip: tip,
        providerName: providerName,
        httpStatus: httpStatus,
        sanitizedBody: sanitizedBody,
      );

  static ApiErrorKind classifyDio(DioException e, int? status) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return ApiErrorKind.timeout;
      case DioExceptionType.connectionError:
        return e.message != null &&
                e.message!.toLowerCase().contains('certificate')
            ? ApiErrorKind.ssl
            : ApiErrorKind.network;
      case DioExceptionType.badCertificate:
        return ApiErrorKind.ssl;
      case DioExceptionType.cancel:
        return ApiErrorKind.cancelled;
      case DioExceptionType.badResponse:
        if (status == null) return ApiErrorKind.serverError;
        // 401 = wrong key; 403 = key rejected/expired or quota denied.
        if (status == 401 || status == 403) return ApiErrorKind.invalidApiKey;
        if (status == 404) return ApiErrorKind.unsupportedEndpoint;
        if (status == 429) return ApiErrorKind.rateLimited;
        if (status == 400) return ApiErrorKind.invalidRequest;
        if (status == 422) return ApiErrorKind.invalidRequest;
        if (status == 500 || status == 502 || status == 503 || status == 504) {
          return ApiErrorKind.serverError;
        }
        return ApiErrorKind.serverError;
      case DioExceptionType.unknown:
        return ApiErrorKind.network;
    }
  }

  static String _friendlyMessage(ApiErrorKind kind, int? status) {
    switch (kind) {
      case ApiErrorKind.invalidApiKey:
        return 'Authentication failed. The API key was rejected by the '
            'provider.';
      case ApiErrorKind.rateLimited:
        return 'The provider is rate limiting requests.';
      case ApiErrorKind.quotaExceeded:
        return 'The provider reported that your quota is exhausted.';
      case ApiErrorKind.invalidModel:
        return 'The model name was rejected by the provider.';
      case ApiErrorKind.unsupportedEndpoint:
        return 'The endpoint returned “not found”. The URL may be wrong.';
      case ApiErrorKind.invalidRequest:
        return 'The provider rejected the request format (HTTP $status).';
      case ApiErrorKind.serverError:
        return 'The provider reported a server error (HTTP $status).';
      case ApiErrorKind.timeout:
        return 'The provider did not respond in time.';
      case ApiErrorKind.ssl:
        return 'Secure connection could not be established (SSL error).';
      case ApiErrorKind.noInternet:
        return 'No internet connection detected.';
      case ApiErrorKind.network:
        return 'Network error while contacting the provider.';
      case ApiErrorKind.streamingError:
        return 'The streaming connection dropped mid-response.';
      case ApiErrorKind.emptyResponse:
        return 'The provider returned an empty response.';
      case ApiErrorKind.parseError:
        return 'The provider returned something unexpected.';
      case ApiErrorKind.configuration:
        return 'This provider is not fully configured.';
      case ApiErrorKind.cancelled:
        return 'Generation stopped.';
    }
  }

  static String? _tipFor(ApiErrorKind kind, int? status) {
    switch (kind) {
      case ApiErrorKind.invalidApiKey:
        return 'Check your API key and authentication settings, then try '
            'again.';
      case ApiErrorKind.invalidModel:
        return 'Verify the model name or fetch the model list for this '
            'provider.';
      case ApiErrorKind.unsupportedEndpoint:
        return 'Check the Base URL and endpoint path in Provider settings.';
      case ApiErrorKind.rateLimited:
        return 'Wait a moment or lower the request frequency.';
      case ApiErrorKind.quotaExceeded:
        return 'Top up your provider account or switch models.';
      case ApiErrorKind.noInternet:
        return 'Reconnect and retry.';
      default:
        return null;
    }
  }
}

/// Truncates long payloads for display.
String _truncate(String value, {int max = 4000}) =>
    value.length <= max ? value : '${value.substring(0, max)}\n… (truncated)';
