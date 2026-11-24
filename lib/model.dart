import 'dart:convert';

import 'package:html/parser.dart' as html;

String dayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

DateTime weekStart(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day - date.weekday + 1);

class ScheduleRotation {
  const ScheduleRotation(this.weeks, this.start);

  static const maxWeeks = 12;
  final int weeks;
  final DateTime start;

  static String label(int index) => 'Week ${String.fromCharCode(65 + index)}';

  int indexFor(DateTime date) =>
      (weekStart(date).difference(weekStart(start)).inDays ~/ 7) % weeks;

  DateTime sourceDay(DateTime date) =>
      weekStart(start)
          .add(Duration(days: indexFor(date) * 7 + date.weekday - 1));

  Map<String, Object> toJson() => {'weeks': weeks, 'start': dayKey(start)};

  static ScheduleRotation? fromJson(Object? value) {
    if (value == null) return null;
    if (value case {'weeks': final int weeks, 'start': final String start}
        when weeks > 0 && weeks <= maxWeeks) {
      return ScheduleRotation(weeks, weekStart(DateTime.parse(start)));
    }
    throw const FormatException('Invalid schedule rotation.');
  }
}

class Lesson {
  const Lesson({
    required this.date,
    required this.period,
    required this.subject,
    this.room = '',
    this.teacher = '',
    this.group = '',
    this.color,
    required this.order,
  });
  final String date, period, subject, room, teacher, group;
  final String? color;
  final int order;
  Map<String, dynamic> toJson() => {
    'date': date,
    'period': period,
    'subject': subject,
    'room': room,
    'teacher': teacher,
    'group': group,
    if (color != null) 'color': color,
    'order': order,
  };
  factory Lesson.fromJson(Map<String, dynamic> j) => Lesson(
    date: j['date'] as String,
    period: j['period'] as String,
    subject: j['subject'] as String,
    room: j['room'] as String? ?? '',
    teacher: j['teacher'] as String? ?? '',
    group: j['group'] as String? ?? '',
    color: _lessonColor(j['color'] as String?),
    order: j['order'] as int,
  );
}

String? _lessonColor(String? value) {
  if (value == null) return null;
  final normalized = value.toLowerCase().trim();
  return RegExp(r'^#[0-9a-f]{6}$').hasMatch(normalized) ? normalized : null;
}

class Snapshot {
  const Snapshot({
    required this.lessons,
    required this.scrapedAt,
    required this.week,
    this.school = '',
    this.homework = const [],
    this.homeworkAt,
    this.rotation,
  });
  final List<Lesson> lessons;
  final DateTime scrapedAt;
  final String week, school;
  final List<Map<String, String>> homework;
  final DateTime? homeworkAt;
  final ScheduleRotation? rotation;

  // Bromcom may label a teaching week by the preceding Sunday.
  DateTime get teachingWeek {
    final portalDate = DateTime.parse(week);
    return DateTime.utc(
      portalDate.year,
      portalDate.month,
      portalDate.day + (DateTime.monday - portalDate.weekday) % 7,
    );
  }

  bool hasWeek(DateTime date) {
    final start = weekStart(date);
    final first = dayKey(start);
    final last = dayKey(start.add(const Duration(days: 6)));
    return lessons.any(
      (lesson) =>
          lesson.date.compareTo(first) >= 0 && lesson.date.compareTo(last) <= 0,
    );
  }

  List<Lesson> lessonsFor(DateTime date) {
    final cycle = rotation;
    final source = cycle != null && !hasWeek(date)
        ? cycle.sourceDay(date)
        : date;
    final key = dayKey(source);
    return lessons.where((lesson) => lesson.date == key).toList();
  }

  Snapshot withRotation(ScheduleRotation? value) => Snapshot(
    lessons: lessons,
    scrapedAt: scrapedAt,
    week: week,
    school: school,
    homework: homework,
    homeworkAt: homeworkAt,
    rotation: value,
  );

  Snapshot withHomework(List<Map<String, String>> items, DateTime time) =>
      Snapshot(
        lessons: lessons,
        scrapedAt: scrapedAt,
        week: week,
        school: school,
        homework: items,
        homeworkAt: time,
        rotation: rotation,
      );

  String encode() => jsonEncode({
    'schema': 1,
    'scrapedAt': scrapedAt.toUtc().toIso8601String(),
    'week': week,
    'school': school,
    'lessons': lessons.map((e) => e.toJson()).toList(),
    'homework': homework,
    'homeworkAt': homeworkAt?.toUtc().toIso8601String(),
    if (rotation != null) 'rotation': rotation!.toJson(),
  });
  factory Snapshot.decode(String source) {
    if (source.length > 2000000) {
      throw const FormatException('Snapshot is too large.');
    }
    final j = jsonDecode(source) as Map<String, dynamic>;
    if (j['schema'] != 1) {
      throw const FormatException('Unsupported snapshot version.');
    }
    final lessons = (j['lessons'] as List)
        .map((e) => Lesson.fromJson(e as Map<String, dynamic>))
        .toList();
    final week = j['week'] as String;
    if (DateTime.tryParse(week) == null ||
        lessons.any(
          (e) =>
              DateTime.tryParse(e.date) == null ||
              e.subject.length > 500 ||
              e.order < 0,
        )) {
      throw const FormatException('Invalid timetable data.');
    }
    return Snapshot(
      lessons: lessons,
      scrapedAt: DateTime.parse(j['scrapedAt'] as String),
      week: week,
      school: j['school'] as String? ?? '',
      homework: (j['homework'] as List? ?? [])
          .map((e) => Map<String, String>.from(e as Map))
          .toList(),
      homeworkAt: j['homeworkAt'] == null
          ? null
          : DateTime.parse(j['homeworkAt'] as String),
      rotation: ScheduleRotation.fromJson(j['rotation']),
    );
  }
}

