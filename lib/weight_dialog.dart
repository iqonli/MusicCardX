import 'package:flutter/material.dart';

import 'font_style.dart';

class WeightDialog extends StatefulWidget {
  final String title;
  final double value, min, max;
  final bool variable;
  final List<Map<String, dynamic>> family;
  final List<int> choices;
  const WeightDialog({
    super.key,
    this.title = '字重',
    required this.value,
    required this.min,
    required this.max,
    required this.variable,
    required this.family,
    required this.choices,
  });
  @override
  State<WeightDialog> createState() => _WeightState();
}

class WeightControl extends StatefulWidget {
  final double value, min, max;
  final bool variable;
  final List<Map<String, dynamic>> family;
  final List<int> choices;
  final ValueChanged<int> onChanged;
  const WeightControl({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.variable,
    required this.family,
    required this.choices,
    required this.onChanged,
  });
  @override
  State<WeightControl> createState() => _WeightControlState();
}

class _WeightControlState extends State<WeightControl> {
  late double value = widget.value;
  late final text = TextEditingController(text: '${value.round()}')
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: '${value.round()}'.length,
    );
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  void change(double v) {
    setState(() {
      value = v.clamp(widget.min, widget.max);
      text.text = '${value.round()}';
    });
    widget.onChanged(value.round());
  }

  String label(int n) {
    final match = widget.family.where((r) => effectiveWeight(r) == n);
    return '$n ${match.isEmpty ? const {100: 'Thin', 200: 'ExtraLight', 300: 'Light', 400: 'Regular', 500: 'Medium', 600: 'SemiBold', 700: 'Bold', 800: 'ExtraBold', 900: 'Black'}[n] ?? '' : match.first['subfamily']}';
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 420,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.variable) ...[
          Row(
            children: [
              TextButton(
                onPressed: () => change(value - 100),
                child: const Text('−100'),
              ),
              Expanded(
                child: TextField(
                  controller: text,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  onChanged: (s) {
                    final n = double.tryParse(s);
                    if (n != null && n >= widget.min && n <= widget.max) {
                      setState(() => value = n);
                      widget.onChanged(n.round());
                    }
                  },
                ),
              ),
              TextButton(
                onPressed: () => change(value + 100),
                child: const Text('+100'),
              ),
            ],
          ),
          Slider(
            value: value,
            min: widget.min,
            max: widget.max,
            onChanged: change,
          ),
        ] else
          DropdownButton<int>(
            isExpanded: true,
            value: widget.choices.reduce(
              (a, b) => (a - value).abs() < (b - value).abs() ? a : b,
            ),
            items: [
              for (final n in widget.choices)
                DropdownMenuItem(value: n, child: Text(label(n))),
            ],
            onChanged: (v) => change(v!.toDouble()),
          ),
      ],
    ),
  );
}

class _WeightState extends State<WeightDialog> {
  late int value = widget.value.round();
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: WeightControl(
      value: widget.value,
      min: widget.min,
      max: widget.max,
      variable: widget.variable,
      family: widget.family,
      choices: widget.choices,
      onChanged: (n) => value = n,
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, value),
        child: const Text('确定'),
      ),
    ],
  );
}
