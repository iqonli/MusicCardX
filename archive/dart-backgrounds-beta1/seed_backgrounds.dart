import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as im;

// Dart port of the user-approved v7 fields. Parameter ranges remain frozen.
const PI = pi, TAU = pi * 2;
double clamp(num x) => x.clamp(0, 1).toDouble();
double fract(num x) => x - x.floorToDouble();
double mix(num a, num b, num t) => (a + (b - a) * t).toDouble();
double smooth(num a, num b, num x) {
  final t = clamp((x - a) / (b - a));
  return t * t * (3 - 2 * t);
}

class V2 {
  double x, y;
  V2(num x, num y) : x = x.toDouble(), y = y.toDouble();
  V2 operator +(V2 v) => V2(x + v.x, y + v.y);
  V2 operator -(V2 v) => V2(x - v.x, y - v.y);
  V2 operator *(num f) => V2(x * f, y * f);
  V2 operator /(num f) => V2(x / f, y / f);
}

class V3 {
  double x, y, z;
  V3(num x, num y, num z)
    : x = x.toDouble(),
      y = y.toDouble(),
      z = z.toDouble();
  V3 operator +(V3 v) => V3(x + v.x, y + v.y, z + v.z);
  V3 operator -(V3 v) => V3(x - v.x, y - v.y, z - v.z);
  V3 operator *(num f) => V3(x * f, y * f, z * f);
  V3 operator /(num f) => V3(x / f, y / f, z / f);
}

double dot(V2 a, V2 b) => a.x * b.x + a.y * b.y;
double length(V2 a) => sqrt(dot(a, a));
V2 rot(V2 p, num a) =>
    V2(p.x * cos(a) - p.y * sin(a), p.x * sin(a) + p.y * cos(a));
V3 cmix(V3 a, V3 b, num t) => a + (b - a) * t;
V3 sat(V3 c) => V3(clamp(c.x), clamp(c.y), clamp(c.z));
int hash32(int v) {
  v &= 0xffffffff;
  v ^= v >>> 16;
  v = (v * 0x7feb352d) & 0xffffffff;
  v ^= v >>> 15;
  v = (v * 0x846ca68b) & 0xffffffff;
  return (v ^ (v >>> 16)) & 0xffffffff;
}

double rnd(int x) => (hash32(x) >>> 8) / 16777216;
int seedHash(String s) {
  var h = 2166136261;
  for (final c in utf8.encode(s)) {
    h = ((h ^ c) * 16777619) & 0xffffffff;
  }
  h ^= h >>> 13;
  h = (h * 0x5bd1e995) & 0xffffffff;
  h ^= h >>> 15;
  return h == 0 ? 0x9e3779b9 : h;
}

// Per-render caches: bounded and cleared before each field. Values are exact memoized results.

final _gradients = <int, V2>{};
int _word(int x, int y, int salt) =>
    ((x * 0x9e3779b9) & 0xffffffff) ^ ((y * 0x85ebca6b) & 0xffffffff) ^ salt;
double _sample(int x, int y, int salt) {
  final key = _word(x, y, salt);
  return rnd(key);
}

double hash21(V2 p, int s) => _sample(p.x.floor(), p.y.floor(), s);
double valueNoise(V2 p, int s) {
  final ix = p.x.floor(), iy = p.y.floor(), fx = fract(p.x), fy = fract(p.y);
  final u = fx * fx * (3 - 2 * fx), v = fy * fy * (3 - 2 * fy);
  return mix(
    mix(_sample(ix, iy, s), _sample(ix + 1, iy, s), u),
    mix(_sample(ix, iy + 1, s), _sample(ix + 1, iy + 1, s), u),
    v,
  );
}

V2 grad2(V2 p, int s) {
  final key = _word(p.x.floor(), p.y.floor(), s);
  return _gradients.putIfAbsent(key, () {
    final a = rnd(key) * TAU;
    return V2(cos(a), sin(a));
  });
}

double perlin(V2 p, int s) {
  final i = V2(p.x.floor(), p.y.floor()), f = V2(fract(p.x), fract(p.y));
  final u = f.x * f.x * (3 - 2 * f.x), v = f.y * f.y * (3 - 2 * f.y);
  return .5 +
      .5 *
          mix(
            mix(
              dot(grad2(i, s), f),
              dot(grad2(i + V2(1, 0), s), f - V2(1, 0)),
              u,
            ),
            mix(
              dot(grad2(i + V2(0, 1), s), f - V2(0, 1)),
              dot(grad2(i + V2(1, 1), s), f - V2(1, 1)),
              u,
            ),
            v,
          ) *
          1.4142;
}

