import 'dialog_buttons.dart';
import 'fonts.dart';
import 'color_picker.dart';
import 'image_viewer.dart';
import 'file_browser.dart';
import 'palette_tools.dart';
import 'editor_pages.dart';
import 'font_style.dart';
import 'weight_dialog.dart';
import 'audio_import.dart';
import 'song_fields.dart';
import 'disabled_song_fields_dialog.dart';
import 'compact_table.dart';
import 'cover_shape_dialog.dart';
import 'about_page.dart';
import 'hex_text.dart';
import 'image_export.dart';
import 'raw_cover.dart';
import 'export_filename.dart';
import 'cover_search_page.dart';
import 'song_search_page.dart';

import 'inline_preview.dart';

import 'package:dynamic_color/dynamic_color.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'model.dart';
import 'renderer.dart';

const defaultControlColor = Color(0xffe1e2e8);
Color controlColor(BuildContext context) => useMonet
    ? Theme.of(context).colorScheme.surfaceContainerHighest
    : defaultControlColor;
final themeChanges = ValueNotifier<int>(0);
bool useMonet = false;
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSizeBytes = 32 * 1024 * 1024;
  PaintingBinding.instance.imageCache.maximumSize = 30;
  await CardDocument.initialize();
  final chinese = ChineseConverter();
  await chinese.load();
  CardDocument doc = CardDocument.fresh();
  try {
    final saved = await platform.invokeMethod<String>('loadState');
    if (saved != null) doc = CardDocument.fromJson(mapv(jsonDecode(saved)));
  } catch (_) {
    /* An invalid state never prevents opening the editor. */
  }
  LicenseRegistry.addLicense(() async* {
    for (final entry in <String, String>{
      'MusicCardX / MusicCard': 'LICENSE',
      'IQ Online Studio (ezCD / AutoCoverDownTool)':
          'assets/licenses/IQ-Online-Studio-MIT.txt',
      'opencc-js': 'assets/licenses/opencc-js-MIT.txt',
      'OpenCC数据': 'assets/licenses/opencc-data-Apache.txt',
      'unorm_dart': 'assets/licenses/unorm_dart-MIT.txt',
    }.entries) {
      yield LicenseEntryWithLineBreaks([
        entry.key,
      ], await rootBundle.loadString(entry.value));
    }
  });
  useMonet = doc.data['monet'] == true;
  runApp(MusicCardX(doc, chinese));
}

class MusicCardX extends StatelessWidget {
  final CardDocument document;
  final ChineseConverter chinese;
  const MusicCardX(this.document, this.chinese, {super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: themeChanges,
    builder: (context, _, child) => DynamicColorBuilder(
      builder: (light, dark) {
        final scheme = useMonet && light != null
            ? light
            : ColorScheme.fromSeed(seedColor: Colors.blue);
        return MaterialApp(
          title: 'MusicCardX',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            textTheme: Typography.material2021().black
                .apply(fontSizeFactor: 1)
                .copyWith(
                  bodyMedium: const TextStyle(fontSize: 13),
                  bodyLarge: const TextStyle(fontSize: 13),
                  bodySmall: const TextStyle(fontSize: 13),
                  titleMedium: const TextStyle(fontSize: 13),
                  titleSmall: const TextStyle(fontSize: 13),
                  labelLarge: const TextStyle(fontSize: 13),
                )
                .apply(
                  bodyColor: scheme.onSurface,
                  displayColor: scheme.onSurface,
                ),
            listTileTheme: ListTileThemeData(
              titleTextStyle: TextStyle(
                fontSize: 13,
                color: scheme.onSurface,
                fontFamily: 'Roboto',
              ),
              subtitleTextStyle: TextStyle(
                fontSize: 13,
                color: scheme.onSurfaceVariant,
                fontFamily: 'Roboto',
              ),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                textStyle: const TextStyle(fontSize: 13, fontFamily: 'Roboto'),
                minimumSize: const Size(34, 32),
                backgroundColor: useMonet
                    ? scheme.surfaceContainerHighest
                    : defaultControlColor,
                elevation: 0,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
            colorScheme: scheme,
            brightness: Brightness.light,
            scaffoldBackgroundColor: Colors.white,
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
            ),
            inputDecorationTheme: const InputDecorationTheme(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            cardTheme: const CardThemeData(elevation: 0),
            fontFamily: 'Roboto',
          ),
          home: Editor(document, chinese),
        );
      },
    ),
  );
}

class Editor extends StatefulWidget {
  final CardDocument document;
  final ChineseConverter chinese;
  const Editor(this.document, this.chinese, {super.key});
  @override
  State<Editor> createState() => _EditorState();
}

class _EditorState extends State<Editor> with WidgetsBindingObserver {
  late CardDocument doc;
  late CardRenderer renderer;
  final fonts = FontRegistry();
  ui.Image? cover;
  RenderedCard? rendered;
  Timer? _timer, _saveTimer, _maintenanceTimer;
  bool _rendering = false, _again = false, _working = false;
  String? error;
  final updates = ValueNotifier<int>(0);
  bool pinned = true;
  int tab = 0, revision = 0, renderedRevision = -1;
  String? uiFamily;
  @override
  void initState() {
    super.initState();
    platform.setMethodCallHandler((call) async {
      if (call.method == 'incoming') await incoming();
      if (call.method == 'exportProgress' &&
          _working &&
          call.arguments is num) {
        workStage(_workLabel, (call.arguments as num).toDouble().clamp(0, 1));
      }
    });
    doc = widget.document;
    useMonet = doc.data['monet'] == true;
    pinned = doc.data['previewPinned'] != false;
    renderer = CardRenderer(widget.chinese, fonts);
    WidgetsBinding.instance.addObserver(this);
    initializeFontsAndCover();
    _maintenanceTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => maintainStorage(),
    );
    maintainStorage();
    WidgetsBinding.instance.addPostFrameCallback((_) => incoming());
  }

  final _fontsReady = Completer<void>();
  bool _fontStartupFailed = false;
  Future<void> initializeFontsAndCover() async {
    try {
      await FontRepository.instance.init();
      await _loadUiFont();
      if (!_fontsReady.isCompleted) _fontsReady.complete();
      if (mounted) await _loadCover();
    } catch (e) {
      _fontStartupFailed = true;
      if (!_fontsReady.isCompleted) _fontsReady.complete();
      if (mounted) setState(() => error = '字体初始化失败：$e');
    }
  }

