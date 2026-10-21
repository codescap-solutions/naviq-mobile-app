import 'dart:io';

import 'package:child_track/core/constants/app_build_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppBuildInfo matches pubspec.yaml version', () {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'));
    expect(line.replaceFirst('version:', '').trim(), '${AppBuildInfo.version}+${AppBuildInfo.build}');
  });
}
