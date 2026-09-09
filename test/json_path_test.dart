import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ai_hub/adapters/json_path.dart';

void main() {
  final sample = {
    'choices': [
      {
        'message': {'content': 'Hello from AI'}
      }
    ],
    'data': {
      'text': 'plain',
    },
    'list': [
      {'a': 1},
      {'a': 2},
    ],
  };

  group('resolveJsonPath', () {
    test('resolves bracket+dot chain', () {
      expect(resolveJsonPath('choices[0].message.content', sample),
          'Hello from AI');
    });

    test('resolves simple key', () {
      expect(resolveJsonPath('data', sample), {'text': 'plain'});
    });

    test('resolves nested dot access', () {
      expect(resolveJsonPath('data.text', sample), 'plain');
    });

    test('resolves numeric indices in list', () {
      expect(resolveJsonPath('list[1].a', sample), 2);
    });

    test('returns null for missing paths without throwing', () {
      expect(resolveJsonPath('nothing.here[0]', sample), isNull);
      expect(resolveJsonPath('choices[9].message.content', sample), isNull);
      expect(resolveJsonPath('', sample), isNull);
      expect(resolveJsonPath('x.y', null), isNull);
    });
  });
}
