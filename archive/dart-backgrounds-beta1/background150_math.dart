import 'dart:io';

import 'package:musiccardx/seed_backgrounds.dart';

void main() {
  double maximum = 0;
  final modes = ['mist', 'fusionSoft', 'fusionHard', 'lightFlow'];
  for (final line in File(
    'test/fixtures/background150_cpp.txt',
  ).readAsLinesSync()) {
    final v = line.split(' ').map(double.parse).toList(),
        m = v[0].toInt(),
        seed = seedHash('测试seed01');
    final st = State(
      seed,
      (seed % 30000) / 197,
      1000,
      400,
      [
        for (var i = 0; i < 5; i++)
          satAdjust(V3(.15 + i * .12, .7 - i * .1, .23 + i * .09), 1.12),
      ],
      seedParameters(modes[m], '测试seed01'),
      null,
      null,
    );
    final uv = V2((v[1] + .5) / 5, (v[2] + .5) / 5),
        c = switch (m) {
          0 => shadeMist(st, uv),
          1 => shadeFusionSoft(st, uv),
          2 => shadeFusionHard(st, uv),
          _ => shadeLightFlow(st, uv),
        };
    for (var i = 0; i < 3; i++) {
      final error = ([c.x, c.y, c.z][i] - v[i + 3]).abs();
      if (error > maximum) maximum = error;
    }
  }
  print('100 C++/Dart field samples max RGB error: $maximum');
  if (maximum > .002) throw StateError('field mismatch');
  for (final mode in modes) {
    for (var i = 0; i < 200; i++) {
      final k = seedParameters(mode, '$i');
      for (var j = 0; j < 5; j++) {
        final range = parameterRanges[mode]![j];
        if (k[j] < range.$2 || k[j] > range.$3) throw StateError('range');
      }
    }
    final result = renderSeedBackground({
      'mode': mode,
      'seed': 'test',
      'width': 48.0,
      'height': 24.0,
      'palette': [0xffff0033, 0xff339900, 0xff0011ff, 0xffffaa00, 0xff0099aa],
    });
    if ((result['bytes'] as List).length != 48 * 24 * 4)
      throw StateError('size');
  }
  print('800 seeded parameter sets and all 4 raster paths passed');
}
