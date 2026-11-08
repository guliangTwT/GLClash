import 'package:gl_clash/common/package.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compareVersions never throws on a malformed tag', () {
    for (final version in [
      'v1.0.0+99999999999999999999999',
      '1.0.0+000000000000000000000001',
      'v1.0.0-0',
      'v1.0.0-alpha.0',
      '1.0.0+build.7',
      'V1.0.0.0.0',
      '1..2',
      'v1.0.0-',
      '  1.0.0  ',
      '1.0.0+',
      '',
      'v',
    ]) {
      expect(
        () => compareVersions(version, '1.0.0'),
        returnsNormally,
        reason: 'compareVersions threw on "$version"',
      );
      expect(
        () => compareVersions('1.0.0', version),
        returnsNormally,
        reason: 'compareVersions threw on "$version" as the second argument',
      );
    }
  });
}
