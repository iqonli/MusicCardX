import 'package:flutter/material.dart';

import 'model.dart';

const defaultImageFilename =
    'MusicCardX-[%title%-][%artist%-][%album%-][%seed%]';

String exportFilename(
  CardDocument doc,
  String extension, {
  String? expression,
  String suffix = '',
}) {
  final fields = Map<String, dynamic>.from(doc.fields);
  // Seed is meaningful only for fusion; metadata must not override this value.
  fields['seed'] = seededBackgrounds.contains(doc.text('backgroundStyle'))
      ? doc.text('seed')
      : '';
  var name = TitleFormat(fields)
      .evaluate(expression ?? doc.text('imageFilename'))
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '');
  if (name.isEmpty || name == '.' || name == '..') name = 'MusicCardX';
  // Leave room for the extension and conflict suffix on Android filesystems.
  final out = StringBuffer();
  var bytes = 0;
  for (final rune in name.runes) {
    final count = rune < 128
        ? 1
        : rune < 2048
        ? 2
        : rune < 65536
        ? 3
        : 4;
    if (bytes + count > 180) break;
    out.writeCharCode(rune);
    bytes += count;
  }
  return '${out.toString()}$suffix.$extension';
}

class FilenameDialog extends StatefulWidget {
  final CardDocument document;
  const FilenameDialog({super.key, required this.document});
  @override
  State<FilenameDialog> createState() => _FilenameDialogState();
}

class _FilenameDialogState extends State<FilenameDialog> {
  late final controller = TextEditingController(
    text: widget.document.text('imageFilename'),
  );
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('保存图片文件名称'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('%字段%读取信息，[内容]有值才显示。%seed%仅融合模式可用。'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              minLines: 2,
              maxLines: 5,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            const Text('文件名预览'),
            Builder(
              builder: (_) {
                try {
                  return SelectableText(
                    exportFilename(
                      widget.document,
                      widget.document.text('imageFormat') == 'jpg'
                          ? 'jpg'
                          : 'png',
                      expression: controller.text,
                    ),
                  );
                } catch (_) {
                  return const Text('标题格式表达式无效');
                }
              },
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => setState(() => controller.text = defaultImageFilename),
        child: const Text('恢复默认'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      TextButton(
        onPressed: () {
          try {
            exportFilename(widget.document, 'png', expression: controller.text);
          } catch (_) {
            return;
          }
          Navigator.pop(context, controller.text);
        },
        child: const Text('保存'),
      ),
    ],
  );
}
