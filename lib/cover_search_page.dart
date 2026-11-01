import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';

import 'cover_search.dart';
import 'dialog_buttons.dart';
import 'model.dart';

class CoverAsset {
  final Uint8List bytes;
  final int width, height;
  const CoverAsset(this.bytes, this.width, this.height);
  static Future<CoverAsset> inspect(Uint8List bytes, {int maxSide = 0}) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final w = descriptor.width, h = descriptor.height;
      if (w <= 0 || h <= 0 || w * h > 32000000 || w > 16384 || h > 16384) {
        throw const FormatException('封面超过可处理尺寸');
      }
      return CoverAsset(bytes, w, h);
    } finally {
      descriptor?.dispose();
      buffer.dispose();
    }
  }
}

/// A bounded memory cache for the current search page, never a permanent download folder.
class CoverLoader {
  final CoverSearchClient client;
  final cache = <String, CoverAsset>{};
  final Map<String, Future<CoverAsset>> pending = {};
  int bytes = 0, active = 0;
  CoverLoader(this.client);
  void clear() {
    cache.clear();
    pending.clear();
    bytes = 0;
  }

  Future<CoverAsset> load(
    CoverCandidate candidate,
    int size,
    CoverCancel cancel, {
    void Function(int, int)? progress,
    bool fresh = false,
  }) async {
    cancel.check();
    final key = '${candidate.source}:${candidate.id}:$size';
    if (!fresh && cache.containsKey(key)) {
      final a = cache.remove(key)!;
      cache[key] = a;
      return a;
    }
    if (!fresh && pending.containsKey(key)) return pending[key]!;
    Future<CoverAsset> fetch() async {
      while (active >= 2) {
        await cancel.delay(const Duration(milliseconds: 50));
      }
      cancel.check();
      active++;
      try {
        final a = await CoverAsset.inspect(
          await client.artwork(candidate, size, cancel, progress: progress),
          maxSide: size,
        );
        cancel.check();
        if (a.bytes.length <= 80 * 1024 * 1024) {
          final old = cache.remove(key);
          if (old != null) bytes -= old.bytes.length;
          cache[key] = a;
          bytes += a.bytes.length;
          while (bytes > 80 * 1024 * 1024) {
            bytes -= cache.remove(cache.keys.first)!.bytes.length;
          }
        }
        return a;
      } finally {
        active--;
      }
    }

    final future = fetch();
    pending[key] = future;
    try {
      return await future;
    } finally {
      if (identical(pending[key], future)) pending.remove(key);
    }
  }
}

int coverGridColumns(double width) => (width / 180).floor().clamp(1, 6);

class CoverSearchPage extends StatefulWidget {
  final CardDocument document;
  final Future<void> Function() onSettings;
  final Future<bool> Function(CoverAsset) onSave;
  final CoverSearchClient? client;
  const CoverSearchPage({
    super.key,
    required this.document,
    required this.onSettings,
    required this.onSave,
    this.client,
  });
  @override
  State<CoverSearchPage> createState() => _CoverSearchPageState();
}

