/// Resolves a small JSON pointer language used by the Custom API adapter,
/// e.g. `choices[0].message.content`, `data.text`, or `a.b[2].c`.
library;

dynamic resolveJsonPath(String? path, dynamic root) {
  if (path == null || path.trim().isEmpty || root == null) return null;
  final trimmed = path.trim();

  // Simple dotted path without indices — fast path.
  if (!trimmed.contains('[') && !trimmed.contains('.')) {
    if (root is Map && root.containsKey(trimmed)) return root[trimmed];
    return null;
  }

  dynamic node = root;
  final tokens = _tokenize(trimmed);
  for (final tok in tokens) {
    if (node == null) return null;
    if (tok is String) {
      if (node is Map && node.containsKey(tok)) {
        node = node[tok];
      } else {
        return null;
      }
    } else if (tok is int) {
      if (node is List && tok >= 0 && tok < node.length) {
        node = node[tok];
      } else {
        return null;
      }
    }
  }
  return node;
}

/// Splits `a.b[0].c` into ['a','b',0,'c'].
List<Object> _tokenize(String path) {
  final tokens = <Object>[];
  final buffer = StringBuffer();
  for (var i = 0; i < path.length; i++) {
    final ch = path[i];
    if (ch == '.') {
      final s = buffer.toString().trim();
      if (s.isNotEmpty) tokens.add(s);
      buffer.clear();
    } else if (ch == '[') {
      final s = buffer.toString().trim();
      if (s.isNotEmpty) tokens.add(s);
      buffer.clear();
      // read digits until ]
      final digits = StringBuffer();
      var j = i + 1;
      while (j < path.length && path[j] != ']') {
        digits.write(path[j]);
        j++;
      }
      final n = int.tryParse(digits.toString().trim());
      tokens.add(n ?? digits.toString());
      i = j;
    } else {
      buffer.write(ch);
    }
  }
  final last = buffer.toString().trim();
  if (last.isNotEmpty) tokens.add(last);
  return tokens;
}
