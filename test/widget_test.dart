import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:periodify/main.dart';
import 'package:periodify/model.dart';
import 'package:periodify/timetable_layout.dart';
import 'package:periodify/windows_title_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Today returns to the current date from another week', (
    tester,
  ) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final nextWeek = DateUtils.addDaysToDate(today, 7);
    final snapshot = Snapshot(
      lessons: [
        Lesson(date: dayKey(today), period: 'P1', order: 0, subject: 'Science'),
        Lesson(
          date: dayKey(nextWeek),
          period: 'P1',
          order: 0,
          subject: 'Music',
        ),
      ],
      week: dayKey(weekStart(today)),
      scrapedAt: today,
    );
    SharedPreferences.setMockInitialValues({'snapshot': snapshot.encode()});
    tester.view.physicalSize = const Size(390, 1050);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const PeriodifyApp());
    await tester.pumpAndSettle();

    expect(find.text('Science'), findsOneWidget);
    await tester.tap(find.byTooltip('Next week'));
    await tester.pumpAndSettle();
    expect(find.text('Science'), findsNothing);
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(find.text('Science'), findsOneWidget);
    expect(find.text('Music'), findsNothing);
  });

  testWidgets('layout choice is saved and restored', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const PeriodifyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Focus'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Focus'));
    await tester.pumpAndSettle();

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('timetableLayout'), 'focus');
    expect(
      tester
          .widget<TimetableLayoutPicker>(find.byType(TimetableLayoutPicker))
          .selected,
      TimetableLayout.focus,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const PeriodifyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TimetableLayoutPicker>(find.byType(TimetableLayoutPicker))
          .selected,
      TimetableLayout.focus,
    );
    await tester.pumpWidget(const SizedBox());
  });

  for (final width in [320.0, 1040.0]) {
    testWidgets('each lesson layout fits at $width pixels', (tester) async {
      tester.view.physicalSize = Size(width, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final day = DateUtils.dateOnly(DateTime.now());
      final lessons = [
        Lesson(
          date: dayKey(day),
          period: 'P1',
          order: 0,
          subject: 'Computer science',
        ),
        Lesson(
          date: dayKey(day),
          period: 'P2',
          order: 1,
          subject: 'Music theory',
        ),
      ];
      for (final layout in TimetableLayout.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  TimetableLessons(
                    layout: layout,
                    lessons: lessons,
                    date: day,
                    periodFor: (_) => null,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Computer science'), findsOneWidget);
        expect(find.text('Music theory'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: layout.label);
      }
    });
  }

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
    expect(find.text('Periods'), findsNothing);
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

  testWidgets('adds a named period and matches it to a Bromcom lesson', (
    tester,
  ) async {
    final today = DateTime.now();
    final snapshot = Snapshot(
      lessons: [
        Lesson(date: dayKey(today), period: 'P7', order: 0, subject: 'Science'),
      ],
      week: dayKey(weekStart(today)),
      scrapedAt: today,
    );
    SharedPreferences.setMockInitialValues({
      'snapshot': snapshot.encode(),
      'bells': '{"P1":"08:30-09:00"}',
    });
    tester.view.physicalSize = const Size(360, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const PeriodifyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Timetable'));
    await tester.pumpAndSettle();
    expect(find.text('08:30–09:00 · Bromcom P1'), findsOneWidget);
    await tester.tap(find.text('Add period'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'Afternoon tutorial',
    );
    await tester.enterText(find.byType(TextFormField).last, 'Period 7');
    await tester.tap(find.text('Save period'));
    await tester.pumpAndSettle();
    expect(find.text('Afternoon tutorial'), findsOneWidget);
    expect(find.text('09:00–10:00 · Bromcom Period 7'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Timetable'),
      ),
    );
    await tester.pumpAndSettle();
    final matched = find.text('Afternoon tutorial · 09:00–10:00');
    await tester.scrollUntilVisible(matched, 150, maxScrolls: 6);
    expect(matched, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
