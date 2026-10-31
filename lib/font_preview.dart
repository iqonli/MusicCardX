import 'dialog_buttons.dart';

import 'package:flutter/material.dart';

import 'fonts.dart';
import 'font_style.dart';
import 'weight_dialog.dart';

class FontPreviewPage extends StatefulWidget {
  final Map<String, dynamic> row;
  final bool selecting;
  const FontPreviewPage({super.key, required this.row, this.selecting = false});
  @override
  State<FontPreviewPage> createState() => _FontPreviewPageState();
}

class _FontPreviewPageState extends State<FontPreviewPage> {
  final repo = FontRepository.instance;
  late String sample = repo.sample;
  late double size = repo.previewSize;
  late int weight = effectiveWeight(widget.row);
  late Future<LoadedFont> loaded = repo.resolve(
    '${widget.row['id']}',
    weight: weight,
  );
  void setWeight(int n) {
    setState(() {
      weight = n;
      loaded = repo.resolve('${widget.row['id']}', weight: n);
    });
  }

  Widget weightControl() {
    final group = repo.rows
        .where((r) => r['familyKey'] == widget.row['familyKey'])
        .toList();
    final axes = group
        .expand(fontAxes)
        .where((a) => a['tag'] == 'wght')
        .toList();
    final choices = group.map(effectiveWeight).toSet().toList()..sort();
    if (choices.isEmpty) choices.add(weight);
    return WeightControl(
      value: weight.toDouble(),
      min: axes.isEmpty ? 1 : (axes.first['min'] as num).toDouble(),
      max: axes.isEmpty ? 1000 : (axes.first['max'] as num).toDouble(),
      variable: axes.isNotEmpty,
      family: group,
      choices: choices,
      onChanged: setWeight,
    );
  }

  Widget preview(LoadedFont font, double size) => Container(
    width: double.infinity,
    color: const Color(0xffffffff),
    padding: const EdgeInsets.all(8),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Text(
        sample.replaceAll('\n', ' '),
        style: font.style(size).copyWith(color: const Color(0xff000000)),
      ),
    ),
  );
  Future<void> information() async {
    final bytes = await repo.bytes(widget.row);
    final meta = Sfnt.inspect(
      bytes,
      '${widget.row['fileName']}',
    ).firstWhere((r) => r['faceIndex'] == widget.row['faceIndex']);
    if (!mounted) return;
    final names = Map<String, dynamic>.from(meta['names'] ?? {});
    await showCardDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('字体信息'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final e in {
                  '4': 'Full Name',
                  '1': 'Font Family',
                  '2': 'Font Subfamily',
                  '3': 'Unique Subfamily Identification',
                  '5': 'Version',
                  '6': 'PostScript',
                  '9': 'Designer',
                  '0': 'Copyright',
                  '13': 'License',
                  '14': 'License URL',
                  '16': 'Typographic Family',
                  '17': 'Typographic Subfamily',
                }.entries) ...[
                  Text(
                    e.value,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  SelectableText('${names[e.key] ?? '-'}'),
                  const SizedBox(height: 12),
                ],
                Text('字重 ${meta['weight']}  面 ${meta['faceIndex']}'),
                for (final axis in fontAxes(meta))
                  Text(
                    '${axis['tag']}: ${axis['min']} – ${axis['max']} (${axis['default']})',
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void persist() {
    repo.sample = sample;
    repo.previewSize = size;
    repo.save();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('${widget.row['fullName']}'),
      actions: [
        IconButton(
          tooltip: '字体信息',
          onPressed: information,
          icon: const Icon(Icons.info_outline),
        ),
        if (widget.selecting)
          IconButton(
            tooltip: '选择字体',
            onPressed: () => Navigator.pop(context, '${widget.row['id']}'),
            icon: const Icon(Icons.check),
          ),
      ],
    ),
    body: FutureBuilder<LoadedFont>(
      future: loaded,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('字体加载失败：${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final font = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '${widget.row['family']}  ${widget.row['subfamily']}\n${widget.row['fileName']}\n字重 ${widget.row['weight']}',
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: sample,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '预览文本'),
              onChanged: (s) {
                setState(() => sample = s);
                persist();
              },
            ),
            const SizedBox(height: 12),
            const Text('字重'),
            weightControl(),
            for (final n in [12, 18, 24, 36, 48, 60, 72, 80, 88, 96])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(width: 30, child: Text('$n')),
                    Expanded(child: preview(font, n.toDouble())),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: size.toInt().toString(),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '自定义字号 1–512'),
              onChanged: (s) {
                final n = double.tryParse(s);
                if (n != null && n >= 1 && n <= 512) {
                  setState(() => size = n);
                  persist();
                }
              },
            ),
            const SizedBox(height: 12),
            preview(font, size),
            const SizedBox(height: 40),
          ],
        );
      },
    ),
  );
}
