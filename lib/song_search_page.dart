import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';

import 'metadata_prompt.dart';
import 'intent_actions.dart';
import 'editor_pages.dart';
import 'music_share.dart';
import 'netease_share_fallback.dart';
import 'cover_search_page.dart';

import 'package:flutter/material.dart';

import 'cover_search.dart';
import 'dialog_buttons.dart';
import 'model.dart';
import 'song_search.dart';

class SongSearchPage extends StatefulWidget {
  final CardDocument document;
  final Future<void> Function() onSettings;
  final SongSearchClient? client;
  final String? initialShareText;
  final MusicShareService? shareService;
  final NeteaseShareFallback? shareFallback;
  final Future<void> Function(Map<String, dynamic>)? onFields;
  final Future<void> Function(CoverAsset)? onCover;
  final Future<bool> Function(CoverAsset)? onSaveCover;
  const SongSearchPage({
    super.key,
    required this.document,
    required this.onSettings,
    this.client,
    this.initialShareText,
    this.shareService,
    this.shareFallback,
    this.onFields,
    this.onCover,
    this.onSaveCover,
  });
  @override
  State<SongSearchPage> createState() => _SongSearchPageState();
}

class _SongSearchPageState extends State<SongSearchPage>
    with SingleTickerProviderStateMixin {
  late final client = widget.client ?? SongSearchClient();
  late final original = Map<String, dynamic>.from(widget.document.fields);
  late final title = TextEditingController(text: '${original['title'] ?? ''}');
  late final artist = TextEditingController(
    text: '${original['artist'] ?? ''}',
  );
  late final album = TextEditingController(text: '${original['album'] ?? ''}');
  final form = GlobalKey<FormState>();
  late final tabs = TabController(
    length: 3,
    vsync: this,
    initialIndex: widget.initialShareText == null ? 0 : 2,
  );
  int lastTab = 0;
  final traditionalCandidates = <String, SongCandidate>{},
      linkCandidates = <String, SongCandidate>{};
  Map<String, SongCandidate> get candidates =>
      tabs.index == 2 ? linkCandidates : traditionalCandidates;
  final linkStatuses = <String, String>{},
      traditionalStatuses = <String, String>{};
  Map<String, String> get statuses =>
      tabs.index == 2 ? linkStatuses : traditionalStatuses;
  final traditionalSelected = <String, String>{},
      linkSelected = <String, String>{};
  Map<String, String> get selected =>
      tabs.index == 2 ? linkSelected : traditionalSelected;
  late final aiControllers = {
    for (final key in songSearchFields.keys)
      key: TextEditingController(text: '${original[key] ?? ''}'),
  };
  final aiScroll = ScrollController();
  final promptActionsKey = GlobalKey();
  late final helpLink = TapGestureRecognizer()..onTap = showShareHelp;
  final prompt = TextEditingController();
  final promptFocus = FocusNode();
  bool generated = false;
  bool promptExpanded = false;
  Map<String, String>? generatedInputs;
  Map<String, String> get currentAiInputs => {
    for (final e in aiControllers.entries) e.key: e.value.text,
  };
  bool get promptStale =>
      generatedInputs != null &&
      aiControllers.entries.any((e) => generatedInputs![e.key] != e.value.text);

  Future<void> editPromptTemplate() async {
    final input = TextEditingController(
      text:
          widget.document.data['metadataPromptTemplate'] as String? ??
          defaultMetadataPromptTemplate,
    );
    final saved = await showCardDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('修改提示词模板'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SelectableText(
                  '已有信息请使用{{filled_fields_json}}或%filled%占位，将自动替换。',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: input,
                  minLines: 8,
                  maxLines: 18,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => input.text = defaultMetadataPromptTemplate,
            child: const Text('恢复默认'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved == true && mounted) {
      widget.document.data['metadataPromptTemplate'] = input.text;
      await widget.onSettings();
    }
    // The route's closing transition may still use its text controller.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    input.dispose();
  }

  late final shareText = TextEditingController(
    text: widget.initialShareText ?? '',
  );
  late final resolver = widget.shareService ?? MusicShareService();
  late final shareFallback = widget.shareFallback ?? NeteaseShareFallback();
  final shareCovers = ShareCoverClient();
  late final shareLoader = CoverLoader(shareCovers);
  final shareResults = <ShareResult>[];
  final pending = <String>{};

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
    for (final c in aiControllers.values) {
      c.addListener(() {
        if (mounted) setState(() {});
      });
    }
    lastTab = tabs.index;
    tabs.addListener(() {
      if (lastTab != tabs.index) {
        cancel?.cancel();
        busy = false;
        lastTab = tabs.index;
        FocusManager.instance.primaryFocus?.unfocus();
        setState(() {});
      }
    });
    region = '${widget.document.data['songSearchRegion'] ?? 'cn'}';
  }

  @override
  void dispose() {
    cancel?.cancel();
    client.close();
    tabs.dispose();
    promptFocus.dispose();
    prompt.dispose();
    aiScroll.dispose();
    helpLink.dispose();
    shareText.dispose();
    for (final c in aiControllers.values) {
      c.dispose();
    }
    resolver.close();
    shareFallback.close();
    shareLoader.clear();
    shareCovers.close();
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

  Future<void> editRegion() async {
    final controller = TextEditingController(text: region);
    final value = await showCardDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('区域代号'),
        content: TextField(
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
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
    Navigator.pop(context, widget.document.cleanSongFields(fields));
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
      bool uncertain = false,
    }) {
      final active = keep ? !selected.containsKey(key) : selected[key] == value;
      final color = Theme.of(context).colorScheme.primary;
      final background = Color.lerp(
        Colors.white,
        color,
        (.08 + .52 * score / 100) * (uncertain ? .55 : 1),
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
                option.value.isEmpty
                    ? '未提供'
                    : '${option.value}${option.uncertain ? ' 存疑' : ''}',
                option.score,
                uncertain: option.uncertain,
              ),
        ],
      ),
    );
  }

  Future<void> editAiJson() async {
    final fields = {
      ...original,
      for (final e in aiControllers.entries) e.key: e.value.text,
    };
    final result = await showCardDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => SongJsonPage(
        fields: fields,
        disabled: widget.document.disabledSongFields,
      ),
    );
    if (result == null || !mounted) return;
    final clean = widget.document.cleanSongFields(result);
    await widget.onFields?.call(clean);
    if (!mounted) return;
    setState(() {
      original
        ..clear()
        ..addAll(clean);
      for (final e in aiControllers.entries) {
        e.value.text = '${clean[e.key] ?? ''}';
      }
    });
  }

  void generatePrompt() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      generated = true;
      generatedInputs = currentAiInputs;
      prompt.text = metadataPrompt({
        ...original,
        for (final e in aiControllers.entries)
          if (!widget.document.disabledSongFields.contains(e.key))
            e.key: e.value.text,
      }, template: widget.document.data['metadataPromptTemplate'] as String?);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final actions = promptActionsKey.currentContext;
      if (mounted && tabs.index == 1 && actions != null) {
        Scrollable.ensureVisible(
          actions,
          alignment: 0,
          duration: const Duration(milliseconds: 250),
        );
      }
    });
  }

  Widget aiBody() => LayoutBuilder(
    builder: (context, bounds) => ListView(
      controller: aiScroll,
      padding: const EdgeInsets.all(16),
      children: [
        for (final e in songSearchFields.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: TextField(
              onTapOutside: (_) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
              controller: aiControllers[e.key],
              decoration: InputDecoration(labelText: e.value),
            ),
          ),
        // Keep enough space below the actions to align them to the viewport top.
        ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: generated ? bounds.maxHeight : 0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextButton(
                key: promptActionsKey,
                onPressed: editAiJson,
                child: const Text('编辑歌曲信息JSON'),
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: generatePrompt,
                    child: const Text('生成提示词'),
                  ),
                  if (generated)
                    TextButton(
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: prompt.text)),
                      child: const Text('复制提示词'),
                    ),
                  TextButton(
                    onPressed: () async {
                      generatePrompt();
                      await Clipboard.setData(ClipboardData(text: prompt.text));
                    },
                    child: const Text('生成并复制'),
                  ),
                ],
              ),
              if (generated)
                IntentActionsBar(
                  actions: (widget.document.data['intentActions'] as List)
                      .map((e) => Map<String, dynamic>.from(e as Map))
                      .toList(),
                  prompt: () => prompt.text,
                  autoCopy: widget.document.data['intentAutoCopy'] != false,
                  onAutoCopy: (value) {
                    setState(
                      () => widget.document.data['intentAutoCopy'] = value,
                    );
                    unawaited(widget.onSettings());
                  },
                  onSave: (items) async {
                    setState(
                      () => widget.document.data['intentActions'] = items,
                    );
                    await widget.onSettings();
                  },
                ),
              if (generated) ...[
                const SizedBox(height: 8),
                Stack(
                  children: [
                    TextField(
                      onTapOutside: (_) =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      controller: prompt,
                      focusNode: promptFocus,
                      minLines: promptExpanded ? 10 : 1,
                      maxLines: promptExpanded ? 24 : 1,
                      decoration: InputDecoration(
                        labelText: '生成的提示词',
                        contentPadding: const EdgeInsets.fromLTRB(
                          12,
                          16,
                          12,
                          16,
                        ),
                        border: const OutlineInputBorder(),
                        enabledBorder: promptStale
                            ? const OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Colors.red,
                                  width: 2,
                                ),
                              )
                            : null,
                        focusedBorder: promptStale
                            ? const OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Colors.red,
                                  width: 2,
                                ),
                              )
                            : null,
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 33.6,
                          height: 33.6,
                        ),
                        iconSize: 16.8,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.transparent,
                        ),
                        tooltip: promptExpanded ? '缩小' : '放大',
                        icon: Icon(
                          promptExpanded
                              ? Icons.close_fullscreen
                              : Icons.open_in_full,
                        ),
                        onPressed: () =>
                            setState(() => promptExpanded = !promptExpanded),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                '将搜索歌曲信息的任务外包给你的AI。填写已知信息，点击生成提示词、复制，发给你的AI。可以使用自定义快捷方式一键启动APP，需提前配置。强烈建议开启深度思考、联网搜索，否则AI可能编造信息。复制AI的回答，点击“编辑歌曲复制JSON”并粘贴。',
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ],
    ),
  );
  Future<void> parseShare() async {
    cancel?.cancel();
    final token = CoverCancel();
    cancel = token;
    setState(() {
      busy = true;
      linkCandidates.clear();
      linkSelected.clear();
      linkStatuses.clear();
      shareResults.clear();
    });
    try {
      final parsed = await resolver.resolve(shareText.text, token);
      final results = await Future.wait(
        parsed.map((r) => shareFallback.complete(r, region, token)),
      );
      if (!mounted || token.cancelled) return;
      setState(() {
        shareResults.addAll(results);
        for (final r in results) {
          linkCandidates[r.candidate.key] = r.candidate;
          linkStatuses[r.platform] =
              '${results.where((x) => x.platform == r.platform).length}个候选';
        }
        linkSelected.addAll(
          defaultShareSelection(linkCandidates.values, original),
        );
      });
    } catch (e) {
      if (mounted && !token.cancelled) {
        setState(() => linkStatuses['解析'] = conciseError(e));
      }
    } finally {
      if (mounted && identical(cancel, token)) setState(() => busy = false);
    }
  }

  Future<void> viewShareCover() async {
    final available = shareResults.where((r) => r.cover.isNotEmpty).toList();
    if (available.isEmpty) return;
    ShareResult choice = available.first;
    if (available.length > 1) {
      final result = await showCardDialog<ShareResult>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('选择封面来源'),
          children: [
            for (final r in available)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, r),
                child: Text('${r.platform} ${r.candidate.song.title}'),
              ),
          ],
        ),
      );
      if (result == null || !mounted) return;
      choice = result;
    }
    final asset = await Navigator.push<CoverAsset>(
      context,
      MaterialPageRoute(
        builder: (_) => CoverDetailPage(
          candidate: choice.candidate.song,
          loader: shareLoader,
          previewSize: 150,
          downloadSize: 1000,
          askDownloadSize: true,
          onSave: widget.onSaveCover ?? (_) async => false,
        ),
      ),
    );
    if (asset != null && mounted) {
      await widget.onCover?.call(asset);
    }
  }

  void showShareHelp() {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('支持的解析链接')),
          body: const SingleChildScrollView(
            padding: EdgeInsets.all(20),
            child: SelectableText(
              '网易云：163cn.tv、163cn.link、music.163.com/song?id=2091914322\nQQ：c6.y.qq.com短链、y.qq.com/n/ryqq/songDetail/歌曲mid\n酷狗：m.kugou.com/share/song.html?chain=分享码、t1.kugou.com短链、带hash的歌曲链接。纯数字按歌曲编号尝试，分享口令不保证能解析。\n酷我：m.kuwo.cn/yinyue/56102277、www.kuwo.cn/play_detail/歌曲ID\n波点：h5app.kuwo.cn/m/bodian/playMusic.html?musicId=歌曲ID；play.html?mvId=视频ID只提供视频信息。\n汽水：qishui.douyin.com/s/短链、music.douyin.com/qishui/share/track?track_id=歌曲ID\n支持无协议网址、平台别名加ID（前后均可、可换行）、=后的ID；仅有ID时尝试全部平台。可粘贴整段分享文字、Markdown和多个链接。部分字段可能未提供；解析后默认选中各项首个候选，点击✓才应用。封面尺寸0表示向源站请求最大版本，失败时有限回退，不放大伪造原图像素。',
            ),
          ),
        ),
      ),
    );
  }

  Widget shareBody() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text.rich(
        TextSpan(
          children: [
            const TextSpan(
              text:
                  '粘贴分享链接、无协议网址或平台名与歌曲ID（前后均可）；只有ID时尝试全部平台。当前支持$sharePlatforms，',
            ),
            TextSpan(
              text: '点击此处',
              recognizer: helpLink,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                decoration: TextDecoration.underline,
              ),
            ),
            const TextSpan(text: '查看详细内容。你也可以在支持分享到其他应用的音乐软件中分享到MusicCardX。'),
          ],
        ),
      ),
      TextField(
        onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        controller: shareText,
        minLines: 3,
        maxLines: 8,
        decoration: const InputDecoration(labelText: '分享内容'),
      ),
      Wrap(
        spacing: 8,
        children: [
          TextButton(
            onPressed: () async {
              final data = await Clipboard.getData(Clipboard.kTextPlain);
              if (mounted) shareText.text = data?.text ?? '';
            },
            child: const Text('粘贴'),
          ),
          TextButton(
            onPressed: busy ? null : parseShare,
            child: const Text('解析'),
          ),
          if (busy)
            TextButton(
              onPressed: () {
                cancel?.cancel();
                setState(() => busy = false);
              },
              child: const Text('取消'),
            ),
        ],
      ),
      if (busy) const LinearProgressIndicator(),
      if (shareResults.any((r) => r.cover.isNotEmpty))
        Align(
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('解析到封面图片！', style: TextStyle(color: Colors.red)),
              TextButton(onPressed: viewShareCover, child: const Text('查看封面')),
            ],
          ),
        ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final e in songSearchFields.entries) fieldFlow(e.key, e.value),
          ],
        ),
      ),
      for (final r in shareResults)
        Text('${r.platform} ${r.warnings.join('；')}'),
      for (final e in linkStatuses.entries) Text('${e.key} ${e.value}'),
    ],
  );

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
        bottom: TabBar(
          controller: tabs,
          tabs: const [
            Tab(text: '传统爬爬'),
            Tab(text: 'AI外包'),
            Tab(text: '来自音乐软件'),
          ],
        ),
        actions: [
          if (tabs.index == 0)
            IconButton(
              tooltip: '区域 ${region.toUpperCase()}',
              icon: const Icon(Icons.public),
              onPressed: busy ? null : editRegion,
            ),
          if (tabs.index == 1)
            IconButton(
              tooltip: '修改提示词模板',
              icon: const Icon(Icons.settings),
              onPressed: editPromptTemplate,
            ),
          IconButton(
            tooltip: tabs.index == 1 ? '返回' : '应用选中信息',
            icon: const Icon(Icons.check),
            onPressed: tabs.index == 1
                ? () => Navigator.pop(context)
                : busy
                ? null
                : applySelection,
          ),
        ],
      ),
      body: tabs.index == 1
          ? aiBody()
          : tabs.index == 2
          ? shareBody()
          : GestureDetector(
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
                              onTapOutside: (_) =>
                                  FocusManager.instance.primaryFocus?.unfocus(),
                              controller: title,
                              decoration: const InputDecoration(
                                labelText: '标题（必填）',
                              ),
                              textInputAction: TextInputAction.next,
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? '请填写标题'
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              onTapOutside: (_) =>
                                  FocusManager.instance.primaryFocus?.unfocus(),
                              controller: artist,
                              decoration: const InputDecoration(
                                labelText: '艺术家（必填）',
                              ),
                              textInputAction: TextInputAction.next,
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? '请填写艺术家'
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              onTapOutside: (_) =>
                                  FocusManager.instance.primaryFocus?.unfocus(),
                              controller: album,
                              decoration: const InputDecoration(
                                labelText: '专辑（选填）',
                              ),
                              onFieldSubmitted: (_) => unawaited(search()),
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final e
                                    in SongSearchClient.sources.entries)
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
