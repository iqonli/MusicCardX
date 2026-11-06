import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'model.dart';

const projectUrl = 'https://github.com/iqonli/MusicCardX';
const thirdPartyProjects = <(String, String, String)>[
  ('MusicCard', 'https://github.com/iqonli/MusicCard', 'LGPL-3.0-or-later'),
  ('ezCD', 'https://github.com/iqonli/ezCD', 'MIT'),
  ('Flutter', 'https://github.com/flutter/flutter', 'BSD-3-Clause'),
  (
    'Material Color Utilities',
    'https://github.com/material-foundation/material-color-utilities',
    'Apache-2.0',
  ),
  (
    'dynamic_color',
    'https://github.com/material-foundation/flutter-packages/tree/main/packages/dynamic_color',
    'Apache-2.0',
  ),
  ('PhotoView', 'https://github.com/bluefireteam/photo_view', 'MIT'),
  (
    'audio_metadata_reader',
    'https://github.com/ClementBeal/audio_metadata_reader',
    'MIT',
  ),
  ('opencc-js', 'https://github.com/nk2028/opencc-js', 'MIT'),
  ('OpenCC数据', 'https://github.com/BYVoid/OpenCC', 'Apache-2.0'),
  (
    'characters',
    'https://github.com/dart-lang/core/tree/main/pkgs/characters',
    'BSD-3-Clause',
  ),
  ('AutoCoverDownTool', 'https://github.com/iqonli', 'MIT（移植部分）'),
  ('PointyCastle', 'https://github.com/bcgit/pc-dart', 'MIT'),
  ('image', 'https://github.com/brendan-duncan/image', 'MIT'),
  ('archive', 'https://github.com/brendan-duncan/archive', 'MIT'),
  (
    'crypto',
    'https://github.com/dart-lang/core/tree/main/pkgs/crypto',
    'BSD-3-Clause',
  ),
  ('unorm_dart', 'https://github.com/yshrsmz/unorm-dart', 'MIT'),
];

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});
  Future<void> open(BuildContext context, String url) async {
    try {
      await platform.invokeMethod('openUrl', {
        'url': Uri.parse(url).normalizePath().toString(),
      });
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(milliseconds: 1500),
            content: Text('无法打开浏览器'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('关于')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'MusicCardX',
            style: TextStyle(fontSize: 36, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text('1.5.1', style: TextStyle(fontSize: 20)),
          const SizedBox(height: 20),
          const SelectableText(
            'by IQ Online Studio, github.com/iqonli/MusicCardX',
          ),
          const SizedBox(height: 12),
          const SelectableText(
            '本项目使用GNU Lesser General Public License v3.0 or later许可证。',
          ),
          const SizedBox(height: 12),
          const SelectableText('作者：PerryDing (QQ: 34067513)'),
          const SizedBox(height: 8),
          const Text('出品：IQ Online Studio'),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => open(context, projectUrl),
            child: const Text('打开Github'),
          ),
          const SizedBox(height: 32),
          const Text(
            '使用的第三方项目',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          for (final project in thirdPartyProjects)
            Card(
              key: ValueKey('project-${project.$1}'),
              margin: const EdgeInsets.only(bottom: 10),
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.$1,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () => open(context, project.$2),
                      child: Text(
                        project.$2,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(project.$3),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 32),
          const Text(
            'Powered by Flutter',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          const Text(
            'Licenses',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          const EmbeddedLicenses(),
        ],
      ),
    ),
  );
}

/// Shares Flutter's license registry with LicensePage. Only the package list is
/// embedded; selecting a card still opens the complete, attributed license text.
class EmbeddedLicenses extends StatefulWidget {
  final Stream<LicenseEntry> Function()? load;
  const EmbeddedLicenses({super.key, this.load});
  @override
  State<EmbeddedLicenses> createState() => _EmbeddedLicensesState();
}

class _EmbeddedLicensesState extends State<EmbeddedLicenses> {
  late final Future<Map<String, List<LicenseEntry>>> licenses = collect();
  Future<Map<String, List<LicenseEntry>>> collect() async {
    final result = <String, List<LicenseEntry>>{};
    await for (final entry in widget.load?.call() ?? LicenseRegistry.licenses) {
      for (final name in entry.packages) {
        result.putIfAbsent(name, () => []).add(entry);
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<Map<String, List<LicenseEntry>>>(
        future: licenses,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Text('许可证读取失败');
          }
          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            );
          }
          final data = snapshot.data!;
          final names = data.keys.toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final name in names)
                Card(
                  key: ValueKey('license-$name'),
                  margin: const EdgeInsets.only(bottom: 8),
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: ListTile(
                    title: Text(name),
                    subtitle: Text(
                      MaterialLocalizations.of(context)
                          .licensesPackageDetailText(data[name]!.length),
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PackageLicenseDetails(
                          name: name,
                          entries: data[name]!,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      );
}

class PackageLicenseDetails extends StatelessWidget {
  final String name;
  final List<LicenseEntry> entries;
  const PackageLicenseDetails({
    super.key,
    required this.name,
    required this.entries,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(name)),
    body: SelectionArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          for (int i = 0; i < entries.length; i++) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Divider(),
              ),
            for (final paragraph in entries[i].paragraphs)
              Padding(
                padding: EdgeInsetsDirectional.only(
                  top: 8,
                  start: paragraph.indent < 0 ? 0 : paragraph.indent * 16,
                ),
                child: Text(
                  paragraph.text,
                  textAlign: paragraph.indent == LicenseParagraph.centeredIndent
                      ? TextAlign.center
                      : TextAlign.start,
                ),
              ),
          ],
        ],
      ),
    ),
  );
}
