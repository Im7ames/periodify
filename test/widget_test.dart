import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:periodify/main.dart';
import 'package:periodify/windows_title_bar.dart';
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
      await tester.tap(find.text('Appearance'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('dark'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  for (final (width, labels) in [(360.0, false), (1280.0, true)]) {
    testWidgets('Windows title bar navigation fits at $width pixels', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = Size(width, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const channel = MethodChannel('window_manager');
      final messages = tester.binding.defaultBinaryMessenger;
      final calls = <String>[];
      messages.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return call.method == 'isMaximized' ? false : null;
      });
      addTearDown(() => messages.setMockMethodCallHandler(channel, null));

      await tester.pumpWidget(const PeriodifyApp());
      await tester.pumpAndSettle();
      expect(find.byType(WindowsTitleBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
      expect(tester.takeException(), isNull);

      Finder destination(String name) => find.descendant(
        of: find.byType(WindowsTitleBar),
        matching: labels ? find.text(name) : find.byTooltip(name),
      );

      await tester.tap(destination('Watch'));
      await tester.pumpAndSettle();
      expect(find.text('Sync saved timetable'), findsOneWidget);
      await tester.tap(destination('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Appearance'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('dark'));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(WindowsTitleBar))).brightness,
        Brightness.dark,
      );
      await tester.tap(destination('Timetable'));
      await tester.pumpAndSettle();
      expect(find.text('Scrape'), findsOneWidget);

      for (final label in ['Minimize', 'Maximize', 'Close']) {
        await tester.tap(find.byTooltip(label));
      }
      expect(calls, containsAllInOrder(['minimize', 'maximize', 'close']));
      expect(tester.takeException(), isNull);
    }, variant: const TargetPlatformVariant({TargetPlatform.windows}));
  }

  testWidgets('opens timetable settings and persists the selected rotation', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const PeriodifyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Bell times'), findsNothing);
    await tester.tap(find.widgetWithText(ListTile, 'Timetable'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No repeat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Every 2 weeks').last);
    await tester.pumpAndSettle();
    expect(find.text('Every 2 weeks'), findsOneWidget);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getInt('repeatWeeks'), 2);
  });
}