double fbm(V2 p, int s, int oct) {
  double sum = 0, a = .54, norm = 0;
  for (var k = 0; k < oct; k++) {
    sum += a * valueNoise(p, s + k * 0x9e37);
    norm += a;
    p = rot(p * 2.08, .5);
    a *= .5;
  }
  return sum / max(.001, norm);
}

V2 warp(V2 p, int s, double time, double amount) {
  final off = V2(
    fbm(p * 2.5 + V2(time * .17, 3), s, 4),
    fbm(p * 2.5 + V2(8, -time * .13), s + 54, 4),
  );
  return p + (off - V2(.5, .5)) * 2 * amount;
}

double srgbDecode(double v) =>
    v <= .04045 ? v / 12.92 : pow((v + .055) / 1.055, 2.4).toDouble();
double srgbEncode(num n) {
  final v = clamp(n);
  return v <= .0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - .055;
}

V3 oklab(V3 c) {
  final r = srgbDecode(c.x), g = srgbDecode(c.y), b = srgbDecode(c.z);
  final l = pow(.4122214708 * r + .5363325363 * g + .0514459929 * b, 1 / 3),
      m = pow(.2119034982 * r + .6806995451 * g + .1073969566 * b, 1 / 3),
      s = pow(.0883024619 * r + .2817188376 * g + .6299787005 * b, 1 / 3);
  return V3(
    .2104542553 * l + .793617785 * m - .0040720468 * s,
    1.9779984951 * l - 2.428592205 * m + .4505937099 * s,
    .0259040371 * l + .7827717662 * m - .808675766 * s,
  );
}

V3 fromOklab(V3 c) {
  var l = c.x + .3963377774 * c.y + .2158037573 * c.z,
      m = c.x - .1055613458 * c.y - .0638541728 * c.z,
      s = c.x - .0894841775 * c.y - 1.291485548 * c.z;
  l = l * l * l;
  m = m * m * m;
  s = s * s * s;
  return V3(
    srgbEncode(4.0767416621 * l - 3.3077115913 * m + .2309699292 * s),
    srgbEncode(-1.2684380046 * l + 2.6097574011 * m - .3413193965 * s),
    srgbEncode(-.0041960863 * l - .7034186147 * m + 1.707614701 * s),
  );
}

V3 perceptual(V3 a, V3 b, num t) =>
    fromOklab(cmix(oklab(a), oklab(b), clamp(t)));
V3 bilinear(V3 a, V3 b, V3 c, V3 d, num x, num y) =>
    cmix(cmix(a, b, clamp(x)), cmix(c, d, clamp(x)), clamp(y));
V3 hsv(V3 c) {
  final mx = max(c.x, max(c.y, c.z)),
      mn = min(c.x, min(c.y, c.z)),
      dt = mx - mn;
  double h = 0;
  if (dt > 1e-7) {
    if (mx == c.x) {
      h = ((c.y - c.z) / dt + 6) % 6 / 6;
    } else if (mx == c.y) {
      h = ((c.z - c.x) / dt + 2) / 6;
    } else {
      h = ((c.x - c.y) / dt + 4) / 6;
    }
  }
  return V3(h, mx > 0 ? dt / mx : 0, mx);
}

V3 fromHSV(V3 h) {
  final x = fract(h.x) * 6,
      i = x.toInt(),
      f = x - i,
      p = h.z * (1 - h.y),
      q = h.z * (1 - f * h.y),
      t = h.z * (1 - (1 - f) * h.y);
  return switch (i % 6) {
    0 => V3(h.z, t, p),
    1 => V3(q, h.z, p),
    2 => V3(p, h.z, t),
    3 => V3(p, q, h.z),
    4 => V3(t, p, h.z),
    _ => V3(h.z, p, q),
  };
}

V3 satAdjust(V3 c, num f) {
  final lab = oklab(sat(c));
  lab.y *= f;
  lab.z *= f;
  return fromOklab(lab);
}

