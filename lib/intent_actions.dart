import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dialog_buttons.dart';
import 'shortcut_flow.dart';
import 'activity_catalog.dart';
import 'intent_tutorial.dart';

const actionChannel = MethodChannel('com.iqonli.musiccardx/platform');
const extraTypes = [
  'string',
  'charSequence',
  'boolean',
  'int',
  'long',
  'double',
];

Map<String, dynamic> prepareAction(Map<String, dynamic> value, String prompt) {
  final component = '${value['component'] ?? ''}'.trim();
  if (!component.contains('/') ||
      component.startsWith('/') ||
      component.endsWith('/')) {
    throw const FormatException('目标Activity格式应为包名/完整类名');
  }
  final action = '${value['action'] ?? ''}'.trim();
  if (action.isEmpty) throw const FormatException('请填写Action');
  final extras = jsonDecode('${value['parameters'] ?? '[]'}');
  if (extras is! List) throw const FormatException('参数应为JSON数组');
  final keys = <String>{};
  final result = <Map<String, String>>[];
  for (final e in extras) {
    if (e is! Map ||
        e['key'] is! String ||
        '${e['key']}'.isEmpty ||
        !keys.add(e['key'])) {
      throw const FormatException('参数名不能为空或重复');
    }
    final type = '${e['type'] ?? 'string'}';
    if (!extraTypes.contains(type) || e['value'] is! String) {
      throw const FormatException('参数类型无效，value必须为字符串');
    }
    final v = (e['value'] as String).replaceAll('{{prompt}}', prompt);
    if (type == 'boolean' && v != 'true' && v != 'false') {
      throw const FormatException('布尔值应为true或false');
    }
    if (type == 'int' || type == 'long') {
      final n = int.tryParse(v);
      if (n == null || (type == 'int' && (n < -2147483648 || n > 2147483647))) {
        throw const FormatException('整数参数超出范围');
      }
    }
    if (type == 'double' && (double.tryParse(v)?.isFinite != true)) {
      throw const FormatException('浮点数参数无效');
    }
    result.add({'key': e['key'], 'type': type, 'value': v});
  }
  return {
    'component': component,
    'action': action,
    'mime': '${value['mime'] ?? ''}'.trim(),
    'extras': result,
  };
}

class IntentActionsBar extends StatefulWidget {
  final List<Map<String, dynamic>> actions;
  final String Function() prompt;
  final Future<void> Function(List<Map<String, dynamic>>) onSave;
  final bool autoCopy;
  final ValueChanged<bool>? onAutoCopy;
  const IntentActionsBar({
    super.key,
    required this.actions,
    required this.prompt,
    required this.onSave,
    this.autoCopy = true,
    this.onAutoCopy,
  });
  @override
  State<IntentActionsBar> createState() => _IntentActionsBarState();
}

