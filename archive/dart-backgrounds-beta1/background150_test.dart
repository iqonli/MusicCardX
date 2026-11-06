import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:musiccardx/model.dart';
import 'package:musiccardx/renderer.dart';

import 'background150_math.dart' as math_test;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(CardDocument.initialize);
  test('approved C++ samples and parameter bounds', math_test.main);
  test(
    'background migration, independent blur values and config round trip',
    () {
      final raw = CardDocument.fresh().data;
      raw.remove('backgroundBlurStrengths');
      raw['backgroundStyle'] = 'fusion';
      raw['blurStrength'] = 123;
      final d = CardDocument.fromJson(raw);
      expect(d.text('backgroundStyle'), 'fusionClassic');
      expect(d.n('blurStrength'), 123);
      d.setBackground('fusionSoft');
      expect(d.n('blurStrength'), 0);
      d.data['blurStrength'] = 45;
      d.setBackground('mist');
      d.data['blurStrength'] = 67;
      d.setBackground('fusionSoft');
      expect(d.n('blurStrength'), 45);
      d.setBackground('mist');
      expect(d.n('blurStrength'), 67);
      d.data['solidHex'] = 'r%10';
      final copy = CardDocument.fromJson(
        jsonDecode(jsonEncode(d.data)) as Map<String, dynamic>,
      );
      expect(
        copy.data['backgroundBlurStrengths'],
        d.data['backgroundBlurStrengths'],
      );
      expect(copy.text('solidHex'), 'r%10');
      expect(backgrounds.values.toList(), [
        '融合classic',
        '融合soft',
        '融合hard',
        '流光',
        '雾化',
        '墨点',
        '采点',
        '模糊',
        '纯色',
      ]);
    },
  );
  test('all new backgrounds render through CardRenderer', () async {
    final renderer = CardRenderer(ChineseConverter(), FontRegistry());
    for (final mode in newBackgrounds) {
      final d = CardDocument.fresh()..setBackground(mode);
      final result = await renderer.render(d, scaleOverride: .2);
      expect(result.image.width, greaterThan(0));
      result.image.dispose();
    }
  });
}
