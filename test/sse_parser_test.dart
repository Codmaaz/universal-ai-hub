import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ai_hub/core/network/sse_parser.dart';

void main() {
  SseDecoder newDecoder() => SseDecoder();

  Future<List<String>> decodeFrom(List<String> chunks) {
    final decoder = newDecoder();
    final bytes = chunks.map(utf8.encode);
    return decoder.decode(Stream.fromIterable(bytes)).toList();
  }

  group('SseDecoder', () {
    test('parses single data event', () async {
      final events = await decodeFrom([
        'data: {"delta":"a"}\n\n',
      ]);
      expect(events, ['{"delta":"a"}']);
    });

    test('parses multiple events', () async {
      final events = await decodeFrom([
        'data: {"a":1}\n\n',
        'data: {"a":2}\n\n',
        'data: [DONE]\n\n',
      ]);
      expect(events, ['{"a":1}', '{"a":2}']);
    });

    test('handles chunks split mid-line', () async {
      final events = await decodeFrom([
        'data: {"partial":',
        '"value"}\n\ndata: sec',
        'ond\n\n',
      ]);
      expect(events, ['{"partial":"value"}', 'second']);
    });

    test('ignores comments and unknown fields', () async {
      final events = await decodeFrom([
        ': keep-alive\n',
        'event: message\n',
        'data: ok\n\n',
      ]);
      expect(events, ['ok']);
    });

    test('multiline data joined with newline', () async {
      final events = await decodeFrom(['data: one\ndata: two\n\n']);
      expect(events, ['one\ntwo']);
    });

    test('flushes trailing event without blank line', () async {
      final events = await decodeFrom(['data: final-token']);
      expect(events, ['final-token']);
    });
  });
}
