import 'turkish.dart';

String _two(int n) => n.toString().padLeft(2, '0');

/// 02:15 veya 01:02:15
String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  return h > 0 ? '${_two(h)}:${_two(m)}:${_two(s)}' : '${_two(m)}:${_two(s)}';
}

/// 19.10.2026 22:29
String formatDateTime(DateTime t) =>
    '${_two(t.day)}.${_two(t.month)}.${t.year} ${_two(t.hour)}:${_two(t.minute)}';

/// 2026-10-19_22-29 (klasör adları için)
String fileStamp(DateTime t) =>
    '${t.year}-${_two(t.month)}-${_two(t.day)}_${_two(t.hour)}-${_two(t.minute)}';

/// Dosya/klasör adında güvenle kullanılabilecek hale getirir.
String sanitizeFileName(String s) {
  final ascii = toAscii(s.trim());
  final cleaned = ascii
      .replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '')
      .replaceAll(RegExp(r'\s+'), '_');
  if (cleaned.isEmpty) return 'toplanti';
  return cleaned.length > 40 ? cleaned.substring(0, 40) : cleaned;
}