V3 tex(im.Image? t, V2 uv) {
  if (t == null) return V3(.35, .35, .35);
  final x = clamp(uv.x) * (t.width - 1),
      y = clamp(uv.y) * (t.height - 1),
      xi = x.floor(),
      yi = y.floor();
  V3 at(int a, int b) {
    final p = t.getPixel(a, b);
    return V3(p.r / 255, p.g / 255, p.b / 255);
  }

  return bilinear(
    at(xi, yi),
    at(min(xi + 1, t.width - 1), yi),
    at(xi, min(yi + 1, t.height - 1)),
    at(min(xi + 1, t.width - 1), min(yi + 1, t.height - 1)),
    x - xi,
    y - yi,
  );
}

class State {
  final int seed;
  final double time, width, height;
  final List<V3> p;
  final List<double> k;
  final im.Image? blur1, blur2;
  late final paletteLab = p.map(oklab).toList();
  late final hardAccent = perceptual(perceptual(p[1], p[2], .5), p[3], k[3]);
  late final hardLabs = [
    paletteLab[0],
    paletteLab[1],
    paletteLab[2],
    oklab(hardAccent),
    paletteLab[4],
  ];
  late final mistAnchors = List.generate(5, (i) {
    final angle =
        TAU * (i + .18 * rnd(seed ^ (i * 811))) / 5 +
        time * .008 * (i % 2 != 0 ? 1 : -1);
    final radius = (i == 4 ? .10 : .43) * max(.1, k[2]);
    return V2(
      radius * cos(angle) * (i == 4 ? 1 : width / height * .65),
      radius * sin(angle),
    );
  });
  late final mistSigma = List.generate(
    5,
    (i) => (i == 4 ? .48 : .42) * max(.35, k[2]) * k[4],
  );
  State(
    this.seed,
    this.time,
    this.width,
    this.height,
    this.p,
    this.k,
    this.blur1,
    this.blur2,
  );
}

// The hash namespace uses the renamed modes. Every range is the approved v7 range.
const parameterRanges = <String, List<(String, double, double)>>{
  'mist': [
    ('texture_mix', 0, .10),
    ('warp_strength', 0, .20),
    ('field_size', .50, .75),
    ('detail_suppression', 0, 1),
    ('palette_softness', .55, 1.45),
  ],
  'fusionSoft': [
    ('old_new_mix', 0, .80),
    ('flow_frequency', 3, 7),
    ('lightwave_strength', 0, .50),
    ('swirl_strength', 0, 1),
    ('color_binding', 0, .80),
  ],
  'fusionHard': [
    ('old_new_mix', 0, 1),
    ('nonperiodic_warp', 0, .48),
    ('transition_softness', .60, 1.40),
    ('accent_weight', 0, 1),
    ('large_scale_mix', 0, 1),
  ],
  'lightFlow': [
    ('flow_gain', .85, 1.15),
    ('micro_ridge', 0, .015),
    ('palette_fog', 0, .165),
    ('ridge_width', .5, 1.5),
    ('ridge_contrast', .5, 1.5),
  ],
};
List<double> seedParameters(String mode, String seed) => [
  for (final spec in parameterRanges[mode]!)
    mix(
      spec.$2,
      spec.$3,
      rnd(seedHash('FlowBenchSeedV7|$seed|$mode|${spec.$1}')),
    ),
];
im.Image boxBlur(im.Image image, int radius) {
  final w = image.width, h = image.height;
  final src = Float64List(w * h * 3),
      tmp = Float64List(w * h * 3),
      out = im.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = image.getPixel(x, y), i = (y * w + x) * 3;
      src[i] = p.r.toDouble();
      src[i + 1] = p.g.toDouble();
      src[i + 2] = p.b.toDouble();
    }
  }
  for (var y = 0; y < h; y++) {
    for (var c = 0; c < 3; c++) {
      double sum = 0;
      for (var k = -radius; k <= radius; k++) {
        sum += src[(y * w + k.clamp(0, w - 1)) * 3 + c];
      }
      for (var x = 0; x < w; x++) {
        tmp[(y * w + x) * 3 + c] = sum / (radius * 2 + 1);
        sum +=
            src[(y * w + (x + radius + 1).clamp(0, w - 1)) * 3 + c] -
            src[(y * w + (x - radius).clamp(0, w - 1)) * 3 + c];
      }
    }
  }
  final values = Float64List(w * h * 3);
  for (var x = 0; x < w; x++) {
    for (var c = 0; c < 3; c++) {
      double sum = 0;
      for (var k = -radius; k <= radius; k++) {
        sum += tmp[(k.clamp(0, h - 1) * w + x) * 3 + c];
      }
      for (var y = 0; y < h; y++) {
        values[(y * w + x) * 3 + c] = sum / (radius * 2 + 1);
        sum +=
            tmp[((y + radius + 1).clamp(0, h - 1) * w + x) * 3 + c] -
            tmp[((y - radius).clamp(0, h - 1) * w + x) * 3 + c];
      }
    }
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 3;
      out.setPixelRgb(
        x,
        y,
        values[i].round(),
        values[i + 1].round(),
        values[i + 2].round(),
      );
    }
  }
  return out;
}

