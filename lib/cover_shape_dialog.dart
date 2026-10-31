import 'package:flutter/material.dart';

import 'cover_shape.dart';
import 'model.dart';

const coverShapeNames = {
  'round': '普通圆角',
  'continuous': '连续圆角',
  'superellipse': '超椭圆',
  'bevel': '切角',
  'concave': '内凹角',
  'ellipse': '椭圆',
  'individual': '独立四角',
  'elliptical': '椭圆圆角',
  'quadratic': '二次曲线圆角',
  'scoop': '圆弧内凹角',
};

class CoverShapeDialog extends StatefulWidget {
  final CardDocument document;
  final VoidCallback onChanged;
  const CoverShapeDialog({
    super.key,
    required this.document,
    required this.onChanged,
  });
  @override
  State<CoverShapeDialog> createState() => _CoverShapeDialogState();
}

class _CoverShapeDialogState extends State<CoverShapeDialog> {
  final form = GlobalKey<FormState>();
  final controllers = <String, TextEditingController>{};
  CardDocument get doc => widget.document;
  String get type => doc.text('coverShape');
  Map<String, dynamic> get parameters {
    final all = doc.data.putIfAbsent(
      'coverShapeParameters',
      () => <String, dynamic>{},
    ) as Map<String, dynamic>;
    return all.putIfAbsent(
      type,
      () => <String, dynamic>{
        'coverCornerRadius': doc.n('coverCornerRadius'),
        'coverExponent': 4,
        'cornerRadiusX': 40,
        'cornerRadiusY': 20,
        'cornerTension': 0,
        'cornerTL': 0,
        'cornerTR': 0,
        'cornerBL': 0,
        'cornerBR': 0,
      },
    ) as Map<String, dynamic>;
  }

  Widget field(String key, String label, double min, double max) {
    final id = '$type:$key';
    final values = parameters;
    final controller = controllers.putIfAbsent(
      id,
      () => TextEditingController(
        text: '${values[key] ?? (key == 'coverExponent' ? 4 : 0)}',
      ),
    );
    return TextFormField(
      key: ValueKey(id),
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        helperText: '${min.toInt()}—${max.toInt()}',
      ),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      onTap: () => controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      ),
      validator: (text) {
        final value = double.tryParse(text ?? '');
        return value != null && value.isFinite && value >= min && value <= max
            ? null
            : '请输入${min.toInt()}—${max.toInt()}';
      },
      onChanged: (text) {
        final value = double.tryParse(text);
        if (value == null || !value.isFinite || value < min || value > max) {
          return;
        }
        values[key] = value;
        widget.onChanged();
      },
    );
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('封面圆角'),
    content: SizedBox(
      width: 380,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final e in coverShapeNames.entries)
                    ChoiceChip(
                      label: Text(
                        e.value,
                        style: const TextStyle(fontSize: 13),
                      ),
                      avatar: CoverShapeIcon(e.key),
                      showCheckmark: false,
                      selected: type == e.key,
                      onSelected: (_) {
                        setState(() => doc.data['coverShape'] = e.key);
                        widget.onChanged();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 18),
              if (type == 'elliptical') ...[
                field('cornerRadiusX', '横向半径', 0, 180),
                field('cornerRadiusY', '纵向半径', 0, 180),
              ] else if (type == 'quadratic') ...[
                field('coverCornerRadius', '圆角大小', 0, 180),
                field('cornerTension', '曲线张力', 0, 1),
              ] else if (type == 'superellipse')
                field('coverExponent', '指数', 1, 12)
              else if (type == 'individual') ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: field('cornerTL', '↖', 0, 180)),
                    const SizedBox(width: 12),
                    Expanded(child: field('cornerTR', '↗', 0, 180)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: field('cornerBL', '↙', 0, 180)),
                    const SizedBox(width: 12),
                    Expanded(child: field('cornerBR', '↘', 0, 180)),
                  ],
                ),
              ] else if (type != 'ellipse')
                field('coverCornerRadius', '圆角大小', 0, 180),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () {
          if (form.currentState!.validate()) Navigator.pop(context);
        },
        child: const Text('确定'),
      ),
    ],
  );
}
