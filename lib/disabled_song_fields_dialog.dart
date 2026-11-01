import 'package:flutter/material.dart';

import 'song_fields.dart';

class DisabledSongFieldsDialog extends StatefulWidget {
  final Set<String> initial;
  const DisabledSongFieldsDialog({super.key, required this.initial});
  @override
  State<DisabledSongFieldsDialog> createState() => _DisabledSongFieldsState();
}

class _DisabledSongFieldsState extends State<DisabledSongFieldsDialog> {
  late final selected = {...widget.initial};
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('请选择要禁用的项目'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in songInputFields.entries)
              CheckboxListTile(
                controlAffinity: ListTileControlAffinity.leading,
                value: selected.contains(entry.key),
                title: Text(
                  entry.value,
                  style: TextStyle(
                    color: selected.contains(entry.key) ? Colors.grey : null,
                    decoration: selected.contains(entry.key)
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                onChanged: (value) => setState(() {
                  if (value == true) {
                    selected.add(entry.key);
                  } else {
                    selected.remove(entry.key);
                  }
                }),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, selected),
        child: const Text('保存'),
      ),
    ],
  );
}