class _IntentActionsBarState extends State<IntentActionsBar> {
  void message(Object e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          duration: const Duration(milliseconds: 1500),
        ),
      );
    }
  }

  Future<void> edit([int? index]) async {
    final value = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => IntentActionEditor(
          initial: index == null ? null : widget.actions[index],
          prompt: widget.prompt,
        ),
      ),
    );
    if (value == null || !mounted) return;
    final next = widget.actions
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    if (index == null) {
      next.add(value);
    } else {
      next[index] = value;
    }
    await widget.onSave(next);
  }

  Future<void> manage() async {
    await showCardDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refresh) => AlertDialog(
          title: const Text('管理'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final e in widget.actions.asMap().entries)
                    ListTile(
                      title: Text('${e.value['name']}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: '编辑',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () {
                              Navigator.pop(ctx);
                              edit(e.key);
                            },
                          ),
                          IconButton(
                            tooltip: '复制',
                            icon: const Icon(Icons.copy),
                            onPressed: () async {
                              await widget.onSave([
                                ...widget.actions,
                                {...e.value, 'name': '${e.value['name']} 副本'},
                              ]);
                              if (ctx.mounted) refresh(() {});
                            },
                          ),
                          IconButton(
                            tooltip: '删除',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              final next = [...widget.actions]..removeAt(e.key);
                              await widget.onSave(next);
                              if (ctx.mounted) refresh(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      for (final entry in widget.actions.asMap().entries)
        TextButton(
          onLongPress: () => edit(entry.key),
          child: Text('${entry.value['name']}'),
          onPressed: () async {
            try {
              final text = widget.prompt();
              final prepared = prepareAction(entry.value, text);
              if (widget.autoCopy) {
                await Clipboard.setData(ClipboardData(text: text));
              }
              await actionChannel.invokeMethod('launchAction', prepared);
            } catch (e) {
              message(e);
            }
          },
        ),
      TextButton(
        child: const Text('新建+', style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () => edit(),
      ),
      if (widget.actions.isNotEmpty)
        TextButton(
          onPressed: manage,
          child: const Text(
            '管理',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '开放、自由的，闪电般快速的意图和自由活动\n人话：'),
                  TextSpan(
                    text: '自定义快捷方式',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, bounds) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ShortcutFlow(
                  viewportWidth: bounds.maxWidth,
                  keepLastPair: widget.actions.isNotEmpty,
                  children: chips,
                ),
              ),
            ),
            CheckboxListTile(
              dense: true,
              visualDensity: const VisualDensity(vertical: -4),
              minVerticalPadding: 0,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('打开快捷方式前自动复制'),
              value: widget.autoCopy,
              onChanged: (value) {
                if (value != null) widget.onAutoCopy?.call(value);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class IntentActionEditor extends StatefulWidget {
  final Map<String, dynamic>? initial;
  final String Function() prompt;
  const IntentActionEditor({super.key, this.initial, required this.prompt});
  @override
  State<IntentActionEditor> createState() => _IntentActionEditorState();
}

class _IntentActionEditorState extends State<IntentActionEditor>
    with WidgetsBindingObserver {
  late final controls = {
    for (final k in ['name', 'component', 'action', 'mime', 'parameters'])
      k: TextEditingController(
        text:
            '${widget.initial?[k] ?? {'name': '', 'component': '', 'action': 'android.intent.action.PROCESS_TEXT', 'mime': 'text/plain', 'parameters': defaultParameters}[k]}',
      ),
  };
  static const defaultParameters =
      '[\n  {"key":"android.intent.extra.PROCESS_TEXT","type":"charSequence","value":"{{prompt}}"},\n  {"key":"android.intent.extra.PROCESS_TEXT_READONLY","type":"boolean","value":"true"}\n]';
  final testText = TextEditingController(text: '这是一段测试提示词，爱来自MusicCardX');
  List<String> missing = [];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    permissions();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) permissions();
  }

  Future<void> permissions() async {
    try {
      final v = await actionChannel.invokeListMethod<String>(
        'actionPermissions',
      );
      if (mounted) setState(() => missing = v ?? []);
    } catch (_) {}
  }

  @override
  void dispose() {
    testText.dispose();
    WidgetsBinding.instance.removeObserver(this);
    for (final c in controls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> get value => {
    for (final e in controls.entries) e.key: e.value.text,
  };
  void message(Object e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          duration: const Duration(milliseconds: 1500),
        ),
      );
    }
  }

  Future<void> select() async {
    try {
      final items =
          await actionChannel.invokeListMethod<dynamic>('textActions') ?? [];
      if (!mounted) return;
      final result = await showCardDialog<Map>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('从长按菜单中选取'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (items.isEmpty)
                    const Text('未找到可调用的文本处理入口。请检查应用安装状态和系统读取应用列表设置。'),
                  for (final item in items)
                    ListTile(
                      title: Text('${item['name']}'),
                      subtitle: Text('${item['component']}'),
                      onTap: () => Navigator.pop(ctx, item),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
          ],
        ),
      );
      if (result != null && mounted) {
        setState(() {
          controls['name']!.text = '${result['name']}';
          controls['component']!.text = '${result['component']}';
          controls['action']!.text = 'android.intent.action.PROCESS_TEXT';
          controls['mime']!.text = 'text/plain';
          controls['parameters']!.text = defaultParameters;
        });
      }
    } catch (e) {
      message(e);
    }
  }

  Widget field(String key, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(
      controller: controls[key],
      minLines: key == 'parameters' ? 5 : 1,
      maxLines: key == 'parameters' ? 14 : 1,
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      decoration: InputDecoration(
        labelText: label,
        helperText: key == 'parameters' ? 'JSON数组；{{prompt}}为提示词全文' : null,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.initial == null ? '新建调用' : '编辑调用')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Text(
            '此处可以自定义一个快捷方式，实现一键启动APP的指定活动。快捷方式就是构造Intent、传入参数、启动Activity。',
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton(onPressed: select, child: const Text('从长按菜单中选取')),
            TextButton(
              onPressed: () async {
                final item = await Navigator.push<Map<String, dynamic>>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ActivityCatalogPage(),
                  ),
                );
                if (item != null && mounted) {
                  setState(() {
                    controls['component']!.text = '${item['component']}';
                    if (controls['name']!.text.trim().isEmpty) {
                      controls['name']!.text = '${item['name']}';
                    }
                  });
                }
              },
              child: const Text('Activity列表'),
            ),
          ],
        ),
        field('name', '你喜欢叫它（这个调用）什么？在这里提出一个名字'),
        field('component', '包名/完整Activity类名'),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          title: const Text('详细设置 不建议编辑'),
          children: [
            field('action', 'Action'),
            field('mime', 'MIME'),
            field('parameters', '参数'),
          ],
        ),
        Wrap(
          spacing: 8,
          children: [
            for (final permission in missing)
              TextButton(
                onPressed: () =>
                    actionChannel.invokeMethod('actionPermissionSettings'),
                child: Text('获取$permission'),
              ),
            TextButton(
              onPressed: () async {
                try {
                  await actionChannel.invokeMethod(
                    'launchAction',
                    prepareAction(value, testText.text),
                  );
                } catch (e) {
                  message(e);
                }
              },
              child: const Text('测试'),
            ),
            TextButton(
              onPressed: () {
                try {
                  if (controls['name']!.text.trim().isEmpty) {
                    throw const FormatException('请填写名称');
                  }
                  prepareAction(value, widget.prompt());
                  Navigator.pop(context, value);
                } catch (e) {
                  message(e);
                }
              },
              child: const Text('保存'),
            ),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const IntentTutorialPage()),
              ),
              child: const Text('教程'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: testText,
          minLines: 2,
          maxLines: 5,
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          decoration: const InputDecoration(labelText: '测试文本'),
        ),
      ],
    ),
  );
}
