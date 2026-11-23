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
  test('homework maps rendered columns and preserves submission status', () {
    final result = parseHomework(
      '<table id="HomeworkTable"><tbody><tr><td>04/01/2027</td><td>Homework</td><td>Read chapter</td><td>Group</td><td>English</td><td>Example</td><td>Not Due</td><td>Offline</td><td></td><td></td></tr></tbody></table>',
    );
    expect(result.single['title'], 'Read chapter');
    expect(result.single['status'], 'Not Due');
    expect(() => parseHomework('<table></table>'), throwsFormatException);
  });
}
