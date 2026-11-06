import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'intent_actions.dart';
import 'dialog_buttons.dart';

/// Memory-only session cache; disposed with the Flutter isolate, never written to disk.
class ActivityCatalogCache {
  static Future<List<Map<String, dynamic>>>? inventory;
  static final icons = <String, Future<Uint8List?>>{};
  static void clear() {
    inventory = null;
    icons.clear();
  }

  static Future<List<Map<String, dynamic>>> get() {
    if (inventory != null) return inventory!;
    final request = actionChannel
        .invokeListMethod<dynamic>('catalogLoad')
        .then(
          (items) => (items ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList(),
        );
    inventory = request;
    request.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        if (identical(inventory, request)) inventory = null;
      },
    );
    return request;
  }
}

class ActivityCatalogPage extends StatefulWidget {
  const ActivityCatalogPage({super.key});
  @override
  State<ActivityCatalogPage> createState() => _CatalogState();
}

class _CatalogState extends State<ActivityCatalogPage> {
  final search = TextEditingController();
  final icons = ActivityCatalogCache.icons;
  final rows = <String, Future<List<Map<String, dynamic>>>>{};
  List<Map<String, dynamic>> apps = [];
  List<Map<String, dynamic>>? results;
  bool loading = true, searching = false;
  String? error;
  Timer? debounce, progressTimer;
  int loaded = 0, total = 0;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    debounce?.cancel();
    progressTimer?.cancel();
    search.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> invoke(
    String method, [
    Map<String, dynamic>? args,
  ]) async =>
      (await actionChannel.invokeListMethod<dynamic>(method, args) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  Future<void> load() async {
    setState(() {
      loading = true;
      loaded = 0;
      total = 0;
    });
    progressTimer?.cancel();
    progressTimer = Timer.periodic(const Duration(milliseconds: 200), (
      _,
    ) async {
      try {
        final v = await actionChannel.invokeMapMethod<String, dynamic>(
          'catalogProgress',
        );
        if (mounted && loading) {
          setState(() {
            loaded = (v?['loaded'] as int?) ?? 0;
            total = (v?['total'] as int?) ?? 0;
          });
        }
      } catch (_) {}
    });
    try {
      final value = await ActivityCatalogCache.get();
      if (mounted) {
        setState(() {
          apps = value;
          error = null;
          loading = false;
          progressTimer?.cancel();
        });
        query(search.text);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          loading = false;
          progressTimer?.cancel();
        });
      }
    }
  }

  void query(String text) {
    final q = text.trim().toLowerCase();
    setState(() {
      results = q.isEmpty
          ? null
          : [
              for (final app in apps)
                if ('${app['name']} ${app['package']}'.toLowerCase().contains(
                  q,
                ))
                  app
                else if ((app['activities'] as List).any(
                  (a) => '${a['name']} ${a['className']}'
                      .toLowerCase()
                      .contains(q),
                ))
                  {
                    ...app,
                    'activities': (app['activities'] as List)
                        .where(
                          (a) => '${a['name']} ${a['className']}'
                              .toLowerCase()
                              .contains(q),
                        )
                        .toList(),
                  },
            ];
    });
  }

  Future<void> choose(Map<String, dynamic> item) async {
    final operation = await showCardDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('${item['name']}'),
        children: [
          SimpleDialogOption(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            onPressed: () => Navigator.pop(ctx, 'fill'),
            child: const Text('填入“目标Activity”'),
          ),
          SimpleDialogOption(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            onPressed: () => Navigator.pop(ctx, 'launch'),
            child: const Text('启动活动'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (operation == 'fill') {
      Navigator.pop(context, item);
    }
    if (operation == 'launch') {
      try {
        await actionChannel.invokeMethod('launchAction', {
          'component': item['component'],
          'action': '',
          'mime': '',
          'extras': [],
        });
      } catch (e) {
        if (mounted) toast('$e');
      }
    }
  }

  Future<Uint8List?> icon(String pkg) {
    final cached = icons.remove(pkg);
    if (cached != null) {
      icons[pkg] = cached;
      return cached;
    }
    final value = actionChannel.invokeMethod<Uint8List>('catalogIcon', {
      'package': pkg,
    });
    icons[pkg] = value;
    if (icons.length > 96) icons.remove(icons.keys.first);
    return value;
  }

  Widget appIcon(String pkg) => FutureBuilder<Uint8List?>(
    future: icon(pkg),
    builder: (context, s) => s.data == null
        ? const Icon(Icons.apps)
        : Image.memory(s.data!, width: 36, height: 36, cacheWidth: 64),
  );
  void toast(String text) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), duration: const Duration(milliseconds: 1500)),
  );
  Widget activity(Map<String, dynamic> item) => ListTile(
    dense: true,
    contentPadding: const EdgeInsets.only(left: 28, right: 8),
    leading: Icon(
      item['callable'] == true ? Icons.open_in_new : Icons.lock_outline,
      size: 20,
    ),
    title: Text('${item['name']}'),
    subtitle: Text(
      '${item['className']}\n${item['enabled'] == false
          ? '已停用'
          : item['exported'] == false
          ? '内部活动'
          : item['callable'] == false
          ? '需要权限'
          : '可供外部调用'}${'${item['permission'] ?? ''}'.isEmpty ? '' : '  ${item['permission']}'}',
    ),
    isThreeLine: true,
    onTap: () => choose(item),
    trailing: IconButton(
      tooltip: '复制活动名称',
      icon: const Icon(Icons.copy_outlined, size: 20),
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: '${item['className']}'));
        if (mounted) toast('已复制活动名称');
      },
    ),
  );
  Widget app(Map<String, dynamic> item) {
    final pkg = '${item['package']}';
    return ExpansionTile(
      key: PageStorageKey('app-$pkg-${results != null}'),
      leading: appIcon(pkg),
      title: Text('${item['name']}'),
      subtitle: Text(pkg),
      children: [
        if (item['activities'] is List)
          for (final row in item['activities'] as List)
            activity(Map<String, dynamic>.from(row as Map))
        else
          _LazyActivities(
            load: () => rows.putIfAbsent(
              pkg,
              () => invoke('catalogActivities', {'package': pkg}),
            ),
            row: activity,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = results ?? apps;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity列表'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () {
              generation++;
              debounce?.cancel();
              search.clear();
              ActivityCatalogCache.clear();
              rows.clear();
              icons.clear();
              results = null;
              searching = false;
              load();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: search,
              onChanged: query,
              onTapOutside: (_) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '搜索应用、包名或活动名称',
              ),
            ),
          ),
          if (searching) const LinearProgressIndicator(),
          if (error != null)
            Padding(padding: const EdgeInsets.all(12), child: Text(error!)),
          Expanded(
            child: loading
                ? Center(
                    child: SizedBox(
                      width: 240,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          LinearProgressIndicator(
                            value: total > 0 ? loaded / total : null,
                          ),
                          const SizedBox(height: 8),
                          Text('$loaded/$total'),
                        ],
                      ),
                    ),
                  )
                : list.isEmpty
                ? const Center(child: Text('没有匹配的项目'))
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (context, i) => app(list[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _LazyActivities extends StatefulWidget {
  final Future<List<Map<String, dynamic>>> Function() load;
  final Widget Function(Map<String, dynamic>) row;
  const _LazyActivities({required this.load, required this.row});
  @override
  State<_LazyActivities> createState() => _LazyActivitiesState();
}

class _LazyActivitiesState extends State<_LazyActivities> {
  late final future = widget.load();
  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<Map<String, dynamic>>>(
        future: future,
        builder: (context, s) {
          if (s.hasError) {
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Text('${s.error}'),
            );
          }
          if (!s.hasData) {
            return const Padding(
              padding: EdgeInsets.all(12),
              child: LinearProgressIndicator(),
            );
          }
          if (s.data!.isEmpty) return const ListTile(title: Text('没有Activity'));
          return Column(children: s.data!.map(widget.row).toList());
        },
      );
}
