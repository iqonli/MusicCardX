import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'image_viewer.dart';
import 'model.dart';
import 'song_fields.dart';
import 'renderer.dart';

Map<String, dynamic> songFieldsFromText(String text) {
  final source = text.trim();
  if (source.startsWith('{') || source.startsWith('```')) {
    final value = decodeSongJson(source);
    return normalizeSongFields(
      value['fields'] is Map
          ? Map<String, dynamic>.from(value['fields'])
          : value,
    );
  }
  final fields = <String, dynamic>{};
  for (final line in source.split('\n')) {
    final m = RegExp(r'^\s*([^=:]+)\s*[=:]\s*(.*)$').firstMatch(line);
    if (m != null) fields[m[1]!.trim().toLowerCase()] = m[2]!;
  }
  return normalizeSongFields(fields.isEmpty ? {'title': source} : fields);
}

class SongJsonPage extends StatefulWidget {
  final Map<String, dynamic> fields;
  final Set<String> disabled;
  const SongJsonPage({
    super.key,
    required this.fields,
    this.disabled = const {},
  });
  @override
  State<SongJsonPage> createState() => _SongJsonState();
}

class _SongJsonState extends State<SongJsonPage> {
  late final controller = TextEditingController(
    text: const JsonEncoder.withIndent('  ')
        .convert(normalizeSongFields(widget.fields, disabled: widget.disabled)),
  );
  String? error;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void confirm() {
    try {
      final value = decodeSongJson(controller.text);
      Navigator.pop(
        context,
        normalizeSongFields(value, disabled: widget.disabled),
      );
    } catch (e) {
      setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('编辑歌曲信息JSON'),
    content: SizedBox(
      width: 650,
      height: MediaQuery.sizeOf(context).height * .6,
      child: Column(
        children: [
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.red)),
          Expanded(
            child: TextField(
              controller: controller,
              expands: true,
              maxLines: null,
              minLines: null,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: const InputDecoration(border: InputBorder.none),
            ),
          ),
        ],
      ),
    ),
    actions: [
      Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: controller.text)),
              child: const Text('复制'),
            ),
          ),
          Expanded(
            child: TextButton(
              onPressed: () async {
                final data = await Clipboard.getData(Clipboard.kTextPlain);
                if (mounted) {
                  controller.clear();
                  controller.text = data?.text ?? '';
                  try {
                    final value = decodeSongJson(controller.text);
                    controller.text = const JsonEncoder.withIndent('  ')
                        .convert(
                          normalizeSongFields(value, disabled: widget.disabled),
                        );
                  } catch (_) {
                    /* Keep invalid syntax visible for correction. */
                  }
                }
              },
              child: const Text('粘贴'),
            ),
          ),
          Expanded(
            child: TextButton(onPressed: confirm, child: const Text('确定')),
          ),
        ],
      ),
    ],
  );
}

class SeedFair extends StatefulWidget {
  final CardDocument document;
  final ui.Image? cover;
  final CardRenderer renderer;
  final Future<bool> Function(int width, int height) onOversizedOutput;
  const SeedFair({
    super.key,
    required this.document,
    required this.cover,
    required this.renderer,
    required this.onOversizedOutput,
  });
  @override
  State<SeedFair> createState() => _SeedFairState();
}

class _SeedFairState extends State<SeedFair> {
  final images = <RenderedCard>[];
  final scroll = ScrollController();
  bool busy = false, alive = true, oversizedConfirmed = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
    scroll.addListener(() {
      if (scroll.position.extentAfter < 500) load();
    });
  }

  Future<bool> confirmOversized(int width, int height) async {
    if (oversizedConfirmed) return true;
    final confirmed = await widget.onOversizedOutput(width, height);
    if (confirmed) oversizedConfirmed = true;
    return confirmed;
  }

  Future<void> load() async {
    if (busy || !alive) return;
    setState(() => busy = true);
    try {
      for (int i = 0; i < 20 && alive; i++) {
        final doc = CardDocument(deepCopy(widget.document.data));
        doc.data['seed'] = newSeed();
        final image = await widget.renderer.render(
          doc,
          cover: widget.cover,
          scaleOverride: widget.document.n('exportScale', 1),
          onOversizedOutput: confirmOversized,
        );
        if (!alive) {
          image.image.dispose();
          break;
        }
        final rec = ui.PictureRecorder();
        final w = image.image.width > 720 ? 720 : image.image.width,
            h = (w * image.image.height / image.image.width).round();
        Canvas(rec).drawImageRect(
          image.image,
          Rect.fromLTWH(
            0,
            0,
            image.image.width.toDouble(),
            image.image.height.toDouble(),
          ),
          Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
          Paint()..filterQuality = FilterQuality.high,
        );
        final pic = rec.endRecording();
        final thumb = await pic.toImage(w, h);
        pic.dispose();
        image.image.dispose();
        if (!alive) {
          thumb.dispose();
          break;
        }
        setState(
          () => images.add(
            RenderedCard(
              thumb,
              Size(w.toDouble(), h.toDouble()),
              image.milliseconds,
              image.seed,
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
      }
    } catch (e) {
      if (alive) setState(() => error = '$e');
    } finally {
      if (alive) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    alive = false;
    scroll.dispose();
    for (final i in images) {
      i.image.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('种子博览会')),
    body: ListView.builder(
      controller: scroll,
      itemCount: images.length + 1,
      itemBuilder: (context, i) {
        if (i == images.length) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: busy
                ? const Center(child: CircularProgressIndicator())
                : TextButton(onPressed: load, child: Text(error ?? '再加载20个')),
          );
        }
        final image = images[i];
        return InkWell(
          onTap: () => Navigator.pop(context, image.seed),
          onLongPress: () async {
            final doc = CardDocument(deepCopy(widget.document.data));
            doc.data['seed'] = image.seed;
            final full = await widget.renderer.render(
              doc,
              cover: widget.cover,
              onOversizedOutput: confirmOversized,
            );
            if (!context.mounted) {
              full.image.dispose();
              return;
            }
            try {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CardImageViewer(image: full.image),
                ),
              );
            } finally {
              full.image.dispose();
            }
          },
          child: Column(
            children: [
              AspectRatio(
                aspectRatio: image.image.width / image.image.height,
                child: RawImage(
                  image: image.image,
                  filterQuality: FilterQuality.high,
                  fit: BoxFit.contain,
                ),
              ),
              Text(image.seed),
              const Divider(),
            ],
          ),
        );
      },
    ),
  );
}