class _CoverSearchPageState extends State<CoverSearchPage> {
  late final client = widget.client ?? CoverSearchClient();
  late final loader = CoverLoader(client);
  late final title = TextEditingController(
    text: '${widget.document.fields['title'] ?? ''}',
  );
  late final artist = TextEditingController(
    text: '${widget.document.fields['artist'] ?? ''}',
  );
  late final album = TextEditingController(
    text: '${widget.document.fields['album'] ?? ''}',
  );
  late final preview = TextEditingController(
    text: '${widget.document.data['coverSearchPreviewSize']}',
  );
  late final threshold = TextEditingController(
    text: '${widget.document.data['coverSearchMinScore']}',
  );
  late final download = TextEditingController(
    text: '${widget.document.data['coverSearchDownloadSize']}',
  );
  final form = GlobalKey<FormState>();
  CoverCancel searchCancel = CoverCancel(), imageCancel = CoverCancel();
  List<CoverCandidate> candidates = [];
  Map<String, String> status = {};
  bool searching = false;
  bool searched = false;
  String? error;
  Map<String, dynamic> get data => widget.document.data;
  Set<String> get enabled => {
    for (final s in CoverSearchClient.sources.keys)
      if (data['coverSearch_$s'] == true) s,
  };
  @override
  void dispose() {
    searchCancel.cancel();
    imageCancel.cancel();
    client.close();
    loader.clear();
    for (final c in [title, artist, album, preview, download, threshold]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> persist() async {
    try {
      await widget.onSettings();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(milliseconds: 1500),
            content: Text('设置保存失败：$e'),
          ),
        );
      }
    }
  }

  bool sizes() {
    if (!mounted ||
        form.currentState == null ||
        !form.currentState!.validate()) {
      return false;
    }
    data['coverSearchMinScore'] = double.parse(threshold.text);
    data['coverSearchPreviewSize'] = int.parse(preview.text);
    data['coverSearchDownloadSize'] = int.parse(download.text);
    return true;
  }

  Future<void> search({Set<String>? only}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!sizes()) return;
    searchCancel.cancel();
    searchCancel = CoverCancel();
    if (only == null) {
      imageCancel.cancel();
      imageCancel = CoverCancel();
      loader.clear();
    }
    final retained = only == null
        ? <CoverCandidate>[]
        : candidates.where((c) => !only.contains(c.source)).toList();
    final retainedStatus =
        only == null ? <String, String>{} : Map<String, String>.from(status)
          ..removeWhere((key, _) => only?.contains(key) == true);
    final token = searchCancel;
    setState(() {
      searching = true;
      searched = true;
      error = null;
      candidates = retained;
      status = retainedStatus;
    });
    await persist();
    if (!mounted || token.cancelled) return;
    try {
      await client.search(
        title: title.text.trim(),
        artist: artist.text.trim(),
        album: album.text.trim(),
        enabled: only ?? enabled,
        region: '${data['coverSearchRegion']}',
        cancel: token,
        onUpdate: (rows, states) {
          if (mounted && !token.cancelled) {
            setState(() {
              candidates = [...retained, ...rows]
                ..sort((a, b) => b.score.compareTo(a.score));
              status = {...retainedStatus, ...states};
            });
          }
        },
      );
    } on CoverCancelled {
      /* A superseded search must not change the current result. */
    } catch (e) {
      if (mounted && !token.cancelled) setState(() => error = conciseError(e));
    } finally {
      if (mounted && !token.cancelled) setState(() => searching = false);
    }
  }

  Future<void> region() async {
    final controller = TextEditingController(
      text: '${data['coverSearchRegion']}',
    );
    final result = await showCardDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('区域代号'),
        content: TextField(
          controller: controller,
          maxLength: 2,
          decoration: const InputDecoration(hintText: 'ISO两字母代号，如cn、us、jp、gb'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              if (RegExp(r'^[a-zA-Z]{2}$').hasMatch(controller.text.trim())) {
                Navigator.pop(ctx, controller.text.trim().toLowerCase());
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    Future.delayed(const Duration(milliseconds: 400), controller.dispose);
    if (result != null && mounted) {
      setState(() => data['coverSearchRegion'] = result);
      await persist();
    }
  }

  Widget dimension(
    String label,
    TextEditingController controller,
    String key,
  ) => Expanded(
    child: Focus(
      onFocusChange: (focused) {
        if (!focused && sizes()) {
          setState(() {});
          persist();
        }
      },
      child: TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label, helperText: '0为最大'),
        onTap: () => controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: controller.text.length,
        ),
        validator: (s) {
          final v = int.tryParse(s ?? '');
          return v == null || v < 0 || v > 10000 ? '请输入0—10000' : null;
        },
      ),
    ),
  );
  Future<void> open(CoverCandidate candidate) async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!sizes()) return;
    await persist();
    if (!mounted) return;
    final result = await Navigator.push<CoverAsset>(
      context,
      MaterialPageRoute(
        builder: (_) => CoverDetailPage(
          candidate: candidate,
          loader: loader,
          previewSize: data['coverSearchPreviewSize'] as int,
          downloadSize: data['coverSearchDownloadSize'] as int,
          onSave: widget.onSave,
        ),
      ),
    );
    if (result != null && mounted) Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) => PopScope<CoverAsset>(
    onPopInvokedWithResult: (didPop, result) {
      if (didPop && sizes()) persist();
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('搜索封面'),
        actions: [
          IconButton(
            tooltip: 'Apple地区',
            onPressed: region,
            icon: const Icon(Icons.public),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, bounds) => CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: form,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: title,
                        decoration: const InputDecoration(labelText: '标题'),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: artist,
                        decoration: const InputDecoration(labelText: '艺术家'),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: album,
                        decoration: const InputDecoration(labelText: '专辑'),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          dimension(
                            '预览封面尺寸',
                            preview,
                            'coverSearchPreviewSize',
                          ),
                          const SizedBox(width: 16),
                          dimension(
                            '下载封面尺寸',
                            download,
                            'coverSearchDownloadSize',
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            const Text('分数低于'),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 70,
                              child: TextFormField(
                                controller: threshold,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                validator: (s) {
                                  final n = double.tryParse(s ?? '');
                                  return n == null ||
                                          !n.isFinite ||
                                          n < 0 ||
                                          n > 100
                                      ? '0—100'
                                      : null;
                                },
                                onChanged: (_) {
                                  if (sizes()) {
                                    setState(() {});
                                    persist();
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Flexible(child: Text('时不自动加载图片')),
                          ],
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          for (final s in CoverSearchClient.sources.entries)
                            FilterChip(
                              label: Text(s.value),
                              selected: data['coverSearch_${s.key}'] == true,
                              onSelected: (v) {
                                setState(
                                  () => data['coverSearch_${s.key}'] = v,
                                );
                                persist();
                              },
                            ),
                          TextButton(
                            onPressed: search,
                            child: const Text('搜索'),
                          ),
                          if (searching)
                            TextButton(
                              onPressed: () {
                                searchCancel.cancel();
                                setState(() => searching = false);
                              },
                              child: const Text('取消'),
                            ),
                        ],
                      ),
                      if (searching) const LinearProgressIndicator(),
                      for (final s in status.entries)
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${CoverSearchClient.sources[s.key]} ${s.value}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: s.value.startsWith('失败')
                                      ? Theme.of(context).colorScheme.error
                                      : null,
                                ),
                              ),
                            ),
                            if (s.value.startsWith('失败') && !searching)
                              TextButton(
                                onPressed: () => search(only: {s.key}),
                                child: const Text('重试'),
                              ),
                          ],
                        ),
                      if (error != null)
                        Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      if (!searching && error == null && candidates.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(searched ? '未找到匹配封面' : '填写歌曲信息后搜索'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: coverGridColumns(bounds.maxWidth - 24),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  mainAxisExtent:
                      (bounds.maxWidth -
                              24 -
                              8 *
                                  (coverGridColumns(bounds.maxWidth - 24) -
                                      1)) /
                          coverGridColumns(bounds.maxWidth - 24) +
                      112 * MediaQuery.textScalerOf(context).scale(13) / 13,
                ),
                itemCount: candidates.length,
                itemBuilder: (context, index) => _CoverTile(
                  key: ValueKey(
                    '${candidates[index].source}:${candidates[index].id}:${data['coverSearchPreviewSize']}',
                  ),
                  autoLoad:
                      candidates[index].score >=
                      numv(data['coverSearchMinScore'], 20),
                  candidate: candidates[index],
                  loader: loader,
                  cancel: imageCancel,
                  size: data['coverSearchPreviewSize'] as int,
                  onTap: () => open(candidates[index]),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CoverTile extends StatefulWidget {
  final bool autoLoad;
  final CoverCandidate candidate;
  final CoverLoader loader;
  final CoverCancel cancel;
  final int size;
  final VoidCallback onTap;
  const _CoverTile({
    super.key,
    required this.autoLoad,
    required this.candidate,
    required this.loader,
    required this.cancel,
    required this.size,
    required this.onTap,
  });
  @override
  State<_CoverTile> createState() => _CoverTileState();
}

class _CoverTileState extends State<_CoverTile> {
  late Future<CoverAsset>? future = widget.autoLoad
      ? widget.loader.load(widget.candidate, widget.size, widget.cancel)
      : null;
  @override
  void didUpdateWidget(covariant _CoverTile old) {
    super.didUpdateWidget(old);
    if (widget.autoLoad && future == null) {
      future = widget.loader.load(widget.candidate, widget.size, widget.cancel);
    }
  }

  void startLoad({bool fresh = false}) {
    final task = widget.loader.load(
      widget.candidate,
      widget.size,
      widget.cancel,
      fresh: fresh,
    );
    setState(() {
      future = task;
    });
  }

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: FutureBuilder<CoverAsset>(
                future: future,
                builder: (context, snapshot) {
                  if (future == null) {
                    return Center(
                      child: IconButton(
                        tooltip: '下载预览图',
                        onPressed: () => startLoad(fresh: false),
                        icon: const Icon(Icons.download_outlined),
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: IconButton(
                        tooltip: '重新加载封面',
                        onPressed: () => startLoad(fresh: true),
                        icon: const Icon(Icons.refresh),
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  return Image.memory(
                    snapshot.data!.bytes,
                    fit: BoxFit.contain,
                    cacheWidth: 384,
                    filterQuality: FilterQuality.high,
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.candidate.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            Text(
              widget.candidate.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
            Text(
              widget.candidate.album,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
            const Spacer(),
            Text(
              '${widget.candidate.sourceName} ${widget.candidate.score.toStringAsFixed(1)}分',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}

class CoverDetailPage extends StatefulWidget {
  final CoverCandidate candidate;
  final CoverLoader loader;
  final int previewSize, downloadSize;
  final bool askDownloadSize;
  final Future<bool> Function(CoverAsset) onSave;
  const CoverDetailPage({
    super.key,
    required this.candidate,
    required this.loader,
    required this.previewSize,
    required this.downloadSize,
    this.askDownloadSize = false,
    required this.onSave,
  });
  @override
  State<CoverDetailPage> createState() => _CoverDetailPageState();
}

class _CoverDetailPageState extends State<CoverDetailPage> {
  final cancel = CoverCancel();
  CoverAsset? current;
  ui.Image? displayed;
  bool working = true;
  bool downloaded = false;
  double? progress;
  String? error;
  String stage = '加载预览';
  @override
  void initState() {
    super.initState();
    load(widget.previewSize, initial: true);
  }

  @override
  void dispose() {
    cancel.cancel();
    displayed?.dispose();
    super.dispose();
  }

  void notify(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 1500),
          content: Text(text),
        ),
      );
    }
  }

  Future<bool> load(int size, {bool initial = false}) async {
    setState(() {
      working = true;
      error = null;
      progress = null;
      stage = initial ? '加载预览' : '下载封面';
    });
    try {
      final asset = await widget.loader.load(
        widget.candidate,
        size,
        cancel,
        fresh: !initial,
        progress: (n, total) {
          if (mounted) {
            setState(
              () => progress = total > 0 ? (n / total).clamp(0, 1) : null,
            );
          }
        },
      );
      final codec = await ui.instantiateImageCodec(
        asset.bytes,
        targetWidth: asset.width > 2048 ? 2048 : asset.width,
        allowUpscaling: false,
      );
      ui.Image image;
      try {
        image = (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
      if (!mounted || cancel.cancelled) {
        image.dispose();
        return false;
      }
      final old = displayed;
      setState(() {
        current = asset;
        downloaded = !initial;
        displayed = image;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        old?.dispose();
      });
      return true;
    } on CoverCancelled {
      return false;
    } catch (e) {
      if (mounted) setState(() => error = conciseError(e));
      return false;
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<int?> requestSize() async {
    if (!widget.askDownloadSize) return widget.downloadSize;
    final controller = TextEditingController(text: '1000');
    final size = await showCardDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('下载封面尺寸'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(helperText: '0为最大'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final n = int.tryParse(controller.text);
              if (n != null && n >= 0 && n <= 10000) {
                Navigator.pop(ctx, n);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    Future.delayed(const Duration(milliseconds: 400), controller.dispose);
    return size;
  }

  Future<void> downloadCover() async {
    final size = await requestSize();
    if (size != null && mounted) {
      await load(size);
    }
  }

  Future<void> useCover() async {
    if (working || current == null) return;
    if (widget.askDownloadSize) {
      final size = await requestSize();
      if (size == null || !mounted || !await load(size)) return;
    } else if (!downloaded && !await load(widget.downloadSize)) {
      return;
    }
    if (mounted && current != null) Navigator.pop(context, current);
  }

  Future<void> save() async {
    if (current == null || working) return;
    setState(() {
      working = true;
      progress = null;
      stage = '保存封面';
    });
    try {
      if (await widget.onSave(current!)) notify('封面已保存');
    } catch (e) {
      notify(conciseError(e));
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        current == null ? '封面' : '${current!.width}×${current!.height}',
      ),
      actions: [
        IconButton(
          tooltip: '下载大图',
          onPressed: working ? null : downloadCover,
          icon: const Icon(Icons.download_outlined),
        ),
        IconButton(
          tooltip: '保存当前封面',
          onPressed: working || current == null ? null : save,
          icon: const Icon(Icons.save_outlined),
        ),
        IconButton(
          tooltip: '使用此封面',
          onPressed: working || current == null ? null : useCover,
          icon: const Icon(Icons.check),
        ),
      ],
    ),
    body: Column(
      children: [
        if (working) ...[
          LinearProgressIndicator(value: progress),
          Text(
            '$stage${progress == null ? '' : ' ${(progress! * 100).round()}%'}',
          ),
        ],
        Expanded(
          child: displayed == null
              ? Center(child: Text(error ?? '加载封面'))
              : PhotoView.customChild(
                  key: ValueKey(displayed),
                  childSize: Size(
                    displayed!.width.toDouble(),
                    displayed!.height.toDouble(),
                  ),
                  minScale: PhotoViewComputedScale.contained,
                  maxScale: PhotoViewComputedScale.contained * 8,
                  backgroundDecoration: const BoxDecoration(
                    color: Colors.white,
                  ),
                  child: RawImage(
                    image: displayed,
                    filterQuality: FilterQuality.high,
                  ),
                ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 180),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.candidate.title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(widget.candidate.artist),
                  Text(widget.candidate.album),
                  Text(
                    '${widget.candidate.sourceName} ${widget.candidate.score.toStringAsFixed(1)}分${current == null ? '' : '  ${(current!.bytes.length / 1024).round()}KB'}',
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