  Future<void> _loadUiFont() async {
    try {
      final f = await fonts.family(doc.text('displayFontName'));
      if (mounted) setState(() => uiFamily = f);
    } catch (e) {
      message('界面字体加载失败：$e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      incoming();
      FontRepository.instance.refresh().then((_) {
        fonts.clear();
        _loadUiFont();
        changed();
      });
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _save();
      maintainStorage();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _saveTimer?.cancel();
    _maintenanceTimer?.cancel();
    maintainStorage();
    cover?.dispose();
    rendered?.image.dispose();
    super.dispose();
  }

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 1500),
          content: Text(text),
        ),
      );
    }
  }

  Map<String, dynamic> configurationSnapshot() {
    final repo = FontRepository.instance;
    if (repo.root != null) {
      doc.data['fontPreferences'] = {
        'mode': repo.mode,
        'tree': repo.tree,
        'sample': repo.sample,
        'previewSize': repo.previewSize,
      };
    }
    return deepCopy(doc.data);
  }

  Future<void> applyConfigurationPreferences(Map<String, dynamic> raw) async {
    pinned = doc.data['previewPinned'] != false;
    if (raw['fontPreferences'] is Map) {
      final repo = FontRepository.instance;
      await repo.init();
      final preferences = mapv(doc.data['fontPreferences']);
      repo.mode = '${preferences['mode'] ?? 'local'}';
      repo.tree = '${preferences['tree'] ?? ''}';
      repo.sample = '${preferences['sample'] ?? repo.sample}';
      repo.previewSize = numv(preferences['previewSize'], 100);
      await repo.save();
      await repo.refresh();
      fonts.clear();
    }
    await _loadUiFont();
    themeChanges.value++;
  }

  Future<void> _save() async {
    try {
      await platform.invokeMethod('saveState', {
        'json': jsonEncode(configurationSnapshot()),
      });
      await maintainStorage();
    } catch (e) {
      message('保存失败：$e');
    }
  }

  Future<void> maintainStorage() async {
    try {
      await platform.invokeMethod('maintainStorage');
      await FontRepository.instance.pruneCache();
    } catch (_) {
      /* Cleanup is best effort; it must never block editing. */
    }
  }

  bool _pendingInput = false;
  double? _workProgress;
  String _workLabel = '处理中';
  void inputChanged() {
    _pendingInput = true;
    revision++;
    _timer?.cancel();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), _save);
  }

  void commitInput() {
    if (!_pendingInput) return;
    _pendingInput = false;
    changed();
  }

  void workStage(String label, [double? progress]) {
    if (mounted) {
      setState(() {
        _workLabel = label;
        _workProgress = progress;
      });
    }
  }

  void changed() {
    if (!mounted) return;
    revision++;
    useMonet = doc.data['monet'] == true;
    themeChanges.value++;
    updates.value++;
    updatePalette();
    setState(() => error = null);
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 300), _preview);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), _save);
  }

  Future<void> _loadCover() async {
    ui.Image? image;
    try {
      final path = doc.text('coverPath');
      if (path.isNotEmpty) {
        final bytes = await File(path).readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        image = (await codec.getNextFrame()).image;
        codec.dispose();
      }
    } catch (e) {
      message('封面读取失败，请重新选择：$e');
    }
    if (!mounted) {
      image?.dispose();
      return;
    }
    final old = cover;
    cover = image;
    old?.dispose();
    await updatePalette();
    await _preview();
  }

  Future<void> _preview() async {
    await _fontsReady.future;
    if (!mounted || _fontStartupFailed) return;
    if (_rendering) {
      _again = true;
      return;
    }
    _rendering = true;
    if (mounted) setState(() {});
    final token = revision;
    try {
      final result = await renderer.render(
        CardDocument(deepCopy(doc.data)),
        cover: cover,
        scaleOverride: doc.n('exportScale', 1),
      );
      if (!mounted || token != revision) {
        result.image.dispose();
      } else {
        final old = rendered;
        setState(() {
          rendered = result;
          renderedRevision = token;
          error = null;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          old?.image.dispose();
        });
      }
    } catch (e) {
      if (mounted && token == revision) setState(() => error = '$e');
    } finally {
      _rendering = false;
      if (mounted) setState(() {});
      if (_again) {
        _again = false;
        _preview();
      }
    }
  }

  Future<void> busy(Future<void> Function() fn) async {
    if (_working) return;
    setState(() {
      _working = true;
      _workProgress = null;
      _workLabel = '处理中';
    });
    try {
      await fn();
    } catch (e) {
      message('$e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> pickCover() async => busy(() async {
    final path = await platform.invokeMethod<String>('pickCover');
    if (path != null) {
      doc.data['coverPath'] = path;
      revision++;
      await _loadCover();
      await _save();
    }
  });
  Future<void> export(String action) async => busy(() async {
    FocusManager.instance.primaryFocus?.unfocus();
    commitInput();
    workStage('准备图片');
    await Future<void>.delayed(Duration.zero);
    final cached =
        !_rendering && renderedRevision == revision && _timer?.isActive != true
        ? rendered
        : null;
    final result = cached == null
        ? await renderer.render(doc, cover: cover)
        : RenderedCard(
            cached.image.clone(),
            cached.size,
            cached.milliseconds,
            cached.seed,
          );
    try {
      workStage('压缩图片');
      final encoded = await encodeExportImage(
        result.image,
        ImageExportOptions.fromMap(doc.data),
      );
      final bytes = encoded.bytes;
      final filename = exportFilename(doc, encoded.extension);
      workStage(
        action == 'saveImage'
            ? '保存图片'
            : action == 'shareImage'
            ? '准备分享'
            : '复制图片',
      );
      if (action == 'saveImage') {
        if (Platform.isAndroid &&
            await platform.invokeMethod<bool>('requestStorage') != true) {
          return;
        }
        if (doc.text('imageFolder').isEmpty) {
          if (!await chooseImageFolder()) return;
        }
        final directory = Directory(doc.text('imageFolder'));
        await directory.create(recursive: true);
        final safeName = filename.replaceAll(
          RegExp(r'[\\/:*?"<>|\x00-\x1f]'),
          '_',
        );
        var target = File('${directory.path}/$safeName');
        if (await target.exists()) {
          target = File(
            '${directory.path}/${safeName.substring(0, safeName.length - 4)}-${DateTime.now().millisecondsSinceEpoch}.${encoded.extension}',
          );
        }
        final sink = await target.open(mode: FileMode.write);
        try {
          const chunk = 256 * 1024;
          for (var offset = 0; offset < bytes.length; offset += chunk) {
            final end = (offset + chunk).clamp(0, bytes.length);
            await sink.writeFrom(bytes, offset, end);
            workStage('保存图片', end / bytes.length);
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        await platform.invokeMethod('scanImage', {
          'path': target.path,
          'mime': encoded.mimeType,
        });
        message('已保存 ${target.path}');
        return;
      }
      final response = await platform.invokeMethod<String>(action, {
        'bytes': bytes,
        'name': filename,
        'mime': encoded.mimeType,
      });
      if (response != null) message(response);
    } finally {
      result.image.dispose();
    }
  });
  Future<String?> editText(
    String title,
    String value, {
    String? note,
    int lines = 1,
    bool hexInput = false,
    bool numeric = false,
    bool benchmark = false,
    bool slider = false,
    double sliderMin = 0,
    double sliderMax = 100,
    String? Function(String)? validate,
  }) async {
    final controller = TextEditingController(
      text: hexInput ? value.toLowerCase() : value,
    );
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: value.length,
    );
    final form = GlobalKey<FormState>();
    final result = await showCardDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 480,
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (note != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      note,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                TextFormField(
                  controller: controller,
                  inputFormatters: hexInput
                      ? const [LowerHexFormatter()]
                      : null,
                  minLines: lines,
                  maxLines: lines == 1 ? 1 : 12,
                  autofocus: true,
                  keyboardType: numeric
                      ? const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        )
                      : TextInputType.multiline,
                  validator: (s) => validate?.call(s ?? ''),
                ),
                if (slider)
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (_, value, _) => Slider(
                      value: (double.tryParse(value.text) ?? sliderMin).clamp(
                        sliderMin,
                        sliderMax,
                      ),
                      min: sliderMin,
                      max: sliderMax,
                      onChanged: (v) => controller.text = v.toStringAsFixed(1),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          if (hexInput)
            TextButton(
              onPressed: () async {
                final c = await pickCardColor(ctx, '#2196f3');
                if (c == null) return;
                final sel = controller.selection;
                final start = sel.isValid ? sel.start : controller.text.length,
                    end = sel.isValid ? sel.end : controller.text.length;
                final insert = start > 0 && controller.text[start - 1] == '#'
                    ? c.substring(1)
                    : c;
                controller.value = TextEditingValue(
                  text: controller.text.replaceRange(start, end, insert),
                  selection: TextSelection.collapsed(
                    offset: start + insert.length,
                  ),
                );
              },
              child: const Text('插入'),
            ),
          if (benchmark)
            TextButton(
              onPressed: () => runBenchmark(),
              child: const Text('测试'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(ctx, controller.text);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    // Dialog route may still be animating out; controller is released after that transition.
    Future.delayed(const Duration(milliseconds: 400), controller.dispose);
    return result;
  }

  Widget setting(
    String title,
    String value,
    VoidCallback onTap, {
    String? subtitle,
    IconData? icon,
    IconData? valueIcon,
  }) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Container(
      margin: const EdgeInsets.all(3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      constraints: const BoxConstraints(minHeight: 34, maxWidth: 360),
      decoration: BoxDecoration(
        color: controlColor(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 6)],
          if (title.isNotEmpty)
            Flexible(
              child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          if (value.isNotEmpty) ...[
            if (title.isNotEmpty) const SizedBox(width: 8),
            if (valueIcon != null) ...[
              Icon(valueIcon, size: 18),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: value == '开' ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
  Widget toggle(
    String title,
    Map<String, dynamic> map,
    String key, {
    String? subtitle,
  }) => InkWell(
    onTap: () {
      map[key] = map[key] != true;
      changed();
    },
    borderRadius: BorderRadius.circular(16),
    child: Container(
      margin: const EdgeInsets.all(3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: controlColor(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$title  '),
            TextSpan(
              text: map[key] == true ? '开' : '关',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: map[key] == true
                    ? FontWeight.w700
                    : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Widget textSetting(
    String title,
    Map<String, dynamic> map,
    String key, {
    String? note,
    int lines = 1,
    bool color = false,
  }) => setting(
    title,
    title == '歌词内容'
        ? '${'${map[key] ?? ''}'.isEmpty ? 0 : '${map[key]}'.split('\n').length}行'
        : '${map[key] ?? ''}'.isEmpty
        ? (color ? '自动' : '留空')
        : color
        ? '${map[key]}'.toLowerCase()
        : '${map[key]}',
    () async {
      final v = await editText(
        title,
        '${map[key] ?? ''}',
        note: color ? hexNote : note,
        hexInput: color,
        lines: lines,
        validate: color
            ? (s) => validColor(s) ? null : '请输入有效HEX、black、white或彩虹色表达式'
            : null,
      );
      if (v != null) {
        map[key] = v;
        changed();
      }
    },
  );
  Widget number(
    String title,
    Map<String, dynamic> map,
    String key,
    double min,
    double max, {
    bool empty = false,
    String? note,
  }) => setting(
    title,
    '${map[key] ?? ''}'.isEmpty ? '原生排版' : '${map[key]}',
    () async {
      final v = await editText(
        title,
        '${map[key] ?? ''}',
        numeric: true,
        benchmark: key == 'rainbowSampleMaxSide',
        slider: key == 'blurBackgroundCropPosition',
        sliderMin: min,
        sliderMax: max,
        note: note ?? '范围 $min–$max，最多三位小数${empty ? '；留空使用原生整段排版' : ''}',
        validate: (s) {
          if (empty && s.trim().isEmpty) return null;
          final n = double.tryParse(s);
          if (n == null ||
              !n.isFinite ||
              n < min ||
              n > max ||
              !RegExp(r'^-?(?:\d+(?:\.\d{0,3})?|\.\d{1,3})$').hasMatch(s)) {
            return '请输入范围内的数值，最多三位小数';
          }
          return null;
        },
      );
      if (v != null) {
        map[key] = empty && v.trim().isEmpty ? '' : double.parse(v);
        changed();
      }
    },
  );
  Widget choice(
    String title,
    Map<String, dynamic> map,
    String key,
    Map<String, String> choices,
  ) => setting(title, choices['${map[key]}'] ?? '${map[key]}', () async {
    if (choices.length <= 3) {
      final keys = choices.keys.toList();
      final i = keys.indexOf('${map[key]}');
      map[key] = keys[(i + 1) % keys.length];
      changed();
      return;
    }
    final v = await showCardDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: [
          for (final e in choices.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, e.key),
              child: Text(e.value),
            ),
        ],
      ),
    );
    if (v != null) {
      map[key] = v;
      changed();
    }
  });
  Widget section(String title, List<Widget> children) =>
      panel(title, [children]);
  Widget panel(
    String title,
    List<List<Widget>> rows, {
    Map<String, dynamic>? optional,
    String? enabledKey,
  }) {
    final enabled = optional == null || optional[enabledKey] == true;
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 5, 10, 5),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: optional == null
                ? null
                : () {
                    optional[enabledKey!] = !enabled;
                    changed();
                  },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(5, 3, 5, 7),
              child: Row(
                children: [
                  Text(
                    optional == null ? title : '$title：${enabled ? '开' : '关'}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: optional == null
                          ? null
                          : Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  if (optional != null)
                    Icon(
                      enabled ? Icons.expand_less : Icons.expand_more,
                      size: 19,
                    ),
                ],
              ),
            ),
          ),
          if (enabled)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final row in rows)
                    Row(mainAxisSize: MainAxisSize.min, children: row),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget actionTile(ListTile tile) => Padding(
    padding: const EdgeInsets.all(3),
    child: Material(
      color: controlColor(context),
      elevation: 0,
      shadowColor: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: tile,
    ),
  );
  Widget normalSection(String title, List<Widget> children) => Card(
    margin: const EdgeInsets.all(12),
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title.isNotEmpty &&
              !const {'歌词内容', '显示', '字体', '图片', '配置'}.contains(title)) ...[
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
          ],
          for (final child in children)
            child is ListTile ? actionTile(child) : child,
        ],
      ),
    ),
  );
  Future<bool> pickFont(Map<String, dynamic> map) async {
    try {
      final id = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => const FontLibraryPage(selecting: true),
        ),
      );
      if (id != null) {
        map['font'] = id;
        final row = FontRepository.instance.lookup(id);
        map['weight'] = row == null ? 400 : effectiveWeight(row);
        map['bold'] = false;
        await fonts.family(id);
        changed();
        return true;
      }
    } catch (e) {
      message('字体读取失败：$e');
    }
    return false;
  }

  Future<void> manageFonts() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FontLibraryPage()),
    );
    fonts.clear();
    changed();
  }

  Widget fontSetting(Map<String, dynamic> style) => setting(
    '字体',
    FontRepository.instance.name('${style['font'] ?? ''}'),
    () => pickFont(style),
  );
  List<Widget> styleControls(Map<String, dynamic> s, {bool lyrics = false}) => [
    textSetting(
      lyrics ? '歌词内容' : '文本内容',
      s,
      'text',
      lines: lyrics ? 6 : 2,
      note: '直接输入文字，或使用 %title%、%artist%、%album%、%datey% 等手动字段。',
    ),
    number('字号', s, 'size', .001, 1000),
    fontSetting(s),
    weightSetting(s),
    toggle('斜体', s, 'italic'),
    textSetting(
      'HEX',
      s,
      'colorHex',
      color: true,
      note: '留空自动黑白；HEX、black、white；r%20或r%20+#114514表示从基础色向封面目标色混合20%。',
    ),
    number('不透明度', s, 'opacity', 0, 255),
    number('模糊强度', s, 'blurStrength', 0, 255),
    number('模糊不透明度', s, 'blurOpacity', 0, 255),
    number(
      '字间距',
      s,
      'letterSpacing',
      -1000,
      1000,
      empty: true,
      note: '留空保留字距调整和连字；0或其他数值逐字绘制。支持负数和三位小数。',
    ),
  ];
  Future<void> elementPage(String key) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => ValueListenableBuilder<int>(
          valueListenable: updates,
          builder: (ctx, value, child) => Scaffold(
            appBar: AppBar(title: Text(styleLabels[key]!)),
            body: ListView(
              children: [
                normalSection('独立文字样式', styleControls(doc.styles[key])),
              ],
            ),
          ),
        ),
      ),
    );
    changed();
  }

  String? batchNumberError(String key, String value) {
    final n = double.tryParse(value);
    final low = key == 'letterSpacing'
        ? -1000.0
        : key == 'size'
        ? 0.001
        : 0.0;
    final high = key == 'size' || key == 'letterSpacing' ? 1000.0 : 255.0;
    if (n == null ||
        !n.isFinite ||
        n < low ||
        n > high ||
        !RegExp(r'^-?(?:\d+(?:\.\d{0,3})?|\.\d{1,3})$').hasMatch(value)) {
      return '请输入 $low–$high，最多三位小数';
    }
    return null;
  }

  Future<void> columnEdit([String? column]) async {
    final result =
        column ??
        await showCardDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('批量修改八个文字元素'),
            children: [
              for (final e in {
                'size': '字号',
                'font': '字体',
                'weight': '字重',
                'italic': '斜体',
                'colorHex': '颜色',
                'opacity': '不透明度',
                'blurStrength': '模糊强度',
                'blurOpacity': '模糊不透明度',
                'letterSpacing': '字间距',
              }.entries)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, e.key),
                  child: Text(e.value),
                ),
            ],
          ),
        );
    if (result == null || !mounted) return;
    final sample = mapv(doc.styles['titleValue']);
    if (result == 'weight') {
      if (!await pickWeight(sample)) return;
    } else if (result == 'font') {
      if (!await pickFont(sample)) return;
    } else if (result == 'bold' || result == 'italic') {
      sample[result] = sample[result] != true;
    } else {
      final value = await editText(
        '批量设置 $result',
        '${sample[result] ?? ''}',
        lines: result == 'text' ? 3 : 1,
        hexInput: result == 'colorHex',
        numeric: result != 'text' && result != 'colorHex',
        note: result == 'colorHex' ? hexNote : null,
        validate: (v) => result == 'text'
            ? null
            : result == 'colorHex'
            ? (validColor(v) ? null : '颜色格式无效')
            : result == 'letterSpacing' && v.isEmpty
            ? null
            : batchNumberError(result, v),
      );
      if (value == null) return;
      sample[result] =
          result == 'text' ||
              result == 'colorHex' ||
              result == 'letterSpacing' && value.isEmpty
          ? value
          : numv(value);
    }
    for (final s in doc.styles.values) {
      s[result] = sample[result];
    }
    changed();
  }

  Future<void> importConfig() async => busy(() async {
    final picked = await browseFiles(context, extensions: {'json'});
    if (picked == null || picked.isEmpty) return;
    final input = await File(picked.first).readAsBytes();
    if (input.length > 8 * 1024 * 1024) throw const FormatException('配置文件过大');
    final raw = input.length >= 2 && input[0] == 255 && input[1] == 254
        ? String.fromCharCodes([
            for (int i = 2; i + 1 < input.length; i += 2)
              input[i] | input[i + 1] << 8,
          ])
        : utf8.decode(input).replaceFirst('\uFEFF', '');
    final parsed = mapv(jsonDecode(raw));
    parsed.putIfAbsent('fields', () => deepCopy(doc.fields));
    parsed.putIfAbsent('coverPath', () => doc.text('coverPath'));
    final next = CardDocument.fromJson(parsed);
    if (!parsed.containsKey('imageFolder')) {
      next.data['imageFolder'] = doc.text('imageFolder');
    }
    doc = next;
    await applyConfigurationPreferences(parsed);
    changed();
    _timer?.cancel();
    await _loadCover();
    await _save();
    setState(() {});
    message('配置已导入');
  });
  Future<void> saveConfig() async => busy(() async {
    await FontRepository.instance.init();
    if (!mounted) return;
    final picked = await browseFiles(context, directory: true);
    if (picked == null || picked.isEmpty) return;
    final file = File(
      '${picked.first}/MusicCardX-${DateTime.now().millisecondsSinceEpoch}.json',
    );
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(configurationSnapshot()),
    );
    message('已保存 ${file.path}');
  });
  Future<bool> chooseImageFolder() async {
    final picked = await browseFiles(
      context,
      directory: true,
      initial: doc.text('imageFolder').isEmpty ? null : doc.text('imageFolder'),
    );
    if (picked == null || picked.isEmpty) return false;
    doc.data['imageFolder'] = picked.first;
    changed();
    return true;
  }

  Future<void> library() async {
    final items = await platform.invokeListMethod<String>('listPresets') ?? [];
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: 450,
          child: Column(
            children: [
              ListTile(
                title: const Text('本地配置库'),
                trailing: IconButton(
                  icon: const Icon(Icons.save_outlined),
                  tooltip: '保存当前配置',
                  onPressed: () async {
                    final name = await editText('配置名称', '新配置');
                    if (name != null && name.trim().isNotEmpty) {
                      try {
                        await FontRepository.instance.init();
                        await platform.invokeMethod('savePreset', {
                          'name': name.trim(),
                          'json': jsonEncode(configurationSnapshot()),
                        });
                        if (ctx.mounted) Navigator.pop(ctx);
                        message('已保存到配置库');
                      } catch (e) {
                        message('$e');
                      }
                    }
                  },
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? const Center(child: Text('暂无配置，点击右上角保存当前样式'))
                    : ListView(
                        children: [
                          for (final name in items)
                            ListTile(
                              title: Text(name),
                              onTap: () async {
                                try {
                                  final raw = await platform
                                      .invokeMethod<String>('loadPreset', {
                                        'name': name,
                                      });
                                  if (raw == null) return;
                                  final parsed = mapv(jsonDecode(raw));
                                  final next = CardDocument.fromJson(parsed);
                                  next.data['fields'] = doc.fields;
                                  next.data['coverPath'] = doc.text(
                                    'coverPath',
                                  );
                                  if (!parsed.containsKey('imageFolder')) {
                                    next.data['imageFolder'] = doc.text(
                                      'imageFolder',
                                    );
                                  }
                                  doc = next;
                                  await applyConfigurationPreferences(parsed);
                                  changed();
                                  if (ctx.mounted) Navigator.pop(ctx);
                                } catch (e) {
                                  message('$e');
                                }
                              },
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: '重命名配置',
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: () async {
                                      final next = await editText('配置名称', name);
                                      if (next == null ||
                                          next.trim().isEmpty ||
                                          next.trim() == name) {
                                        return;
                                      }
                                      try {
                                        await platform.invokeMethod(
                                          'renamePreset',
                                          {
                                            'name': name,
                                            'newName': next.trim(),
                                          },
                                        );
                                        if (ctx.mounted) Navigator.pop(ctx);
                                        await library();
                                      } catch (e) {
                                        message('$e');
                                      }
                                    },
                                  ),
                                  IconButton(
                                    tooltip: '复制配置',
                                    icon: const Icon(Icons.copy_outlined),
                                    onPressed: () async {
                                      try {
                                        var copy = '$name副本';
                                        var n = 2;
                                        while (items.contains(copy)) {
                                          copy = '$name副本$n';
                                          n++;
                                        }
                                        final raw = await platform
                                            .invokeMethod<String>(
                                              'loadPreset',
                                              {'name': name},
                                            );
                                        if (raw == null) return;
                                        await platform.invokeMethod(
                                          'savePreset',
                                          {'name': copy, 'json': raw},
                                        );
                                        if (ctx.mounted) Navigator.pop(ctx);
                                        await library();
                                      } catch (e) {
                                        message('$e');
                                      }
                                    },
                                  ),
                                  IconButton(
                                    tooltip: '删除配置',
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () async {
                                      final yes = await confirm('删除配置“$name”？');
                                      if (yes) {
                                        await platform.invokeMethod(
                                          'deletePreset',
                                          {'name': name},
                                        );
                                        if (ctx.mounted) Navigator.pop(ctx);
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> confirm(String text) async =>
      await showCardDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确定'),
            ),
          ],
        ),
      ) ??
      false;
  Future<bool> confirmCover(String path) async =>
      await showCardDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('替换当前封面？'),
          content: SizedBox(
            width: 320,
            height: 280,
            child: Image.file(
              File(path),
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              cacheWidth: 960,
              errorBuilder: (_, e, st) => const Text('图片无法预览'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('确定'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> searchSongInformation({String? sharedText}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    commitInput();
    final fields = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => SongSearchPage(
          document: doc,
          onSettings: _save,
          initialShareText: sharedText,
          onFields: (fields) async {
            doc.data['fields'] = fields;
            setState(() => doc = CardDocument(deepCopy(doc.data)));
            changed();
          },
          onCover: applySharedCover,
          onSaveCover: saveCoverAsset,
        ),
      ),
    );
    if (fields == null || !mounted) return;
    doc.data['fields'] = fields;
    setState(() => doc = CardDocument(deepCopy(doc.data)));
    changed();
  }

  Future<void> searchCover() async {
    FocusManager.instance.primaryFocus?.unfocus();
    commitInput();
    final asset = await Navigator.push<CoverAsset>(
      context,
      MaterialPageRoute(
        builder: (_) => CoverSearchPage(
          document: doc,
          onSettings: _save,
          onSave: saveCoverAsset,
        ),
      ),
    );
    if (asset == null || !mounted) return;
    await busy(() async {
      final root = await platform.invokeMethod<String>('storageRoot');
      if (root == null) throw const FileSystemException('无法读取应用目录');
      final directory = Directory('$root/covers');
      await directory.create(recursive: true);
      final file = File(
        '${directory.path}/online-${DateTime.now().microsecondsSinceEpoch}.image',
      );
      final temporary = File('${file.path}.part');
      try {
        await temporary.writeAsBytes(asset.bytes, flush: true);
        await temporary.rename(file.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
      doc.data['coverPath'] = file.path;
      revision++;
      await _loadCover();
      await _save();
    });
  }

  Future<void> applySharedCover(CoverAsset asset) async {
    await busy(() async {
      final root = await platform.invokeMethod<String>('storageRoot');
      if (root == null) throw const FileSystemException('无法读取应用目录');
      final directory = Directory('$root/covers');
      await directory.create(recursive: true);
      final file = File(
        '${directory.path}/online-${DateTime.now().microsecondsSinceEpoch}.image',
      );
      final temporary = File('${file.path}.part');
      try {
        await temporary.writeAsBytes(asset.bytes, flush: true);
        await temporary.rename(file.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
      doc.data['coverPath'] = file.path;
      revision++;
      await _loadCover();
      await _save();
    });
  }

  Future<bool> saveCoverAsset(CoverAsset asset) async {
    if (Platform.isAndroid &&
        await platform.invokeMethod<bool>('requestStorage') != true) {
      return false;
    }
    if (doc.text('imageFolder').isEmpty && !await chooseImageFolder()) {
      return false;
    }
    final type = coverFileType(asset.bytes);
    final name = exportFilename(doc, type.extension, suffix: '-cover');
    final file = await writeRawCover(
      Directory(doc.text('imageFolder')),
      name,
      asset.bytes,
    );
    await platform.invokeMethod('scanImage', {
      'path': file.path,
      'mime': type.mime,
    });
    return true;
  }

  Future<void> saveCover() async => busy(() async {
    if (cover == null) return;
    final path = doc.text('coverPath');
    if (path.isEmpty) throw const FileSystemException('封面源文件不存在');
    final bytes = await File(path).readAsBytes();
    if (await saveCoverAsset(CoverAsset(bytes, cover!.width, cover!.height))) {
      message('封面已保存');
    }
  });
  Future<void> pickAudio() async => busy(() async {
    final files = await browseFiles(
      context,
      extensions: audioExtensions,
      multiple: false,
    );
    if (files == null || files.isEmpty) return;
    await importAudio(files.first);
  });
  Future<void> importAudio(String path) async {
    final data = await compute(readAudioInformation, path);
    final image = data.cover;
    String? imagePath;
    if (image != null) {
      final root = await platform.invokeMethod<String>('storageRoot');
      if (root == null) throw const FileSystemException('无法访问应用目录');
      final f = File(
        '$root/covers/audio-${DateTime.now().microsecondsSinceEpoch}.image',
      );
      await f.parent.create(recursive: true);
      await f.writeAsBytes(image);
      imagePath = f.path;
    }
    doc.data['fields'] = data.fields;
    doc.lyrics['text'] = data.lyrics ?? '';
    if (imagePath != null) {
      doc.data['coverPath'] = imagePath;
      await _loadCover();
    }
    setState(() => doc = CardDocument(deepCopy(doc.data)));
    changed();
    message('歌曲信息已读取');
  }

  Future<void> manageDisabledSongFields() async {
    FocusManager.instance.primaryFocus?.unfocus();
    commitInput();
    final disabled = await showCardDialog<Set<String>>(
      context: context,
      builder: (_) => DisabledSongFieldsDialog(initial: doc.disabledSongFields),
    );
    if (disabled == null || !mounted) return;
    doc.data['disabledSongFields'] = disabled.toList();
    setState(() => doc = CardDocument(deepCopy(doc.data)));
    changed();
  }

  Future<void> clearSongCoverLyrics() async {
    FocusManager.instance.primaryFocus?.unfocus();
    commitInput();
    if (!await confirm('清空歌曲信息、封面与歌词？') || !mounted) return;
    doc.fields.clear();
    doc.lyrics['text'] = '';
    doc.data['coverPath'] = '';
    revision++;
    await _loadCover();
    if (!mounted) return;
    setState(() => doc = CardDocument(deepCopy(doc.data)));
    changed();
  }

  Widget inputPage() => Theme(
    data: Theme.of(context).copyWith(
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      textTheme: Theme.of(context).textTheme
          .apply(fontFamily: uiFamily ?? 'Roboto'),
      listTileTheme: Theme.of(context).listTileTheme.copyWith(
        minTileHeight: 48,
        dense: false,
        titleTextStyle: Theme.of(context).listTileTheme.titleTextStyle
            ?.copyWith(fontFamily: uiFamily ?? 'Roboto'),
        subtitleTextStyle: Theme.of(context).listTileTheme.subtitleTextStyle
            ?.copyWith(fontFamily: uiFamily ?? 'Roboto'),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(34, 34),
          backgroundColor: controlColor(context),
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          textStyle: TextStyle(fontSize: 13, fontFamily: uiFamily ?? 'Roboto'),
          visualDensity: VisualDensity.standard,
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
    ),
    child: GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: Column(children: pageChildren(fieldsPage())),
    ),
  );

  Widget fieldsPage() => ListView(
    children: [
      normalSection('歌曲信息', [
        for (final e in songInputFields.entries)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 7, 16, 7),
            child: Focus(
              onFocusChange: (focused) {
                if (!focused) commitInput();
              },
              child: TextFormField(
                key: ValueKey('field-${e.key}-${doc.hashCode}'),
                enabled: !doc.disabledSongFields.contains(e.key),
                initialValue: doc.disabledSongFields.contains(e.key)
                    ? '已禁用'
                    : '${doc.fields[e.key] ?? ''}',
                decoration: InputDecoration(labelText: e.value),
                onChanged: (v) {
                  doc.fields[e.key] = v;
                  inputChanged();
                },
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: searchSongInformation,
            child: const Text('在线搜索'),
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton(onPressed: songJson, child: const Text('编辑歌曲信息JSON')),
            TextButton(
              onPressed: () async {
                if (await confirm('清空歌曲信息？')) {
                  doc.fields.clear();
                  setState(() => doc = CardDocument(deepCopy(doc.data)));
                  changed();
                }
              },
              child: const Text('清空歌曲信息'),
            ),
            TextButton(
              onPressed: manageDisabledSongFields,
              child: const Text('管理禁用项目'),
            ),
          ],
        ),
      ]),
      normalSection('封面', [
        Row(
          children: [
            Flexible(
              child: TextButton(
                onPressed: pickCover,
                child: Text(
                  cover == null
                      ? '选择图片'
                      : '选择图片 当前封面${cover!.width}×${cover!.height}',
                ),
              ),
            ),
            TextButton(onPressed: searchCover, child: const Text('在线搜索封面')),
          ],
        ),
        Row(
          children: [
            TextButton(
              onPressed: cover == null ? null : saveCover,
              child: const Text('保存封面'),
            ),
            TextButton(
              onPressed: cover == null
                  ? null
                  : () async {
                      if (!await confirm('移除当前封面？')) return;
                      doc.data['coverPath'] = '';
                      revision++;
                      await _loadCover();
                      await _save();
                    },
              child: const Text('移除封面'),
            ),
          ],
        ),
      ]),
      normalSection('', [
        Wrap(
          spacing: 8,
          children: [
            TextButton(onPressed: pickAudio, child: const Text('从音频文件读取')),
            TextButton(
              onPressed: clearSongCoverLyrics,
              child: const Text('清空歌曲信息、封面与歌词'),
            ),
          ],
        ),
      ]),
      normalSection('歌词内容', [
        Focus(
          onFocusChange: (focused) {
            if (!focused) commitInput();
          },
          child: TextFormField(
            key: ValueKey('lyrics-${doc.hashCode}'),
            initialValue: '${doc.lyrics['text']}',
            minLines: 4,
            maxLines: 10,
            decoration: const InputDecoration(labelText: '歌词内容'),
            onChanged: (v) {
              doc.lyrics['text'] = v;
              inputChanged();
            },
          ),
        ),

        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () async {
              if (!await confirm('清空歌词内容？')) return;
              doc.lyrics['text'] = '';
              setState(() => doc = CardDocument(deepCopy(doc.data)));
              changed();
            },
            child: const Text('清空歌词内容'),
          ),
        ),
      ]),
      const SizedBox(height: 24),
    ],
  );
  Widget backgroundPanel() => panel('样式配置', [
    [
      number('输出倍率', doc.data, 'exportScale', .1, 10),
      choice('背景', doc.data, 'backgroundStyle', backgrounds),
      if (doc.text('backgroundStyle') == 'solid')
        setting('自定义', '', () async {
          final value = await pickCardColor(
            context,
            colorHex(tokenColor(doc.text('solidHex'), Colors.black)),
            title: '自定义',
          );
          if (value != null) {
            doc.data['solidHex'] = value;
            changed();
          }
        }),
      choice('简繁', doc.data, 'textOpenCCMode', ccModes),
    ],
    [
      number('模糊强度', doc.data, 'blurStrength', 0, 500),
      setting(
        '封面圆角',
        const {
              'round': '普通圆角',
              'continuous': '连续圆角',
              'bevel': '切角',
              'concave': '内凹角',
              'ellipse': '椭圆',
              'individual': '独立四角',
              'superellipse': '超椭圆',
            }[doc.text('coverShape')] ??
            '普通圆角',
        shapeSettings,
      ),
    ],
    [
      number('封面阴影不透明度', doc.data, 'coverShadowOpacity', 0, 255),
      number('阴影深度', doc.data, 'coverShadowDepth', 0, 100),
      choice('不规则封面', doc.data, 'irregularCoverMode', {
        'crop': '裁剪',
        'tile': '平铺',
      }),
    ],
    if (doc.text('backgroundStyle') == 'blur')
      [number('背景截取封面位置 %', doc.data, 'blurBackgroundCropPosition', 0, 100)],
    if (doc.text('backgroundStyle') == 'solid')
      [textSetting('纯色', doc.data, 'solidHex', color: true)],
  ]);
  Widget lyricsPanel() {
    final ly = doc.lyrics;
    final controls = styleControls(ly, lyrics: true);
    return panel(
      '歌词排版',
      [
        [
          number('容器宽度', ly, 'containerWidth', 0, 10000),
          controls[0],
          controls[1],
          choice('简繁', doc.data, 'lyricsOpenCCMode', ccModes),
          controls[2],
        ],
        controls.sublist(3),
        [
          number('上间距', ly, 'topPadding', 0, 1000),
          number('下间距', ly, 'bottomPadding', 0, 1000),
          number('行距', ly, 'lineGap', 0, 500),
          choice('x对齐', ly, 'xAlign', {
            'left': '左',
            'center': '中',
            'right': '右',
          }),
          choice('y对齐', ly, 'yAlign', {
            'top': '上',
            'center': '中',
            'bottom': '下',
          }),
          number('容器右侧与封面距离', ly, 'rightGap', 0, 1000),
        ],
      ],
      optional: ly,
      enabledKey: 'enabled',
    );
  }

  Widget dividerPanel() => panel(
    '分隔线',
    [
      [
        number('分隔线粗', doc.lyrics, 'dividerThickness', .001, 100),
        for (final e in {
          'TopPadding': '上间距',
          'BottomPadding': '下间距',
          'LeftGap': '左间距',
          'RightGap': '右间距',
        }.entries)
          number('分隔线${e.value}', doc.lyrics, 'divider${e.key}', 0, 1000),
      ],
      [
        for (final e in {'Top': '顶部', 'Middle': '中间', 'Bottom': '底部'}.entries)
          textSetting(
            '${e.value} HEX',
            doc.lyrics,
            'divider${e.key}Hex',
            color: true,
          ),
      ],
      [
        for (final e in {'Top': '顶部', 'Middle': '中间', 'Bottom': '底部'}.entries)
          number(
            '${e.value}不透明度',
            doc.lyrics,
            'divider${e.key}Opacity',
            0,
            255,
          ),
      ],
    ],
    optional: doc.lyrics,
    enabledKey: 'dividerEnabled',
  );
  List<String> palette = [
    '#000000',
    '#121212',
    '#444444',
    '#cccccc',
    '#fafafa',
  ];
  int paletteRequest = 0;
  Future<void> updatePalette() async {
    final token = ++paletteRequest;
    final colors = await renderer.environment(doc, cover);
    if (mounted && token == paletteRequest) setState(() => palette = colors);
  }

  Widget colorPanel() {
    final custom = doc.data['customEnvironmentColorsEnabled'] == true;
    final colors =
        custom && (doc.data['customEnvironmentColors'] as List).length == 5
        ? (doc.data['customEnvironmentColors'] as List).cast<String>()
        : palette;
    return panel('颜色', [
      [
        setting('自定义环境颜色', custom ? '开' : '关', () async {
          if (custom) {
            doc.data['customEnvironmentColorsEnabled'] = false;
            doc.data['customEnvironmentColors'] = <String>[];
          } else {
            doc.data['customEnvironmentColorsEnabled'] = false;
            final current = await renderer.environment(doc, cover);
            doc.data['customEnvironmentColors'] = current;
            doc.data['customEnvironmentColorsEnabled'] = true;
          }
          changed();
        }),
        setting(
          '选择算法',
          paletteAlgorithms[doc.text('paletteAlgorithm')] ?? 'Celebi',
          chooseAlgorithm,
        ),
        if (custom) setting('选点', '', pickPoints),
      ],
      if (custom)
        [
          for (int i = 0; i < 5; i++)
            colorSwatch(
              colors[i],
              label: true,
              onTap: () async {
                final value = await pickCardColor(context, colors[i]);
                if (value != null) {
                  doc.data['customEnvironmentColors'][i] = value;
                  changed();
                }
              },
            ),
        ],
      [
        setting('自定义彩虹色', doc.text('rainbowMode') == 'custom' ? '开' : '关', () {
          doc.data['rainbowMode'] = doc.text('rainbowMode') == 'custom'
              ? 'auto'
              : 'custom';
          changed();
        }),
        if (doc.text('rainbowMode') == 'custom') ...[
          for (int i = 0; i < 5; i++)
            colorSwatch(
              colors[i],
              selected: doc.text('rainbowCustomSelection') == '$i',
              onTap: () {
                doc.data['rainbowCustomSelection'] = '$i';
                changed();
              },
            ),
          setting(
            '自定义',
            doc.text('rainbowCustomSelection') == 'hex' ? '✓' : '',
            () async {
              final value = await pickCardColor(
                context,
                doc.text('rainbowCustomHex'),
              );
              if (value != null) {
                doc.data['rainbowCustomHex'] = value;
                doc.data['rainbowCustomSelection'] = 'hex';
                changed();
              }
            },
          ),
        ],
      ],
      [
        choice('自动黑白色', doc.data, 'autoColorMode', {
          'auto': '',
          'black': '锁黑色',
          'white': '锁白色',
        }),
        number('取色封面边长', doc.data, 'rainbowSampleMaxSide', 1, 1000),
      ],
    ]);
  }

  static const hexNote =
      '留空=自动黑/白。支持#rrggbb（可省略#）；black/#black、white/#white，不区分大小写。彩虹色格式：rainbow%n或rainbow%n+hex，n为0–100、最多三位小数；r%为rainbow%的缩写，省略hex时使用当前自动黑/白。';
  Future<void> songJson() async {
    final fields = await showCardDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) =>
          SongJsonPage(fields: doc.fields, disabled: doc.disabledSongFields),
    );
    if (fields != null) {
      doc.data['fields'] = normalizeSongFields(fields);
      setState(() => doc = CardDocument(deepCopy(doc.data)));
      changed();
    }
  }

  Future<void> seedFair() async {
    final value = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => SeedFair(
          document: CardDocument(deepCopy(doc.data)),
          cover: cover,
          renderer: renderer,
        ),
      ),
    );
    if (value != null) {
      doc.data['seed'] = value;
      changed();
    }
  }

  Future<void> chooseAlgorithm() async {
    if (cover == null) {
      message('请先选择封面');
      return;
    }
    final pixels = await CoverPixels.read(cover!, 128);
    final results = <String, List<Color>>{};
    for (final key in paletteAlgorithms.keys) {
      results[key] = await pixels.palette(key);
    }
    if (!mounted) return;
    final value = await showCardDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('选择算法'),
        children: [
          for (final e in results.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, e.key),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Icon(
                      doc.text('paletteAlgorithm') == e.key
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                    ),
                  ),
                  SizedBox(width: 76, child: Text(paletteAlgorithms[e.key]!)),
                  const SizedBox(width: 8),
                  for (final color in e.value)
                    Expanded(child: Container(height: 26, color: color)),
                ],
              ),
            ),
        ],
      ),
    );
    if (value != null) {
      doc.data['paletteAlgorithm'] = value;
      changed();
    }
  }

  Future<void> pickPoints() async {
    if (cover == null) {
      message('请先选择封面');
      return;
    }
    final colors = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => PalettePointPage(
          image: cover!,
          initial: palette,
          algorithm: doc.text('paletteAlgorithm'),
        ),
      ),
    );
    if (colors != null) {
      doc.data['customEnvironmentColors'] = colors;
      doc.data['customEnvironmentColorsEnabled'] = true;
      changed();
    }
  }

  Widget weightSetting(Map<String, dynamic> s) => setting(
    '字重',
    '${s['weight'] ?? (s['bold'] == true
            ? 700
            : FontRepository.instance.lookup('${s['font']}') == null
            ? 400
            : effectiveWeight(FontRepository.instance.lookup('${s['font']}')!))}',
    () => pickWeight(s),
  );
  Future<bool> pickWeight(Map<String, dynamic> s) async {
    final repo = FontRepository.instance;
    await repo.init();
    final row = repo.lookup('${s['font'] ?? ''}');
    final group = repo.rows
        .where((r) => r['familyKey'] == row?['familyKey'])
        .toList();
    final axes = group
        .expand(fontAxes)
        .where((a) => a['tag'] == 'wght')
        .toList();
    double value = numv(
      s['weight'],
      s['bold'] == true
          ? 700
          : row == null
          ? 400
          : effectiveWeight(row).toDouble(),
    );
    final choices = group.map(effectiveWeight).toSet().toList()..sort();
    if (choices.isEmpty) {
      choices.addAll([100, 200, 300, 400, 500, 600, 700, 800, 900]);
    }
    final min = axes.isEmpty ? 1.0 : (axes.first['min'] as num).toDouble(),
        max = axes.isEmpty ? 1000.0 : (axes.first['max'] as num).toDouble();
    value = value.clamp(min, max);
    if (!mounted) return false;
    final result = await showCardDialog<int>(
      context: context,
      builder: (_) => WeightDialog(
        value: value,
        min: min,
        max: max,
        variable: axes.isNotEmpty,
        family: group,
        choices: choices,
      ),
    );
    if (result == null) return false;
    s['weight'] = result;
    s['bold'] = false;
    changed();
    return true;
  }

  Future<void> shapeSettings() async {
    await showCardDialog<void>(
      context: context,
      builder: (_) => CoverShapeDialog(document: doc, onChanged: changed),
    );
  }

  Future<void> runBenchmark() async {
    if (cover == null) {
      message('请先选择封面');
      return;
    }
    int count = 10, min = 20, max = 1000;
    List<String> results = [];
    bool running = false;
    await showCardDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: const Text('取色测试'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final key in ['测试点', '最小值', '最大值'])
                    TextFormField(
                      initialValue:
                          '${key == '测试点'
                              ? count
                              : key == '最小值'
                              ? min
                              : max}',
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: key),
                      onChanged: (s) {
                        final v = int.tryParse(s);
                        if (v == null) return;
                        if (key == '测试点') {
                          count = v;
                        } else if (key == '最小值') {
                          min = v;
                        } else {
                          max = v;
                        }
                      },
                    ),
                  for (final result in results) Text(result),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: running
                  ? null
                  : () async {
                      if (count < 1 ||
                          count > 100 ||
                          min < 1 ||
                          max < min ||
                          max > 4000) {
                        return;
                      }
                      update(() {
                        running = true;
                        results = [];
                      });
                      for (int i = 0; i < count; i++) {
                        final side = count == 1
                            ? min
                            : (min + (max - min) * i / (count - 1)).round();
                        final watch = Stopwatch()..start();
                        final copy = CardDocument(deepCopy(doc.data));
                        copy.data['rainbowSampleMaxSide'] = side;
                        await renderer.benchmarkRainbow(copy, cover!);
                        watch.stop();
                        if (!c.mounted) return;
                        update(
                          () => results.add(
                            '$side ${watch.elapsedMicroseconds / 1000}ms',
                          ),
                        );
                        await Future<void>.delayed(Duration.zero);
                      }
                      update(() => running = false);
                    },
              child: const Text('运行'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
  }

  bool receiving = false, receiveAgain = false;
  Future<void> incoming() async {
    receiveAgain = true;
    if (receiving) return;
    receiving = true;
    try {
      do {
        receiveAgain = false;
        while (mounted) {
          final value = await platform.invokeMapMethod<String, dynamic>(
            'takeIncoming',
          );
          if (value == null || !mounted) break;
          try {
            await applyIncoming(value);
          } catch (e) {
            message('导入失败：$e');
          } finally {
            if (value['path'] is String) {
              try {
                await platform.invokeMethod('releaseIncoming', {
                  'path': value['path'],
                });
              } catch (_) {}
            }
          }
        }
      } while (mounted && receiveAgain);
    } catch (e) {
      message('导入失败：$e');
    } finally {
      receiving = false;
    }
  }

  Future<void> applyIncoming(Map<String, dynamic> value) async {
    if (value['kind'] == 'error') throw FormatException('${value['text']}');
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).popUntil((route) => route.isFirst);
    if (value['kind'] != 'image' &&
        value['kind'] != 'audio' &&
        value['jsonFile'] != true) {
      try {
        decodeSongJson('${value['text']}');
      } catch (_) {
        // Receiving must not wait for this route to close: another share can
        // replace it through the home route while this page is still open.
        unawaited(searchSongInformation(sharedText: '${value['text']}'));
        return;
      }
    }
    final image = value['kind'] == 'image';
    if (image) {
      if (!await confirmCover('${value['path']}')) return;
    } else if (!await confirm('替换当前歌曲信息？')) {
      return;
    }
    if (value['kind'] == 'audio') {
      await importAudio('${value['path']}');
      return;
    }
    if (image) {
      final root = await platform.invokeMethod<String>('storageRoot');
      if (root == null) throw const FileSystemException('无法访问应用目录');
      final target = File(
        '$root/covers/shared-${DateTime.now().microsecondsSinceEpoch}.image',
      );
      await target.parent.create(recursive: true);
      await File('${value['path']}').copy(target.path);
      doc.data['coverPath'] = target.path;
      await _loadCover();
    } else {
      doc.data['fields'] = normalizeSongFields(
        songFieldsFromText('${value['text']}'),
      );
    }
    setState(() => doc = CardDocument(deepCopy(doc.data)));
    changed();
  }

  Widget colorSwatch(
    String value, {
    bool label = false,
    bool selected = false,
    required VoidCallback onTap,
  }) {
    final c = Color(
      0xff000000 | int.parse(value.replaceAll('#', ''), radix: 16),
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: label ? 100 : 40,
        height: 32,
        margin: const EdgeInsets.all(3),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? const Color(0xffe69129) : const Color(0xffaaa29b),
            width: selected ? 3 : 1,
          ),
          boxShadow: selected
              ? const [BoxShadow(color: Color(0x66e69129), blurRadius: 3)]
              : null,
        ),
        child: label
            ? Text(
                value.toLowerCase(),
                style: TextStyle(color: inverseColor(c)),
              )
            : null,
      ),
    );
  }

  Widget settingsPage() => Column(
    children: [
      normalSection('显示', [
        setting(
          '文本对齐模式',
          const {'top': '顶部', 'center': '中', 'bottom': '底部'}[doc.text(
                'textAlignMode',
              )] ??
              '中',
          () {
            const modes = ['top', 'center', 'bottom'];
            doc.data['textAlignMode'] =
                modes[(modes.indexOf(doc.text('textAlignMode')) + 1) %
                    modes.length];
            changed();
          },
          valueIcon: const {
            'top': Icons.vertical_align_top,
            'center': Icons.vertical_align_center,
            'bottom': Icons.vertical_align_bottom,
          }[doc.text('textAlignMode')],
        ),
        toggle('启用monet配色', doc.data, 'monet'),
      ]),
      normalSection('字体', [
        ListTile(
          title: const Text('字体管理器'),
          onTap: manageFonts,
          trailing: const Icon(Icons.chevron_right),
        ),
        ListTile(
          title: const Text('修改显示字体'),
          subtitle: Text(
            FontRepository.instance.name(doc.text('displayFontName')),
          ),
          onTap: () async {
            final id = await Navigator.push<String>(
              context,
              MaterialPageRoute(
                builder: (_) => const FontLibraryPage(selecting: true),
              ),
            );
            if (id != null) {
              doc.data['displayFontName'] = id;
              await _loadUiFont();
              changed();
            }
          },
        ),
        ListTile(
          title: const Text('恢复系统界面字体'),
          onTap: () {
            doc.data['displayFontName'] = '';
            _loadUiFont();
            changed();
          },
        ),
      ]),
      normalSection('图片', [
        ListTile(
          title: const Text('图片压缩'),
          subtitle: Text(ImageExportOptions.fromMap(doc.data).label),
          onTap: imageCompression,
        ),
        ListTile(
          title: const Text('保存图片文件夹'),
          subtitle: Text(
            doc.text('imageFolder').isEmpty
                ? '首次保存时选择'
                : doc.text('imageFolder'),
          ),
          onTap: chooseImageFolder,
          trailing: const Icon(Icons.folder_outlined),
        ),
        ListTile(
          title: const Text('保存图片文件名称'),
          subtitle: Text(doc.text('imageFilename')),
          onTap: () async {
            final value = await showCardDialog<String>(
              context: context,
              builder: (_) => FilenameDialog(document: doc),
            );
            if (value != null) {
              doc.data['imageFilename'] = value;
              await _save();
              setState(() {});
            }
          },
        ),
      ]),
      normalSection('配置', [
        ListTile(title: const Text('导入配置'), onTap: importConfig),
        ListTile(title: const Text('导出配置'), onTap: saveConfig),
        ListTile(title: const Text('选择配置'), onTap: library),
        ListTile(
          title: const Text('恢复默认配置'),
          onTap: () async {
            if (await confirm('恢复默认配置？')) {
              final fresh = CardDocument.fresh();
              for (final k in [
                'fields',
                'coverPath',
                'imageFolder',
                'previewPinned',
                'imageFilename',
                'imageFormat',
                'jpegQuality',
                'fontPreferences',
                'coverSearchMinScore',
                'coverSearchPreviewSize',
                'coverSearchDownloadSize',
                'coverSearch_163',
                'coverSearch_apple',
                'coverSearch_appleweb',
                'coverSearchRegion',
                ...doc.data.keys.where((k) => k.startsWith('songSearch')),
              ]) {
                fresh.data[k] = doc.data[k];
              }
              doc = fresh;
              changed();
            }
          },
        ),
      ]),
      normalSection('', [
        ListTile(
          title: const Text('关于'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AboutPage()),
          ),
        ),
      ]),
    ],
  );
  Future<void> imageCompression() async {
    final selected = await showCardDialog<ImageExportOptions>(
      context: context,
      builder: (_) =>
          ImageCompressionDialog(initial: ImageExportOptions.fromMap(doc.data)),
    );
    if (selected == null || !mounted) return;
    setState(() {
      doc.data.addAll(selected.toMap());
    });
    await _save();
  }

  Future<void> largePreview() async {
    if (rendered == null) return;
    final image = rendered!.image.clone();
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => CardImageViewer(image: image)),
      );
    } finally {
      image.dispose();
    }
  }

  Widget preview() => Container(
    color: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: Column(
      children: [
        SizedBox(
          height: 32,
          child: Row(
            children: [
              Text(
                rendered == null
                    ? ''
                    : '${rendered!.image.width}×${rendered!.image.height} ${rendered!.milliseconds}ms',
              ),
              const Spacer(),
              IconButton(
                padding: EdgeInsets.zero,
                tooltip: '固定预览',
                onPressed: () {
                  setState(() => pinned = !pinned);
                  doc.data['previewPinned'] = pinned;
                  _save();
                },
                icon: Icon(
                  pinned ? Icons.push_pin : Icons.push_pin_outlined,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 150,
          child: rendered == null
              ? const Center(child: Text('正在生成预览…'))
              : InlinePreview(
                  key: const ValueKey('preview-image'),
                  image: rendered!.image,
                  onTap: largePreview,
                ),
        ),
        if (error != null)
          Text(error!, style: const TextStyle(color: Colors.red)),
        SizedBox(
          height: 32,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: TextButtonTheme(
              data: TextButtonThemeData(
                style:
                    (TextButtonTheme.of(context).style ?? const ButtonStyle())
                        .copyWith(
                          backgroundColor: const WidgetStatePropertyAll(
                            Colors.transparent,
                          ),
                          elevation: const WidgetStatePropertyAll(0),
                          shadowColor: const WidgetStatePropertyAll(
                            Colors.transparent,
                          ),
                          textStyle: WidgetStatePropertyAll(
                            TextStyle(
                              fontSize: 13,
                              fontFamily: uiFamily ?? 'Roboto',
                            ),
                          ),
                        ),
              ),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () async {
                      final v = await editText('Input', doc.text('seed'));
                      if (v != null) {
                        doc.data['seed'] = v.isEmpty ? newSeed() : v;
                        changed();
                      }
                    },
                    child: const Text('Input'),
                  ),
                  TextButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: doc.text('seed')));
                      message('种子已复制');
                    },
                    child: Text('Copy seed: ${doc.text('seed')}'),
                  ),
                  if (doc.text('backgroundStyle') == 'fusion')
                    TextButton(onPressed: seedFair, child: const Text('博览会')),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: () {
                      doc.data['seed'] = newSeed();
                      changed();
                    },
                    icon: const Icon(Icons.refresh, size: 19),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
  Future<void> editCell(String row, String key) async {
    final s = doc.styles[row];
    if (key == 'font') {
      await pickFont(s);
      return;
    }
    if (key == 'weight') {
      await pickWeight(s);
      return;
    }
    if (key == 'bold' || key == 'italic') {
      s[key] = s[key] != true;
      changed();
      return;
    }
    final v = await editText(
      '${styleLabels[row]} $key',
      '${s[key] ?? ''}',
      lines: key == 'text' ? 3 : 1,
      hexInput: key == 'colorHex',
      numeric: key != 'text' && key != 'colorHex',
      note: key == 'colorHex' ? hexNote : null,
      validate: (v) => key == 'text'
          ? null
          : key == 'colorHex'
          ? (validColor(v) ? null : '颜色格式无效')
          : key == 'letterSpacing' && v.isEmpty
          ? null
          : batchNumberError(key, v),
    );
    if (v == null) return;
    s[key] =
        ['text', 'colorHex'].contains(key) ||
            key == 'letterSpacing' && v.isEmpty
        ? v
        : numv(v);
    changed();
  }

  Widget textTable() {
    const keys = {
      'text': '内容',
      'size': '字号',
      'font': '字体',
      'weight': '字重',
      'italic': '斜体',
      'colorHex': 'HEX',
      'opacity': '不透明度',
      'blurStrength': '模糊强度',
      'blurOpacity': '模糊不透明度',
      'letterSpacing': '字间距',
    };
    String cell(String row, String key) {
      final value = key == 'weight'
          ? (doc.styles[row]['weight'] ??
                (doc.styles[row]['bold'] == true ? 700 : 400))
          : doc.styles[row][key];
      return key == 'font'
          ? FontRepository.instance.name('$value')
          : key == 'bold' || key == 'italic'
          ? (value == true ? '开' : '关')
          : '$value';
    }

    return CompactTextTable(
      columns: {'element': '元素', ...keys},
      rows: [
        for (final row in styleLabels.keys)
          [styleLabels[row]!, for (final k in keys.keys) cell(row, k)],
      ],
      family: uiFamily ?? 'Roboto',
      onHeader: (key) {
        if (key != 'element') columnEdit(key);
      },
      onCell: (r, key) {
        final row = styleLabels.keys.elementAt(r);
        if (key == 'element') {
          elementPage(row);
        } else {
          editCell(row, key);
        }
      },
    );
  }

  List<Widget> pageChildren(Widget page) =>
      ((page as ListView).childrenDelegate as SliverChildListDelegate).children;
  Widget workbench() => Column(
    children: [
      backgroundPanel(),
      colorPanel(),
      textTable(),
      lyricsPanel(),
      if (doc.lyrics['enabled'] == true) dividerPanel(),
      const SizedBox(height: 20),
    ],
  );
  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        listTileTheme: Theme.of(context).listTileTheme.copyWith(
          titleTextStyle: Theme.of(context).listTileTheme.titleTextStyle
              ?.copyWith(fontFamily: uiFamily ?? 'Roboto'),
          subtitleTextStyle: Theme.of(context).listTileTheme.subtitleTextStyle
              ?.copyWith(fontFamily: uiFamily ?? 'Roboto'),
        ),
        textTheme: Theme.of(context).textTheme
            .apply(fontFamily: uiFamily ?? 'Roboto'),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            textStyle: TextStyle(
              fontSize: 13,
              fontFamily: uiFamily ?? 'Roboto',
            ),
            minimumSize: const Size(34, 32),
            backgroundColor: controlColor(context),
            elevation: 0,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
        ),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 42,
          title: const Text('MusicCardX', style: TextStyle(fontSize: 18)),
          actions: [
            IconButton(
              tooltip: '分享',
              onPressed: () => export('shareImage'),
              icon: const Icon(Icons.open_in_new),
            ),
            IconButton(
              tooltip: '复制图片',
              onPressed: () => export('copyImage'),
              icon: const Icon(Icons.content_copy),
            ),
            IconButton(
              tooltip: '保存图片',
              onPressed: () => export('saveImage'),
              icon: const Icon(Icons.save_outlined),
            ),
          ],
        ),
        body: Stack(
          children: [
            Column(
              children: [
                if (pinned && tab != 2) preview(),
                Expanded(
                  child: SingleChildScrollView(
                    key: PageStorageKey('page-$tab'),
                    child: Column(
                      children: [
                        if (!pinned && tab != 2) preview(),
                        if (tab == 0)
                          inputPage()
                        else if (tab == 1)
                          workbench()
                        else
                          settingsPage(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (_working)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black38,
                  child: Center(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: SizedBox(
                          width: 240,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_workLabel),
                              const SizedBox(height: 16),
                              LinearProgressIndicator(value: _workProgress),
                              if (_workProgress != null)
                                Text('${(_workProgress! * 100).round()}%'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: SizedBox(
            key: const ValueKey('bottom-tabs'),
            height: kBottomNavigationBarHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final e in {0: '输入', 1: '工作台', 2: '设置'}.entries)
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        FocusManager.instance.primaryFocus?.unfocus();
                        commitInput();
                        setState(() => tab = e.key);
                      },
                      style: TextButton.styleFrom(
                        elevation: 0,
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        foregroundColor: tab == e.key
                            ? Theme.of(context).colorScheme.primary
                            : Colors.black54,
                        textStyle: TextStyle(
                          fontSize: 13,
                          fontFamily: uiFamily ?? 'Roboto',
                          fontWeight: tab == e.key
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                      child: Text(e.value),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
