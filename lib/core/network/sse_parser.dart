import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

/// Server-Sent-Events decoder tolerant to chunk fragmentation, provider
/// heartbeat comments, and `data:` payloads split across events. Emits each
/// event's *data payload* (UTF-8 string) downstream; returns a [SseDecoder]
/// that the adapter uses to know when the stream finished.
class SseDecoder {
  SseDecoder();

  final StringBuffer _buffer = StringBuffer();

  /// Convert a [utf8.decoder] byte stream into decoded event data strings.
  Stream<String> decode(Stream<List<int>> bytes) {
    final lines = <String>[];
    final controller = StreamController<String>(sync: true);
    StreamSubscription<String>? sub;

    void flushEvent() {
      final payload = lines.join('\n');
      lines.clear();
      // Guard against "data: [DONE]" sentinels.
      if (payload.isNotEmpty && payload != '[DONE]') {
        controller.add(payload);
      }
    }

    // Process one decoded character chunk; buffer partial lines.
    void feed(String chunk) {
      for (final ch in chunk.split('')) {
        if (ch == '\n') {
          final line = _buffer.toString();
          _buffer.clear();
          if (line.isEmpty) {
            flushEvent(); // blank line = event boundary
          } else if (line.startsWith('data:')) {
            final data = line.substring(5).trimLeft();
            if (data == '[DONE]') {
              flushEvent();
            } else {
              lines.add(data);
            }
          } else if (line.startsWith(':')) {
            // comment / heartbeat — ignore
          } else {
            // Field like "event: ...", "id: ...", "retry: ..." — ignore body.
          }
        } else {
          _buffer.write(ch);
        }
      }
    }

    sub = bytes
        .transform(utf8.decoder)
        .listen(feed, onError: (Object e, StackTrace st) {
      controller.addError(e, st);
    }, onDone: () {
      // Flush any trailing event that was not terminated by a blank line.
      if (_buffer.isNotEmpty) {
        final rest = _buffer.toString();
        if (rest.startsWith('data:')) {
          lines.add(rest.substring(5).trimLeft());
        }
        _buffer.clear();
      }
      if (lines.isNotEmpty) {
        flushEvent();
      }
      controller.close();
    }, cancelOnError: true);

    _subscription = sub;
    return controller.stream;
  }

  StreamSubscription<String>? _subscription;

  /// Cancels the underlying byte subscription (used on manual stop).
  void cancel() => _subscription?.cancel();
}

/// Collects one SSE response into a [Response<ResponseBody>] friendly
/// converter used by adapters to stream text deltas.
Stream<String> sseDataLines(Response<ResponseBody> response) {
  final decoder = SseDecoder();
  final bytes = response.data!.stream;
  return decoder.decode(bytes);
}
