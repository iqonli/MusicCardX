import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Explicit column widths avoid DataTable's intrinsic and flex sizing.
class CompactTextTable extends StatelessWidget {
  final Map<String, String> columns;
  final List<List<String>> rows;
  final String family;
  final void Function(String) onHeader;
  final void Function(int, String) onCell;
  const CompactTextTable({
    super.key,
    required this.columns,
    required this.rows,
    required this.family,
    required this.onHeader,
    required this.onCell,
  });

  @override
  Widget build(BuildContext context) {
    final keys = columns.keys.toList();
    TextStyle style(int c, String value, {bool header = false}) => TextStyle(
      inherit: false,
      letterSpacing: 0,
      fontFamily: family,
      fontSize: 13,
      fontWeight: header
          ? FontWeight.w600
          : value == '开'
          ? FontWeight.w700
          : FontWeight.w400,
      color: value == '开' || value == '关'
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.onSurface,
    );
    double measure(String text, TextStyle style) {
      final p = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final width = p.width.ceilToDouble();
      p.dispose();
      return width;
    }

    final widths = <int, TableColumnWidth>{};
    for (int c = 0; c < keys.length; c++) {
      final label = columns[keys[c]]!;
      double w = measure(label, style(c, label, header: true));
      for (final row in rows) {
        w = math.max(w, measure(row[c], style(c, row[c])));
      }
      if (keys[c] == 'text') w = math.min(w, 200);
      if (keys[c] == 'font') w = math.min(w, 180);
      // Twelve pixels are cell padding, not a lower bound on the content width.
      widths[c] = FixedColumnWidth(w + 12);
    }
    Widget cell(int c, String value, VoidCallback tap, {bool header = false}) =>
        InkWell(
          onTap: tap,
          child: Container(
            height: 34,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style(c, value, header: header),
            ),
          ),
        );
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          columnWidths: widths,
          border: TableBorder(
            horizontalInside: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
              width: .5,
            ),
          ),
          children: [
            TableRow(
              children: [
                for (int c = 0; c < keys.length; c++)
                  cell(
                    c,
                    columns[keys[c]]!,
                    () => onHeader(keys[c]),
                    header: true,
                  ),
              ],
            ),
            for (int r = 0; r < rows.length; r++)
              TableRow(
                children: [
                  for (int c = 0; c < keys.length; c++)
                    cell(c, rows[r][c], () => onCell(r, keys[c])),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
