import 'package:flutter_test/flutter_test.dart';
import 'package:periodify/model.dart';

String fixture({String start = '12-27-2026', String label = 'Monday'}) =>
    '''
<select id="WeekStartDate"><option selected value="$start">Week</option></select>
<table id="Timetable"><thead><tr><th>$label</th></tr></thead><tbody>
<tr><td><div id="sp-timetable-period&gt;P1&lt;/div&gt;&lt;div id=" title="Test group">Test group</div><div id="sp-timetable-room">R1</div><div class="sp-text">Mathematics</div><div id="sp-timetable-teacher">Example Teacher</div></td></tr>
<tr><td id="sp-timetable-period"><div>BR</div></td></tr>
</tbody></table>''';
void main() {
  test(
    'handles malformed period markup without confusing it with class name',
    () {
      final result = parseTimetable(fixture());
      expect(result.lessons.single.period, 'P1');
      expect(result.lessons.single.group, 'Test group');
      expect(result.lessons.single.subject, 'Mathematics');
      expect(result.lessons.single.room, 'R1');
      expect(result.lessons.single.date, '2026-12-28');
    },
  );
  test('rolls dates across year boundary using weekday headings', () {
    expect(
      parseTimetable(fixture(label: 'Friday')).lessons.single.date,
      '2027-01-01',
    );
  });
  test(
    'rejects login, loading and changed layouts instead of replacing snapshot',
    () {
      expect(() => parseTimetable('<form>Login</form>'), throwsFormatException);
      expect(
        () => parseTimetable(fixture().replaceAll('<th>Monday</th>', '')),
        throwsFormatException,
      );
    },
  );
  test('snapshot round-trips and rejects unknown schema', () {
    final result = parseTimetable(fixture());
    expect(Snapshot.decode(result.encode()).lessons.single.period, 'P1');
    expect(() => Snapshot.decode('{"schema":2}'), throwsFormatException);
  });
  test('Bromcom lesson colours survive snapshot export', () {
    final rendered = fixture().replaceFirst(
      '<td>',
      '<td data-periodify-color="#7DB4D9">',
    );
    final lesson = Snapshot.decode(parseTimetable(rendered).encode())
        .lessons
        .single;
    expect(lesson.color, '#7db4d9');
    expect(parseTimetable(fixture()).lessons.single.color, isNull);
  });
  test('rotations keep exact dates and repeat the selected teaching weeks', () {
    final weekA = parseTimetable(fixture());
    final weekB = parseTimetable(
      fixture(start: '01-03-2027').replaceAll('Mathematics', 'English'),
    );
    final later =
        parseTimetable(
          fixture(start: '01-24-2027').replaceAll('Mathematics', 'Science'),
        ).withHomework([
          {'title': 'Read chapter'},
        ], DateTime.utc(2027, 1, 25));
    final snapshot = Snapshot.decode(
      mergeTimetableWeeks(later, [
        weekA,
        weekB,
      ], ScheduleRotation(2, weekA.teachingWeek)).encode(),
    );

    expect(weekA.teachingWeek, DateTime.utc(2026, 12, 28));
    expect(
      snapshot.lessonsFor(DateTime(2027, 1, 11)).single.subject,
      'Mathematics',
    );
    expect(
      snapshot.lessonsFor(DateTime(2027, 1, 18)).single.subject,
      'English',
    );
    expect(
      snapshot.lessonsFor(DateTime(2027, 1, 25)).single.subject,
      'Science',
    );
    expect(snapshot.lessonsFor(DateTime(2027, 1, 26)), isEmpty);
    expect(
      snapshot.lessonsFor(DateTime(2026, 12, 21)).single.subject,
      'English',
    );
    expect(snapshot.homework.single['title'], 'Read chapter');
    expect(later.lessonsFor(DateTime(2027, 2, 1)), isEmpty);
  });
  test('homework maps rendered columns and preserves submission status', () {
    final result = parseHomework(
      '<table id="HomeworkTable"><tbody><tr><td>04/01/2027</td><td>Homework</td><td>Read chapter</td><td>Group</td><td>English</td><td>Example</td><td>Not Due</td><td>Offline</td><td></td><td></td></tr></tbody></table>',
    );
    expect(result.single['title'], 'Read chapter');
    expect(result.single['status'], 'Not Due');
    expect(() => parseHomework('<table></table>'), throwsFormatException);
  });
}