/// Isolate entry: bounded 660px working grid, output reconstructed by Flutter bicubic.
Map<String, Object> renderSeedBackground(Map<String, Object?> args) {
  _gradients.clear();
  final mode = args['mode'] as String, seed = args['seed'] as String;
  final width = args['width'] as double, height = args['height'] as double;
  final factor = 660 / max(width, height),
      w = max(1, (width * min(1, factor)).round()),
      h = max(1, (height * min(1, factor)).round());
  final colors = args['palette'] as List<int>;
  final p = [
    for (final c in colors)
      satAdjust(
        V3(((c >> 16) & 255) / 255, ((c >> 8) & 255) / 255, (c & 255) / 255),
        1.12,
      ),
  ];
  final prepared = args['preparedCover'] as Map<String, Object>?;
  im.Image? blur1, blur2;
  if (prepared != null) {
    im.Image load(String key) => im.Image.fromBytes(
      width: prepared['width'] as int,
      height: prepared['height'] as int,
      bytes: (prepared[key] as Uint8List).buffer,
      numChannels: 4,
    );
    blur1 = load('blur1');
    blur2 = load('blur2');
  } else if (mode == 'mist' && args['cover'] != null) {
    final prepared = prepareMistCover(args);
    blur1 = im.Image.fromBytes(
      width: prepared['width'] as int,
      height: prepared['height'] as int,
      bytes: (prepared['blur1'] as Uint8List).buffer,
      numChannels: 4,
    );
    blur2 = im.Image.fromBytes(
      width: prepared['width'] as int,
      height: prepared['height'] as int,
      bytes: (prepared['blur2'] as Uint8List).buffer,
      numChannels: 4,
    );
  }
  final hash = seedHash(seed),
      st = State(
        hash,
        (hash % 30000) / 197,
        width,
        height,
        p,
        seedParameters(mode, seed),
        blur1,
        blur2,
      );
  final bytes = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final uv = V2((x + .5) / w, (y + .5) / h);
      final c = sat(switch (mode) {
        'mist' => shadeMist(st, uv),
        'fusionSoft' => shadeFusionSoft(st, uv),
        'fusionHard' => shadeFusionHard(st, uv),
        _ => shadeLightFlow(st, uv),
      });
      final d = (rnd(x * 374761393 ^ y * 668265263 ^ hash) - .5) / 255,
          i = (y * w + x) * 4;
      bytes[i] = (clamp(c.x + d) * 255).round();
      bytes[i + 1] = (clamp(c.y + d) * 255).round();
      bytes[i + 2] = (clamp(c.z + d) * 255).round();
      bytes[i + 3] = 255;
    }
  }
  return {'bytes': bytes, 'width': w, 'height': h};
}

