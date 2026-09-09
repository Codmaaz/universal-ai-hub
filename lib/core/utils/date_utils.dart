/// Small formatting helpers for timestamps.
String formatRelativeTime(DateTime? time, {DateTime? now}) {
  if (time == null) return '';
  final n = now ?? DateTime.now();
  final diff = n.difference(time);
  if (diff.inSeconds < 60) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  final local = time.toLocal();
  return '${local.day}/${local.month}';
}

String formatFullTime(DateTime? time) {
  if (time == null) return '';
  final t = time.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.day}/${t.month}/${t.year} ${two(t.hour)}:${two(t.minute)}';
}
