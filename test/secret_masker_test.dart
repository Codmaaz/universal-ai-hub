import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ai_hub/core/utils/secret_masker.dart';

void main() {
  group('SecretMasker.mask', () {
    test('reveal flag returns the original value', () {
      expect(SecretMasker.mask('sk-secret-1234', reveal: true),
          'sk-secret-1234');
    });

    test('masks everything but a short tail', () {
      final m = SecretMasker.mask('super-secret-value');
      expect(m.contains('super-secret'), isFalse);
      expect(m.endsWith('alue'), isTrue);
      expect(m, isNot(equals('super-secret-value')));
    });

    test('never throws on empty/short values', () {
      expect(SecretMasker.mask(''), '');
      expect(SecretMasker.mask('ab'), '********');
    });
  });

  group('SecretMasker.scrubSecrets', () {
    test('masks Authorization bearer tokens', () {
      final out = SecretMasker.scrubSecrets(
          'Authorization: Bearer sk-abcdef1234567890 and more');
      expect(out.contains('sk-abcdef1234567890'), isFalse);
      expect(out, contains('****'));
    });

    test('masks x-api-key header values', () {
      final out =
          SecretMasker.scrubSecrets('x-api-key: deadbeefdeadbeefdeadbeef');
      expect(out.contains('deadbeefdeadbeefdeadbeef'), isFalse);
    });

    test('masks query parameter keys', () {
      final out =
          SecretMasker.scrubSecrets('https://x.com/v1/predict?key=abcd1234&a=1');
      expect(out.contains('abcd1234'), isFalse);
      expect(out, contains('****'));
      expect(out, contains('a=1'));
    });

    test('masks known secret when supplied verbatim', () {
      final out = SecretMasker.scrubSecrets(
          'key is abc12345XYZ and nothing else', knownSecret: 'abc12345XYZ');
      expect(out.contains('abc12345XYZ'), isFalse);
    });
  });

  group('SecretMasker.scrubJsonBody', () {
    test('redacts api-key-like keys while keeping structure', () {
      const body = '{"model":"m","headers":{"x-api-key":"secret-1234",'
          '"Authorization":"Bearer secret-1234"}}';
      final out = SecretMasker.scrubJsonBody(body);
      expect(out.contains('secret-1234'), isFalse);
      expect(out, contains('model'));
    });
  });
}