V3 mistField(State st, V2 uv) {
  final textureMix = st.k[0], warpStrength = st.k[1];
  final detailSuppression = st.k[3];
  final aspect = st.width / st.height;
  var xy = uv - V2(.5, .5);
  xy.x *= aspect;
  var coarse = V2(
    fbm(xy * 1.9 + V2(st.time * .011, 8.3), st.seed ^ 0x51, 4),
    fbm(xy * 1.9 + V2(2.7, -st.time * .012), st.seed ^ 0x9a, 4),
  );
  var fine = V2(
    fbm(xy * 3.6 + V2(1.6, st.time * .01), st.seed ^ 0x19, 3),
    fbm(xy * 3.6 + V2(7.4, 1.2), st.seed ^ 0x31, 3),
  );
  var displaced =
      xy +
      (coarse - V2(.5, .5)) * (.54 * warpStrength) +
      (fine - V2(.5, .5)) * (.13 * warpStrength);
  final weight = List<double>.filled(5, 0);
  double total = 0;
  for (int i = 0; i < 5; i++) {
    final anchor = st.mistAnchors[i];
    var d = displaced - anchor;
    final sigma = st.mistSigma[i];
    weight[i] = exp(-.85 * dot(d, d) / (sigma * sigma)) + .035;
    total += weight[i];
  }
  var lab = V3(0, 0, 0);
  for (int i = 0; i < 5; i++) lab += st.paletteLab[i] * (weight[i] / total);
  var field = fromOklab(lab);
  var q = rot(displaced, st.time * .018 + .3);
  q.x /= aspect;
  q = q * .49 + V2(.5, .5);

  var image = cmix(tex(st.blur1, q), tex(st.blur2, q), detailSuppression);
  var c = perceptual(field, image, textureMix);
  var sheen = fbm(displaced * 1.7 + V2(3.2, 5.1), st.seed ^ 0x777, 3);
  c += V3(1, 1, 1) * ((sheen - .5) * (.065 - .023 * detailSuppression));
  return sat(satAdjust(c, 1.09));
}

V3 shadeMist(State st, V2 uv) {
  return mistField(st, uv);
}

V3 fusionHardLegacy(State st, V2 uv) {
  var p = uv - V2(.5, .5);
  var aspect = st.width / st.height;
  p.y /= aspect;
  var angle =
      (perlin(V2(st.time * .1, p.x * p.y), st.seed ^ 0x5577) - .5) * TAU + PI;
  p = rot(p, angle);
  p.y *= aspect;
  var speed = st.time * 2.0;
  p.x += sin(p.y * 5.0 + speed) / 30.0;
  p.y += sin(p.x * 7.5 + speed) / 15.0;
  var x = smooth(-.3, .2, rot(p, -0.0872665).x), y = smooth(.5, -.3, p.y);
  return sat(bilinear(st.p[0], st.p[1], st.p[2], st.p[3], x, y));
}

V3 fusionHardField(State st, V2 uv) {
  final structure = st.k[0];
  if (structure <= 0.0) return fusionHardLegacy(st, uv);
  final warpStrength = st.k[1];
  final transitionSoftness = st.k[2];
  final accentWeight = st.k[3];
  final cloudMix = st.k[4];
  final aspect = st.width / st.height;
  var coord = uv - V2(.5, .5);
  coord.x *= aspect;
  final t = st.time * .013;

  var drift = V2(
    fbm(coord * 1.65 + V2(2.1 + t, 4.4), st.seed ^ 0x43d2, 4),
    fbm(coord * 1.65 + V2(7.9, -t - 3.1), st.seed ^ 0x7b5a, 4),
  );
  var q = coord + (drift - V2(.5, .5)) * (.85 * warpStrength);

  var accent = st.hardAccent;
  var wide = max(.25, transitionSoftness);
  var x = smooth(
    -.48 * wide,
    .48 * wide,
    q.x + .09 * (fbm(q * 1.35 + V2(1.7, t), st.seed ^ 0x91d7, 3) - .5),
  );
  var y = smooth(
    -.38 * wide,
    .38 * wide,
    q.y + .08 * (fbm(q * 1.45 + V2(-t, 3.6), st.seed ^ 0x6157, 3) - .5),
  );
  var gradient = bilinear(st.p[0], st.p[1], st.p[2], accent, x, y);

  double sum = 0;
  var lab = V3(0, 0, 0);
  for (int i = 0; i < 5; i++) {
    final key = st.seed ^ (i + 1) * 0x9e3779b9;
    var ax = (rnd(key ^ 0x221) - .5) * aspect * 1.45;
    var ay = (rnd(key ^ 0x733) - .5) * 1.10;
    var delta = q - V2(ax, ay);
    var stretch = .78 + .55 * rnd(key ^ 0x417);
    var sigma = (.45 + .15 * (i % 2).toDouble()) * wide;
    var d2 =
        (delta.x * delta.x) / (sigma * sigma * stretch) +
        (delta.y * delta.y) * stretch / (sigma * sigma);
    var w = exp(-.70 * d2) + .035;
    if (i == 3) w *= .35 + .65 * accentWeight;
    lab += st.hardLabs[i] * w;
    sum += w;
  }
  var cloud = fromOklab(lab / max(sum, 1e-6));
  var clean = perceptual(gradient, cloud, cloudMix);
  if (structure >= 1.0) return sat(clean);
  return sat(perceptual(fusionHardLegacy(st, uv), clean, structure));
}

