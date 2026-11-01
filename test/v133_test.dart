import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musiccardx/audio_import.dart';
import 'package:musiccardx/model.dart';
import 'package:musiccardx/main.dart';
import 'package:musiccardx/about_page.dart';
import 'package:musiccardx/palette_tools.dart';
import 'package:musiccardx/storage_policy.dart';
import 'package:musiccardx/fonts.dart';
import 'package:crypto/crypto.dart';
import 'package:musiccardx/renderer.dart';
import 'package:musiccardx/image_viewer.dart';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:audio_metadata_reader/src/parsers/tags/vorbis_comment.dart';

List<int> id3(String? track, {int version = 3}) {
  final payload = [0, ...latin1.encode(track ?? 'Title')];
  final id = version == 2
      ? (track == null ? 'TT2' : 'TRK')
      : (track == null ? 'TIT2' : 'TRCK');
  final frame = [
    ...latin1.encode(id),
    if (version != 2) 0,
    0,
    0,
    payload.length,
    if (version != 2) ...[0, 0],
    ...payload,
  ];
  return [
    ...latin1.encode('ID3'),
    version,
    0,
    0,
    0,
    0,
    frame.length >> 7,
    frame.length & 127,
    ...frame,
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ChineseConverter chinese;
  setUpAll(() async {
    await CardDocument.initialize();
    chinese = ChineseConverter();
    await chinese.load();
    final fontFile = File(
      '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
    );
    if (fontFile.existsSync()) {
      final text = FontLoader('Roboto')
        ..addFont(
          Future.value(ByteData.sublistView(fontFile.readAsBytesSync())),
        );
      await text.load();
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
  for (final item in [
    (2, '03 / 12\x00'),
    (3, '03\x00'),
    (3, '03 / 12\x00'),
    (4, '03\x00'),
  ]) {
    test('ID3v2.${item.$1} track ${item.$2.codeUnits}', () {
      final dir = Directory.systemTemp.createTempSync('mcx-track-');
      try {
        final f = File('${dir.path}/tag.mp3')
          ..writeAsBytesSync(id3(item.$2, version: item.$1));
        final info = readAudioInformation(f.path);
        expect(info.fields['tracknumber'], '3');
        if (item.$2.contains('/')) expect(info.fields['totaltracks'], '12');
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  }
  for (final v2 in [false, true]) {
    test('ID3v1.1 track is read with v2=$v2', () {
      final dir = Directory.systemTemp.createTempSync('mcx-v1-');
      try {
        final footer = Uint8List(128)..setRange(0, 3, latin1.encode('TAG'));
        footer[126] = 7;
        footer[127] = 255;
        final f = File('${dir.path}/v1.mp3')
          ..writeAsBytesSync([if (v2) ...id3(null), ...footer]);
        expect(readAudioInformation(f.path).fields['tracknumber'], '7');
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  }
  test('Vorbis TRACK aliases and invalid total do not abort tags', () {
    for (final key in ['TRACK', 'TRACKNO', 'TRACK_NUMBER', 'TRACKNUMBER']) {
      final m = VorbisMetadata();
      parseVorbisComment(utf8.encode('$key=03 / 12\x00'), m, fetchImage: false);
      expect(m.trackNumber, [3]);
      expect(m.trackTotal, 12);
      parseVorbisComment(utf8.encode('TRACKTOTAL=bad'), m, fetchImage: false);
    }
    expect(audioNumberPair(null, null, {'TRACK NUMBER': '03/12'}), (3, 12));
    expect(audioNumberPair(null, null, {'TRK': '3', 'TOTAL_TRACKS': '12'}), (
      3,
      12,
    ));
    expect(audioNumberPair(null, null, {'track': 'invalid'}), (null, null));
  });
  test('foobar-like palette favours representative vivid colours over dominant grey', () async {
    final pixels = Uint8List(100 * 4);
    for (int i = 0; i < 100; i++) {
      pixels.setRange(
        i * 4,
        i * 4 + 4,
        i < 80
            ? [140, 140, 140, 255]
            : i < 90
            ? [230, 30, 35, 255]
            : [20, 70, 235, 255],
      );
    }
    final p = CoverPixels(10, 10, pixels);
    final colors = await p.palette('foobar');
    expect(colors, hasLength(5));
    expect(HSVColor.fromColor(colors.first).saturation, greaterThan(.6));
    expect(await p.palette('foobar'), colors);
    final doc = CardDocument.fresh()..data['paletteAlgorithm'] = 'foobar';
    expect(CardDocument.fromJson(doc.data).text('paletteAlgorithm'), 'foobar');
    final gray = CoverPixels(1, 1, Uint8List.fromList([90, 90, 90, 255]));
    expect(
      (await gray.palette('foobar'))
          .every((c) => HSVColor.fromColor(c).saturation < .02),
      isTrue,
    );
  });
  test(
    'font cleanup retains referenced imports, removes only regenerable blobs',
    () async {
      final root = await Directory.systemTemp.createTemp('mcx-font-clean-');
      try {
        final hash = 'a' * 64, other = 'b' * 64;
        final imported = File('${root.path}/$hash.font');
        await imported.writeAsString('user');
        final cache = File('${root.path}/$hash.cache');
        await cache.writeAsString('duplicate');
        final orphan = File('${root.path}/$other.font');
        await orphan.writeAsString('unused');
        final catalog = File('${root.path}/state.json');
        await catalog.writeAsString('{}');
        await pruneFontStorage(root, {imported.path});
        expect(await imported.exists(), true);
        expect(await catalog.exists(), true);
        expect(await cache.exists(), false);
        expect(await orphan.exists(), false);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
  test(
    'legacy font duplicate removal requires verified complete migration',
    () async {
      final root = await Directory.systemTemp.createTemp('mcx-legacy-');
      try {
        final old = Directory('${root.path}/fonts');
        await old.create();
        final current = Directory('${root.path}/fonts-flutter');
        await current.create();
        final data = Uint8List.fromList([1, 2, 3]);
        final hash = sha256.convert(data).toString();
        final source = File('${old.path}/$hash.font');
        await source.writeAsBytes(data);
        final destination = File('${current.path}/$hash.font');
        await destination.writeAsBytes(data);
        await File('${old.path}/catalog.json').writeAsString(
          jsonEncode({
            'fonts': [
              {'blob': hash, 'face': 0},
            ],
          }),
        );
        final repository = FontRepository()..root = current;
        await repository.pruneLegacyDuplicates(root.path);
        expect(await source.exists(), true);
        repository.local = [
          {'sha256': hash, 'faceIndex': 0},
        ];
        await destination.writeAsBytes([0]);
        await repository.pruneLegacyDuplicates(root.path);
        expect(await source.exists(), true);
        await destination.writeAsBytes(data);
        await repository.pruneLegacyDuplicates(root.path);
        expect(await source.exists(), false);
        expect(await destination.readAsBytes(), data);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
  test('Gaussian cover shadow has no alternating contour gaps at 4x', () async {
    final r = ui.PictureRecorder();
    final c = Canvas(r)..scale(4);
    paintCoverShadow(
      c,
      Path()..addRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(20, 20, 40, 40),
          const Radius.circular(15),
        ),
      ),
      12,
      200,
    );
    final pic = r.endRecording();
    final img = await pic.toImage(320, 320);
    try {
      final data = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final alphas = [
        for (int x = 240; x < 310; x++) data.getUint8((160 * 320 + x) * 4 + 3),
      ];
      expect(alphas.first, greaterThan(40));
      for (int i = 1; i < alphas.length; i++) {
        expect(alphas[i], lessThanOrEqualTo(alphas[i - 1] + 1));
      }
      final out = File('test-output/shadow-1.3.3.png');
      out.parent.createSync(recursive: true);
      final displayRecorder = ui.PictureRecorder();
      final display = Canvas(displayRecorder);
      display.drawColor(Colors.white, BlendMode.src);
      display.drawImage(img, Offset.zero, Paint());
      display.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(80, 80, 160, 160),
          const Radius.circular(60),
        ),
        Paint()..color = const Color(0xffbdd0e8),
      );
      final displayPicture = displayRecorder.endRecording();
      final displayImage = await displayPicture.toImage(320, 320);
      await out.writeAsBytes(
        (await displayImage.toByteData(format: ui.ImageByteFormat.png))!.buffer
            .asUint8List(),
      );
      displayImage.dispose();
      displayPicture.dispose();
    } finally {
      img.dispose();
      pic.dispose();
    }
  });
  testWidgets(
    'actual image viewer keeps contained layout and zoom with bicubic',
    (t) async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.red, BlendMode.src);
      final picture = recorder.endRecording();
      late ui.Image image;
      await t.runAsync(() async {
        image = await picture.toImage(1600, 800);
      });
      await t.pumpWidget(MaterialApp(home: CardImageViewer(image: image)));
      await t.pumpAndSettle();
      final raw = find.byType(RawImage);
      expect(t.widget<RawImage>(raw).filterQuality, FilterQuality.high);
      final topLeft = t.getTopLeft(raw), bottomRight = t.getBottomRight(raw);
      expect(bottomRight.dx - topLeft.dx, closeTo(800, 1));
      expect(bottomRight.dy - topLeft.dy, closeTo(400, 1));
      final dynamic core = t.state(
        find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == 'PhotoViewCore',
        ),
      );
      core.nextScaleState();
      await t.pumpAndSettle();
      expect(t.getBottomRight(raw).dx - t.getTopLeft(raw).dx, greaterThan(800));
      await t.pumpWidget(const SizedBox());
      image.dispose();
      picture.dispose();
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('export icons, theme-backed panels, and redesigned About', (
    t,
  ) async {
    final urls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, (call) async {
          if (call.method == 'openUrl') urls.add(call.arguments['url']);
          return null;
        });
    t.view.physicalSize = const Size(430, 960);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    await t.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MusicCardX(CardDocument.fresh(), chinese),
      ),
    );
    await t.pumpAndSettle();
    final bar = t.widget<AppBar>(find.byType(AppBar));
    expect(bar.actions!.map((w) => (w as IconButton).tooltip).toList(), [
      '分享',
      '复制图片',
      '保存图片',
    ]);
    expect(find.text('复制图片'), findsNothing);
    final panel = find.byWidgetPredicate(
      (w) =>
          w is Card &&
          w.color ==
              Theme.of(t.element(find.byType(Editor)))
                  .colorScheme
                  .surfaceContainerLow,
    );
    expect(panel, findsWidgets);
    await t.tap(find.text('设置'));
    await t.pumpAndSettle();
    expect(find.text('MusicCardX 1.3.2'), findsNothing);
    await t.ensureVisible(find.text('关于'));
    await t.tap(find.text('关于'));
    await t.pumpAndSettle();
    expect(find.byType(AboutPage), findsOneWidget);
    expect(find.text('1.4.5'), findsOneWidget);
    expect(find.text('作者：PerryDing (QQ: 34067513)'), findsOneWidget);
    await t.tap(find.text('打开Github'));
    await t.pump();
    expect(urls, [projectUrl]);
    expect(find.text('使用的第三方项目'), findsOneWidget);
    expect(find.text('Powered by Flutter'), findsOneWidget);
    await t.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      File('test-output/about-1.3.3.png').writeAsBytesSync(
        (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
            .asUint8List(),
      );
      image.dispose();
    });
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, null);
  });
}
