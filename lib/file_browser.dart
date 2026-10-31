import 'dialog_buttons.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _io = MethodChannel('com.iqonli.musiccardx/platform');
Future<List<String>?> browseFiles(
  BuildContext context, {
  Set<String> extensions = const {},
  bool directory = false,
  bool multiple = true,
  String? initial,
}) async {
  if (Platform.isAndroid &&
      await _io.invokeMethod<bool>('requestStorage') != true) {
    return null;
  }
  if (!context.mounted) return null;
  return Navigator.push<List<String>>(
    context,
    MaterialPageRoute(
      builder: (_) => FileBrowser(
        extensions: extensions,
        directory: directory,
        multiple: multiple,
        initial: initial,
      ),
    ),
  );
}

class FileBrowser extends StatefulWidget {
  final Set<String> extensions;
  final bool directory;
  final bool multiple;
  final String? initial;
  const FileBrowser({
    super.key,
    required this.extensions,
    required this.directory,
    this.multiple = true,
    this.initial,
  });
  @override
  State<FileBrowser> createState() => _FileBrowserState();
}

class _FileBrowserState extends State<FileBrowser> {
  final path = TextEditingController();
  String current = '', error = '';
  List<FileSystemEntity> entries = [];
  final selected = <String>{};
  int serial = 0;
  @override
  void initState() {
    super.initState();
    load(widget.initial ?? '/storage/emulated/0/Download');
  }

  @override
  void dispose() {
    serial++;
    path.dispose();
    super.dispose();
  }

  Future<void> load(String folder) async {
    final token = ++serial;
    try {
      final dir = Directory(folder);
      final absolute = await dir.resolveSymbolicLinks();
      final list = await dir
          .list(followLinks: false)
          .where(
            (e) =>
                e is Directory ||
                !widget.directory &&
                    widget.extensions.contains(
                      e.path.split('.').last.toLowerCase(),
                    ),
          )
          .toList();
      list.sort((a, b) {
        if ((a is Directory) != (b is Directory)) {
          return a is Directory ? -1 : 1;
        }
        return a.path.toLowerCase().compareTo(b.path.toLowerCase());
      });
      if (!mounted || token != serial) return;
      setState(() {
        current = absolute;
        path.text = current;
        entries = list;
        error = '';
      });
    } catch (e) {
      if (mounted && token == serial) setState(() => error = '无法读取目录：$e');
    }
  }

  Future<void> create() async {
    final name = TextEditingController();
    final v = await showCardDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(controller: name, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, name.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (v != null &&
        v.trim().isNotEmpty &&
        !RegExp(r'[/\\]').hasMatch(v) &&
        v != '.' &&
        v != '..') {
      try {
        await Directory('$current/${v.trim()}').create();
        await load(current);
      } catch (e) {
        if (mounted) setState(() => error = '$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.directory ? '选择文件夹' : '文件管理器'),
      actions: [
        if (widget.directory)
          IconButton(
            tooltip: '新建文件夹',
            onPressed: create,
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
        TextButton(
          onPressed: current.isEmpty || !widget.directory && selected.isEmpty
              ? null
              : () => Navigator.pop(
                  context,
                  widget.directory ? [current] : selected.toList(),
                ),
          child: Text(widget.directory ? '使用此文件夹' : '选择 ${selected.length}'),
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: path,
            onSubmitted: load,
            decoration: InputDecoration(
              labelText: '路径',
              suffixIcon: IconButton(
                onPressed: () => load(path.text),
                icon: const Icon(Icons.arrow_forward),
              ),
            ),
          ),
        ),
        if (error.isNotEmpty) Text(error),
        Expanded(
          child: ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.arrow_upward),
                title: const Text('上级目录'),
                onTap: () => load(Directory(current).parent.path),
              ),
              for (final e in entries)
                ListTile(
                  dense: true,
                  leading: Icon(
                    e is Directory
                        ? Icons.folder_outlined
                        : Icons.insert_drive_file_outlined,
                  ),
                  title: Text(e.path.split('/').last),
                  trailing: e is Directory || !widget.multiple
                      ? null
                      : Checkbox(
                          value: selected.contains(e.path),
                          onChanged: (_) => choose(e.path),
                        ),
                  onTap: () => e is Directory ? load(e.path) : choose(e.path),
                ),
            ],
          ),
        ),
      ],
    ),
  );
  void choose(String p) {
    if (!widget.multiple) {
      Navigator.pop(context, [p]);
      return;
    }
    setState(() {
      if (!selected.remove(p)) selected.add(p);
    });
  }
}