V3 shadeFusionHard(State st, V2 uv) {
  return fusionHardField(st, uv);
}

V3 fusionSoftLegacy(State st, V2 uv) {
  var p = uv - V2(.5, .5);
  p.y *= st.height / st.width;
  var degree = perlin(V2(st.time * .11, p.x * p.y * 2), st.seed);
  p = rot(p, (degree - .5) * TAU + PI);
  p.x += sin(p.y * 5 + st.time * .75) / 25.0;
  p.y += sin(p.x * 7.5 + st.time * .75) / 12.5;
  p = warp(p * 1.2, st.seed, st.time, .105);
  var c = bilinear(
    st.p[0],
    st.p[1],
    st.p[2],
    st.p[3],
    smooth(-.35, .32, rot(p, -.09).x),
    smooth(.37, -.45, p.y),
  );
  var h = hsv(c);
  var w = uv - V2(.5, .5);
  var mo = sin(w.y * 4 + st.time * .34) + cos(w.x * 3.5 - st.time * .22);
  var wave = .5 + .5 * sin(mo + cos((w.x + w.y) * 3.1) + st.time * .1);
  h.x = fract(h.x + .016 * wave);
  h.y *= .91 + .12 * wave;
  h.z *= .89 + .12 * wave;
  return fromHSV(h);
}

V3 fusionSoftCore(
  State st,
  V2 uv,
  double foldStrength,
  double freq,
  double lightStrength,
) {
  var aspect = st.width / st.height;
  var p = uv - V2(.5, .5);
  p.y /= aspect;
  var rotateNoise = perlin(V2(st.time * .09, p.x * p.y * 2.0), st.seed);
  p = rot(p, PI + (rotateNoise - .5) * TAU * (.38 + .42 * foldStrength));
  p.x += sin(p.y * freq + st.time * .72) * (.015 + .065 * foldStrength);
  p.y += sin(p.x * freq * 1.4 - st.time * .59) * (.02 + .09 * foldStrength);
  p = warp(p * 1.2 + V2(.3, -.2), st.seed, st.time, .15 * foldStrength);
  var x = smooth(-.42, .36, rot(p, -.14).x), y = smooth(.48, -.42, p.y);
  var color = bilinear(st.p[0], st.p[1], st.p[2], st.p[3], x, y);

  var w = uv - V2(.5, .5);
  var sine = sin(
    w.x * freq * .9 + st.time * .24 + 2.0 * sin(w.y * 2.2 - st.time * .13),
  );
  var fold = perlin(p * 4.3 + V2(st.time * .027, 5.4), st.seed ^ 0x665);
  var h = hsv(color);
  h.x = fract(h.x + lightStrength * .010 * sine);
  h.y = clamp(h.y * (1.0 - lightStrength * .17 * (.5 + .5 * sine)));
  h.z = clamp(h.z * (1.0 - lightStrength * .24 + lightStrength * .31 * fold));
  return sat(fromHSV(h));
}

V3 fusionSoftField(State st, V2 uv) {
  final oldNewMix = st.k[0], freq = st.k[1], lightwave = st.k[2];
  final swirl = st.k[3], colorBinding = st.k[4];

  if (oldNewMix == 0.0 && swirl == 0.0 && colorBinding == 0.0)
    return fusionSoftLegacy(st, uv);
  var uv2 = uv;
  if (swirl > 0) {
    var p = uv - V2(.5, .5);
    var a =
        swirl * .48 * sin(3.5 * length(p) + st.time * .034) +
        swirl *
            .31 *
            (perlin(p * 2.3 + V2(2.5, st.time * .01), st.seed ^ 0x89) - .5);
    uv2 = rot(p, a) + V2(.5, .5);
  }
  var old = fusionSoftLegacy(st, uv2);
  if (oldNewMix == 0.0 && colorBinding == 0.0) return old;
  var newer = fusionSoftCore(st, uv2, .6, freq, lightwave);
  var c = cmix(old, newer, oldNewMix);
  if (colorBinding > 0.0) {
    var a = smooth(-.38, .42, uv2.x - .5), b = smooth(-.3, .5, uv2.y - .5);
    var constrained = bilinear(st.p[0], st.p[1], st.p[2], st.p[3], a, b);
    c = perceptual(c, constrained, colorBinding * .55);
  }
  return sat(c);
}

