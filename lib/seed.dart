class OriginalRandom {
  late int state;
  OriginalRandom(String text) {
    int h = 2166136261;
    for (final c in text.codeUnits) {
      h = ((h ^ c) * 16777619) & 0xffffffff;
    }
    h ^= h >>> 13;
    h = (h * 0x5bd1e995) & 0xffffffff;
    h ^= h >>> 15;
    state = h == 0 ? 0x9e3779b9 : h;
  }
  double nextDouble() {
    state = (state * 1664525 + 1013904223) & 0xffffffff;
    return state / 4294967296;
  }

  int nextInt(int max) => (nextDouble() * max).floor();
}
