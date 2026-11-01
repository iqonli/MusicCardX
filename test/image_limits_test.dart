import 'package:flutter_test/flutter_test.dart';
import 'package:musiccardx/renderer.dart';

void main() {
  test('output limits allow exact boundaries and warn above either limit', () {
    expect(exceedsOutputLimits(32768, 3051), isFalse);
    expect(exceedsOutputLimits(32768, 3052), isTrue);
    expect(exceedsOutputLimits(10000, 10000), isFalse);
    expect(exceedsOutputLimits(32769, 1), isTrue);
    expect(exceedsOutputLimits(1, 32769), isTrue);
    expect(exceedsOutputLimits(10001, 10000), isTrue);
  });
}
