import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:periodify/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets('empty state and navigation fit at $width pixels', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = Size(width, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const PeriodifyApp());
      await tester.pumpAndSettle();
      expect(find.text('Scrape'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Watch'));
      await tester.pumpAndSettle();
      expect(find.text('Sync saved timetable'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Appearance'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('dark'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
