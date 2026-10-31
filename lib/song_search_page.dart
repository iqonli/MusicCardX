import 'dart:async';

import 'package:flutter/material.dart';

import 'cover_search.dart';
import 'dialog_buttons.dart';
import 'model.dart';
import 'song_search.dart';

class SongSearchPage extends StatefulWidget {
  final CardDocument document;
  final Future<void> Function() onSettings;
  final SongSearchClient? client;
  const SongSearchPage({
    super.key,
    required this.document,
    required this.onSettings,
    this.client,
  });
  @override
  State<SongSearchPage> createState() => _SongSearchPageState();
}

class _SongSearchPageState extends State<SongSearchPage> {
  late final client = widget.client ?? SongSearchClient();
  late final original = Map<String, dynamic>.from(widget.document.fields);
  late final title = TextEditingController(text: '${original['title'] ?? ''}');
  late final artist = TextEditingController(
    text: '${original['artist'] ?? ''}',
  );
  late final album = TextEditingController(text: '${original['album'] ?? ''}');
  final form = GlobalKey<FormState>();
  final candidates = <String, SongCandidate>{};
  final pending = <String>{};
  final statuses = <String, String>{};
  CoverCancel? cancel;
  bool busy = false;
  String region = 'cn';
  late final enabled = <String, bool>{
    for (final s in SongSearchClient.sources.keys)
      s: widget.document.data['songSearch_$s'] == true,
  };

  @override
  void initState() {
    super.initState();
    region = '${widget.document.data['songSearchRegion'] ?? 'cn'}';
  }

  @override
  void dispose() {
    cancel?.cancel();
    client.close();
    title.dispose();
    artist.dispose();
    album.dispose();
    super.dispose();
  }

