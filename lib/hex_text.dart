import 'package:flutter/services.dart';

/// Hexadecimal colour values and colour expressions are case-insensitive.
/// Do not apply this formatter to lyrics, song fields or title-format code.
class LowerHexFormatter extends TextInputFormatter {
  const LowerHexFormatter();
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toLowerCase());
}

void normalizeDocumentColors(Map<String, dynamic> data) {
  void colors(Map map) {
    for (final key in map.keys.toList()) {
      if (key is String &&
          key.toLowerCase().contains('hex') &&
          map[key] is String) {
        map[key] = (map[key] as String).toLowerCase();
      }
    }
  }

  colors(data);
  if (data['style'] is Map) {
    for (final row in (data['style'] as Map).values) {
      if (row is Map) colors(row);
    }
  }
  if (data['lyrics'] is Map) colors(data['lyrics'] as Map);
  if (data['customEnvironmentColors'] is List) {
    data['customEnvironmentColors'] = (data['customEnvironmentColors'] as List)
        .map((c) => c is String ? c.toLowerCase() : c)
        .toList();
  }
}
