import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:periodify/updates.dart';

void main() {
  test('release versions are compared numerically', () {
    expect(compareVersions('0.1.10', '0.1.8'), isPositive);
    expect(compareVersions('0.2.1', '1.0.0'), isNegative);
    expect(compareVersions('1.0.0', '1.0.0'), 0);
  });

  test('Windows updates require an exact repository download and checksum', () {
    final asset = <String, Object>{
      'name': 'periodify-windows-unsigned.exe',
      'url': 'https://github.com/Im7ames/periodify/releases/download/v0.1.9/periodify-windows-unsigned.exe',
      'sha256': 'a' * 64,
      'size': 6,
    };
    String manifest() => jsonEncode({
      'schema': 1,
      'version': '0.1.9',
      'assets': [asset],
    });
    expect(
      AppUpdate.fromManifest(
        '0.1.9',
        manifest(),
        TargetPlatform.windows,
      )?.bytes,
      6,
    );
    expect(
      AppUpdate.fromManifest('0.1.9', manifest(), TargetPlatform.android),
      isNull,
    );
    asset['url'] = 'https://example.com/periodify-windows-unsigned.exe';
    expect(
      AppUpdate.fromManifest('0.1.9', manifest(), TargetPlatform.windows),
      isNull,
    );
  });
}
