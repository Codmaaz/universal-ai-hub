import 'dart:math';

/// Small identifier generator (no uuid dependency needed).
abstract final class Ids {
  static final Random _rng = Random();

  static String newId([String prefix = 'id']) {
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final rnd = _rng.nextInt(0x7fffffff).toRadixString(36);
    return '${prefix}_$ts$rnd';
  }
}
