/// Tags are nonempty strings, finite numbers, or nonempty lists of those values.
/// Booleans, nulls, objects and empty values are removed rather than stringified.
Map<String, dynamic> normalizeSongFields(Map<String, dynamic> source) {
  final out = <String, dynamic>{};
  String? scalar(dynamic v) => v is String
      ? (v.replaceAll('\x00', '').trim().isEmpty
            ? null
            : v.replaceAll('\x00', '').trim())
      : v is num && v.isFinite
      ? '$v'
      : null;
  for (final e in source.entries) {
    final key = e.key.trim().toLowerCase();
    if (key.isEmpty || key.contains(RegExp(r'[\x00-\x1f]'))) continue;
    if (e.value is List) {
      final a = (e.value as List).map(scalar).whereType<String>().toList();
      if (a.isNotEmpty) out[key] = a;
    } else {
      final v = scalar(e.value);
      if (v != null) out[key] = v;
    }
  }
  return out;
}
