import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zmusic/ui/theme.dart';

void main() {
  test('app themes are built with the expected brightness', () {
    expect(AppTheme.light().brightness, Brightness.light);
    expect(AppTheme.dark().brightness, Brightness.dark);
  });
}
