import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musiccardx/main.dart';
import 'package:musiccardx/model.dart';
import 'package:musiccardx/about_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ChineseConverter chinese;
  setUpAll(() async {
    await CardDocument.initialize();
    chinese = ChineseConverter();
    await chinese.load();
    final font = File('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc');
    if (font.existsSync()) {
      final loader = FontLoader('Roboto')
        ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
      await loader.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File(
                '../tooling/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
              ).readAsBytesSync(),
            ),
          ),
        );
      await icons.load();
    }
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, null),
  );
  testWidgets(
    'ordinary labels, input/settings button styling, headings, and panel outlines',
    (t) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform, (_) async => null);
      t.view.physicalSize = const Size(430, 960);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final key = GlobalKey();
      await t.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MusicCardX(CardDocument.fresh(), chinese),
        ),
      );
      await t.pumpAndSettle();
      final actions = t
          .widget<AppBar>(find.byType(AppBar))
          .actions!
          .cast<IconButton>();
      expect((actions.first.icon as Icon).icon, Icons.open_in_new);
      expect((actions.last.icon as Icon).icon, Icons.save_outlined);
      final input = t.widget<EditableText>(find.byType(EditableText).first);
      expect(
        input.style.color,
        Theme.of(t.element(find.byType(Editor))).colorScheme.onSurface,
      );
      for (final label in ['选择图片', '保存封面', '移除封面', '从音频文件读取', '清空歌词内容']) {
        final button = find.widgetWithText(TextButton, label);
        final style = TextButtonTheme.of(t.element(button)).style!;
        expect(style.elevation!.resolve({}), 0);
        expect(style.backgroundColor!.resolve({}), isNotNull);
        expect(t.getSize(button).height, greaterThanOrEqualTo(48));
      }
      // Only the editable field's label remains; the duplicate card title is gone.
      expect(find.text('歌词内容'), findsOneWidget);
      final clear = find.widgetWithText(TextButton, '清空歌词内容');
      final field = find.byKey(
        ValueKey(
          'lyrics-${t.widget<Editor>(find.byType(Editor)).document.hashCode}',
        ),
      );
      expect(t.getTopLeft(clear).dx, closeTo(t.getTopLeft(field).dx, 1));
      final json = find.text('编辑歌曲信息JSON');
      final text = t.renderObject<RenderParagraph>(json).text as TextSpan;
      expect(text.style!.color, Theme.of(t.element(json)).colorScheme.primary);
      await t.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        Directory('test-output').createSync();
        File('test-output/input-ui.png').writeAsBytesSync(
          (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
              .asUint8List(),
        );
        image.dispose();
      });
      await t.tap(find.text('设置'));
      await t.pumpAndSettle();
      for (final title in ['显示', '字体', '图片', '配置']) {
        expect(find.text(title), findsNothing);
      }
      final font = find.text('字体管理器');
      final tileMaterial = t.widget<Material>(
        find.ancestor(of: font, matching: find.byType(Material)).first,
      );
      expect(tileMaterial.elevation, 0);
      final label = t.renderObject<RenderParagraph>(font).text as TextSpan;
      expect(
        label.style!.color,
        Theme.of(t.element(font)).colorScheme.onSurface,
      );
      await t.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        File('test-output/settings-ui.png').writeAsBytesSync(
          (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
              .asUint8List(),
        );
        image.dispose();
      });
      await t.tap(find.text('工作台'));
      await t.pumpAndSettle();
      final containers = t.widgetList<Container>(find.byType(Container));
      final panels = containers.where(
        (c) =>
            c.decoration is BoxDecoration &&
            (c.decoration as BoxDecoration).borderRadius ==
                BorderRadius.circular(12),
      );
      expect(panels, isNotEmpty);
      for (final p in panels) {
        expect((p.decoration as BoxDecoration).border, isNull);
      }
      final setting = find.text('输出倍率');
      final decoration =
          t
                  .widget<Container>(
                    find
                        .ancestor(of: setting, matching: find.byType(Container))
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(decoration.boxShadow, isNull);
      expect(decoration.color, defaultControlColor);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('About has project cards, LGPL line, and peer license headings', (
    t,
  ) async {
    await t.pumpWidget(const MaterialApp(home: AboutPage()));
    await t.pumpAndSettle();
    expect(find.byType(DataTable), findsNothing);
    for (final p in thirdPartyProjects) {
      expect(find.byKey(ValueKey('project-${p.$1}')), findsOneWidget);
    }
    const notice = '本项目使用GNU Lesser General Public License v3.0 or later许可证。';
    expect(
      t.getTopLeft(find.text(notice)).dy,
      greaterThan(
        t
            .getTopLeft(
              find.text('by IQ Online Studio, github.com/iqonli/MusicCardX'),
            )
            .dy,
      ),
    );
    final powered = t.widget<Text>(find.text('Powered by Flutter')).style!;
    final licenses = t.widget<Text>(find.text('Licenses')).style!;
    expect(licenses, powered);
    expect(find.text('Licenses:'), findsNothing);
    expect(find.byType(EmbeddedLicenses), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('embedded license cards open the full attributed license text', (
    t,
  ) async {
    final entry = LicenseEntryWithLineBreaks([
      'Example package',
    ], 'Copyright Example\n\nPermission grant preserved.');
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EmbeddedLicenses(load: () => Stream.value(entry))),
      ),
    );
    await t.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('license-Example package')),
      findsOneWidget,
    );
    await t.tap(find.text('Example package'));
    await t.pumpAndSettle();
    expect(find.byType(PackageLicenseDetails), findsOneWidget);
    expect(find.text('Copyright Example'), findsOneWidget);
    expect(find.text('Permission grant preserved.'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    expect(t.takeException(), isNull);
  });
}