V3 shadeFusionSoft(State st, V2 uv) {
  return fusionSoftField(st, uv);
}

V3 lightFlowLegacy(State st, V2 uv) {
  var p = uv - V2(.5, .5);
  var aspect = st.width / st.height;
  p.y /= aspect;
  var angle = (perlin(V2(st.time * .1, p.x * p.y), st.seed) - .5) * TAU + PI;
  p = rot(p, angle);
  p.y *= aspect;
  p.x += sin(p.y * 5.0 + st.time * 2.0) / 30.0;
  p.y += sin(p.x * 7.5 + st.time * 2.0) / 15.0;
  var x = smooth(-.3, .2, rot(p, -.0873).x);
  var y = smooth(.5, -.3, p.y);
  var v = bilinear(st.p[0], st.p[1], st.p[2], st.p[3], x, y);
  var fine = fbm(p * 3.5 + V2(st.time * .08, 0), st.seed ^ 0x789f, 3);
  return cmix(v, st.p[4], .11 * smooth(.45, .8, fine));
}

V3 lightFlowField(State st, V2 uv) {
  final flowGain = st.k[0], microRidge = st.k[1], paletteFog = st.k[2];
  final ridgeWidth = st.k[3], ridgeContrast = st.k[4];
  if (flowGain == 1.0 && microRidge == 0.0 && paletteFog == .11)
    return lightFlowLegacy(st, uv);
  var p = uv - V2(.5, .5);
  var aspect = st.width / st.height;
  p.y /= aspect;
  var angle = (perlin(V2(st.time * .1, p.x * p.y), st.seed) - .5) * TAU + PI;
  p = rot(p, angle);
  p.y *= aspect;
  p.x += (sin(p.y * 5.0 + st.time * 2.0) / 30.0) * flowGain;
  p.y += (sin(p.x * 7.5 + st.time * 2.0) / 15.0) * flowGain;
  var x = smooth(-.3, .2, rot(p, -.0873).x), y = smooth(.5, -.3, p.y);
  var c = bilinear(st.p[0], st.p[1], st.p[2], st.p[3], x, y);
  var fine = fbm(p * 3.5 + V2(st.time * .08, 0), st.seed ^ 0x789f, 3);
  c = cmix(c, st.p[4], paletteFog * smooth(.45, .8, fine));
  if (microRidge > 0) {
    var q = p.x * .73 + p.y * .68;
    var v = sin(5.5 * q + .72 * sin(p.y * 2.9 + st.time * .045));
    var ridge = exp(-12.0 * v * v / (ridgeWidth * ridgeWidth));
    c += V3(1, 1, 1) * (microRidge * ridgeContrast * ridge);
  }
  return sat(c);
}

V3 shadeLightFlow(State st, V2 uv) {
  return lightFlowField(st, uv);
}

/// Identical resize and box filters, separated so changing seed reuses artwork preprocessing.
Map<String, Object> prepareMistCover(Map<String, Object?> args) {
  late im.Image cover;
  if (args['cover'] != null) {
    cover = im.Image.fromBytes(
      width: args['coverWidth'] as int,
      height: args['coverHeight'] as int,
      bytes: (args['cover'] as Uint8List).buffer,
      numChannels: 4,
    );
    cover = im.copyResize(
      cover,
      width: cover.width >= cover.height ? 512 : null,
      height: cover.height > cover.width ? 512 : null,
      interpolation: im.Interpolation.cubic,
    );
  }

  return {
    'width': cover.width,
    'height': cover.height,
    'blur1': boxBlur(cover, 7).getBytes(order: im.ChannelOrder.rgba),
    'blur2': boxBlur(cover, 20).getBytes(order: im.ChannelOrder.rgba),
  };
}