Snapshot mergeTimetableWeeks(
  Snapshot? previous,
  List<Snapshot> captured,
  ScheduleRotation? rotation,
) {
  final replaced = {for (final week in captured) week.teachingWeek};
  final lessons =
      [
        ...?previous?.lessons.where(
          (lesson) =>
              !replaced.contains(weekStart(DateTime.parse(lesson.date))),
        ),
        for (final week in captured) ...week.lessons,
      ]..sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        return byDate != 0 ? byDate : a.order.compareTo(b.order);
      });
  return Snapshot(
    lessons: lessons,
    scrapedAt: captured.last.scrapedAt,
    week: captured.first.week,
    school: captured.last.school.isEmpty
        ? previous?.school ?? ''
        : captured.last.school,
    homework: previous?.homework ?? [],
    homeworkAt: previous?.homeworkAt,
    rotation: rotation,
  );
}

List<Map<String, String>> parseHomework(String source) {
  final table = html.parse(source).querySelector('#HomeworkTable');
  if (table == null) {
    throw const FormatException(
      'Open Homework and wait for the table to load.',
    );
  }
  final results = <Map<String, String>>[];
  for (final row in table.querySelectorAll('tbody tr')) {
    final cells = row.querySelectorAll('td');
    if (cells.length == 1 && cells.first.classes.contains('dataTables_empty')) {
      continue;
    }
    if (cells.length != 10) {
      throw const FormatException(
        'Homework layout changed. Your saved data is unchanged.',
      );
    }
    final date = cells[0].text.trim();
    if (!RegExp(r'^\d{2}/\d{2}/\d{4}$').hasMatch(date)) {
      throw const FormatException('Unrecognised homework due date.');
    }
    results.add({
      'due': date,
      'title': cells[2].text.trim(),
      'subject': cells[4].text.trim(),
      'teacher': cells[5].text.trim(),
      'status': cells[6].text.trim(),
    });
  }
  return results;
}

/// Parses the rendered, authenticated page, never login credentials or scripts.
Snapshot parseTimetable(String source, {DateTime? scrapedAt}) {
  final doc = html.parse(source);
  final table = doc.querySelector('table#Timetable');
  final selected = doc.querySelector('#WeekStartDate option[selected]');
  if (table == null || selected == null) {
    throw const FormatException(
      'Open My Timetable and wait for the week to load, then press Scrape. Your saved data has not changed.',
    );
  }
  final parts = (selected.attributes['value'] ?? '')
      .split('-')
      .map(int.parse)
      .toList();
  if (parts.length != 3) throw const FormatException('Unrecognised week date.');
  final week = DateTime(parts[2], parts[0], parts[1]);
  final headers = table.querySelectorAll('thead th');
  const weekdays = {
    'monday': 1,
    'tuesday': 2,
    'wednesday': 3,
    'thursday': 4,
    'friday': 5,
    'saturday': 6,
    'sunday': 7,
  };
  final dates = headers.map((h) {
    final name = weekdays.keys
        .where((d) => h.text.toLowerCase().startsWith(d))
        .firstOrNull;
    if (name == null) {
      throw const FormatException('Unrecognised timetable day.');
    }
    return dayKey(
      week.add(Duration(days: (weekdays[name]! - week.weekday + 7) % 7)),
    );
  }).toList();
  if (dates.isEmpty) throw const FormatException('Timetable is still loading.');
  final lessons = <Lesson>[];
  final rows = table.querySelectorAll('tbody tr');
  for (var r = 0; r < rows.length; r++) {
    final cells = rows[r].querySelectorAll('td');
    if (cells.length != dates.length) {
      throw const FormatException(
        'Timetable layout changed. Saved data has not changed.',
      );
    }
    for (var c = 0; c < cells.length; c++) {
      final cell = cells[c];
      final teacher =
          cell.querySelector('[id="sp-timetable-teacher"]')?.text.trim() ?? '';
      final room =
          cell.querySelector('[id="sp-timetable-room"]')?.text.trim() ?? '';
      final subject = cell.querySelector('.sp-text')?.text.trim() ?? '';
      final periodNode = cell.querySelector('[id^="sp-timetable-period"]');
      final malformed = RegExp(r'sp-timetable-period>([^<]+)')
          .firstMatch(periodNode?.id ?? '');
      final period =
          malformed?.group(1) ?? (periodNode?.text.trim() ?? cell.text.trim());
      if (period.isEmpty || period.length > 40) {
        throw const FormatException('Could not read period labels.');
      }
      final group = malformed != null
          ? periodNode!.text.trim()
          : (cell.querySelector('[id="sp-timetable-class"]')?.text.trim() ??
                '');
      if (subject.isEmpty && teacher.isEmpty && room.isEmpty) continue;
      lessons.add(
        Lesson(
          date: dates[c],
          period: period,
          subject: subject.isEmpty ? 'Registration' : subject,
          room: room,
          teacher: teacher,
          group: group,
          color: _lessonColor(cell.attributes['data-periodify-color']),
          order: r,
        ),
      );
    }
  }
  if (lessons.isEmpty) {
    throw const FormatException(
      'No lessons found in this week. Choose a teaching week; your saved timetable is unchanged.',
    );
  }
  lessons.sort((a, b) {
    final date = a.date.compareTo(b.date);
    return date != 0 ? date : a.order.compareTo(b.order);
  });
  return Snapshot(
    lessons: lessons,
    scrapedAt: scrapedAt ?? DateTime.now(),
    week: dayKey(week),
    school: doc.querySelector('#SchoolNameLabel')?.text.trim() ?? '',
  );
}