  void message(String text) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), duration: const Duration(milliseconds: 1500)),
  );

  Future<void> search() async {
    if (!form.currentState!.validate()) return;
    final sources = enabled.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();
    if (sources.isEmpty) {
      message('请选择搜索源');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    cancel?.cancel();
    final token = CoverCancel();
    cancel = token;
    final t = title.text.trim(),
        a = artist.text.trim(),
        b = album.text.trim(),
        r = region;
    bool current() => mounted && identical(cancel, token) && !token.cancelled;
    setState(() {
      busy = true;
      selected.clear();
      candidates.clear();
      pending.clear();
      statuses.clear();
      for (final s in sources) {
        statuses[s] = '搜索中';
      }
    });
    Future<void> source(String s) async {
      try {
        final songs = await client.searchSource(s, t, a, b, r, token);
        if (!current()) return;
        setState(() {
          statuses[s] = songs.isEmpty ? '没有结果' : '${songs.length}个候选，补全信息中';
          for (final c in songs) {
            final item = SongCandidate(c, {
              'title': c.title,
              'artist': c.artist,
              'album': c.album,
              ...c.metadata,
            });
            candidates[item.key] = item;
            pending.add(item.key);
          }
        });
        // Two detail requests per provider, never an unbounded fan-out.
        var next = 0;
        Future<void> worker() async {
          while (next < songs.length && current()) {
            final song = songs[next++];
            final result = await client.details(song, r, token);
            if (!current()) return;
            setState(() {
              candidates[result.key] = result;
              pending.remove(result.key);
            });
          }
        }

        await Future.wait([worker(), worker()]);
        if (current()) setState(() => statuses[s] = '${songs.length}个候选');
      } on CoverCancelled {
        /* Leaving or starting another search owns cancellation. */
      } catch (_) {
        if (current()) setState(() => statuses[s] = '搜索失败，请重试');
      }
    }

    await Future.wait(sources.map(source));
    if (current()) setState(() => busy = false);
  }

  final selected = <String, String>{};
  Future<void> editRegion() async {
    final controller = TextEditingController(text: region);
    final value = await showCardDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('区域代号'),
        content: TextField(
          controller: controller,
          maxLength: 2,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'ISO两字母代号，如cn、us、jp、gb'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final v = controller.text.trim().toLowerCase();
              if (RegExp(r'^[a-z]{2}$').hasMatch(v)) {
                Navigator.pop(ctx, v);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    Future.delayed(const Duration(milliseconds: 400), controller.dispose);
    if (value != null && mounted) {
      setState(() => region = value);
      widget.document.data['songSearchRegion'] = value;
      await widget.onSettings();
    }
  }

  void applySelection() {
    final fields = Map<String, dynamic>.from(original);
    for (final e in selected.entries) {
      if (e.value.isEmpty) {
        fields.remove(e.key);
      } else {
        fields[e.key] = e.value;
      }
    }
    Navigator.pop(context, fields);
  }

  Widget fieldFlow(String key, String label) {
    final old = '${original[key] ?? ''}';
    final currentAlbum = selected['album'] ?? '${original['album'] ?? ''}';
    final options = rankSongField(
      candidatesForSongField(candidates.values, key, currentAlbum),
      key,
    );
    final bestMatches = options.isNotEmpty && options.first.value == old;
    Widget bubble(
      String value,
      String text,
      double score, {
      bool keep = false,
    }) {
      final active = keep ? !selected.containsKey(key) : selected[key] == value;
      final color = Theme.of(context).colorScheme.primary;
      final background = Color.lerp(
        Colors.white,
        color,
        .08 + .52 * score / 100,
      )!;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(text),
          selected: active,
          showCheckmark: true,
          backgroundColor: background,
          selectedColor: background,
          labelStyle: TextStyle(
            color:
                ThemeData.estimateBrightnessForColor(background) ==
                    Brightness.dark
                ? Colors.white
                : Colors.black,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
          ),
          side: active ? BorderSide(color: color, width: 2) : BorderSide.none,
          onSelected: (_) => setState(() {
            if (key == 'album') {
              for (final dependent in albumDependentFields) {
                selected.remove(dependent);
              }
            }
            if (keep || value == old) {
              selected.remove(key);
            } else {
              selected[key] = value;
            }
          }),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 80, child: Text(label)),
          bubble(
            old,
            '${bestMatches ? '最佳&保留' : '保留'}：${old.isEmpty ? '未提供' : old}',
            100,
            keep: true,
          ),
          for (final option in options)
            if (!(bestMatches && option.value == old))
              bubble(
                option.value,
                option.value.isEmpty ? '未提供' : option.value,
                option.score,
              ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sorted = candidates.values.toList()
      ..sort((a, b) {
        final score = b.song.score.compareTo(a.song.score);
        return score == 0 ? a.key.compareTo(b.key) : score;
      });
    return Scaffold(
      appBar: AppBar(
        title: const Text('在线搜索歌曲信息'),
        actions: [
          IconButton(
            tooltip: '区域 ${region.toUpperCase()}',
            icon: const Icon(Icons.public),
            onPressed: busy ? null : editRegion,
          ),
          IconButton(
            tooltip: '应用选中信息',
            icon: const Icon(Icons.check),
            onPressed: busy ? null : applySelection,
          ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverToBoxAdapter(
                child: Form(
                  key: form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: title,
                        decoration: const InputDecoration(labelText: '标题（必填）'),
                        textInputAction: TextInputAction.next,
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? '请填写标题' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: artist,
                        decoration: const InputDecoration(labelText: '艺术家（必填）'),
                        textInputAction: TextInputAction.next,
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? '请填写艺术家' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: album,
                        decoration: const InputDecoration(labelText: '专辑（选填）'),
                        onFieldSubmitted: (_) => unawaited(search()),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final e in SongSearchClient.sources.entries)
                            FilterChip(
                              label: Text(e.value),
                              selected: enabled[e.key] == true,
                              onSelected: busy
                                  ? null
                                  : (v) {
                                      setState(() => enabled[e.key] = v);
                                      widget
                                              .document
                                              .data['songSearch_${e.key}'] =
                                          v;
                                      unawaited(widget.onSettings());
                                    },
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          TextButton(
                            onPressed: busy ? null : search,
                            child: const Text('搜索'),
                          ),
                          if (busy)
                            TextButton(
                              onPressed: () {
                                cancel?.cancel();
                                setState(() {
                                  busy = false;
                                  pending.clear();
                                  statuses.updateAll(
                                    (k, v) => v.contains('中') ? '已停止' : v,
                                  );
                                });
                              },
                              child: const Text('停止'),
                            ),
                        ],
                      ),
                      if (busy)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: LinearProgressIndicator(),
                        ),
                      if (!busy && statuses.isNotEmpty && sorted.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 16),
                          child: Text('没有找到歌曲，可以调整标题、艺术家或搜索源。'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverToBoxAdapter(
                child: SingleChildScrollView(
                  key: const ValueKey('song-field-flow'),
                  scrollDirection: Axis.horizontal,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final e in songSearchFields.entries)
                        fieldFlow(e.key, e.value),
                    ],
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final e in statuses.entries)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '${SongSearchClient.sources[e.key]} ${e.value}',
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
