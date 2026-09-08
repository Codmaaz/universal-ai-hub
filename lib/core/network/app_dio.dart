import 'package:dio/dio.dart';

import '../utils/secret_masker.dart';

/// Central factory for Dio clients. All clients share:
///   * no global proxies,
///   * sane defaults,
///   * a sanitizing log interceptor.
abstract final class AppDio {
  static Dio create({
    Duration connectTimeout = const Duration(seconds: 30),
    Duration receiveTimeout = const Duration(seconds: 120),
    bool verboseLogging = false,
  }) {
    final dio = Dio(
      BaseOptions(
        connectTimeout: connectTimeout,
        receiveTimeout: receiveTimeout,
        sendTimeout: connectTimeout,
        headers: const {
          'Accept': 'application/json, text/event-stream, text/plain',
        },
        validateStatus: (status) => status != null && status >= 200 && status < 300,
      ),
    );
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (verboseLogging) {
            final scrubbedUri = SecretMasker.scrubSecrets(options.uri.toString());
            // ignore: avoid_print
            print('[uaih:req] ${options.method} $scrubbedUri');
          }
          handler.next(options);
        },
        onResponse: (response, handler) {
          if (verboseLogging) {
            // ignore: avoid_print
            print('[uaih:res] ${response.statusCode} '
                '${response.requestOptions.method} '
                '${SecretMasker.scrubSecrets(response.requestOptions.uri.toString())}');
          }
          handler.next(response);
        },
        onError: (e, handler) {
          if (verboseLogging) {
            final kind = '${e.type}';
            // ignore: avoid_print
            print('[uaih:err] type=$kind status=${e.response?.statusCode} '
                'url=${SecretMasker.scrubSecrets(e.requestOptions.uri.toString())}');
          }
          handler.next(e);
        },
      ),
    );
    return dio;
  }
}
