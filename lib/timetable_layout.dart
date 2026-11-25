import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'model.dart';
import 'periods.dart';

enum TimetableLayout {
  cards('Cards', 'Full lesson details with colour badges'),
  compact('Compact', 'Slim rows for a quick scan'),
  timeline('Timeline', 'Follow the day from top to bottom'),
  grid('Grid', 'Place lessons side by side'),
  week('Week', 'Scan the week and pick a day'),
  focus('Focus', 'Highlight your current or next lesson');

  const TimetableLayout(this.label, this.description);
  final String label;
  final String description;

  static TimetableLayout fromName(String? name) =>
      values.where((layout) => layout.name == name).firstOrNull ?? cards;
}

class TimetableLayoutPicker extends StatelessWidget {
  const TimetableLayoutPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final TimetableLayout selected;
  final ValueChanged<TimetableLayout> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final tileWidth = width >= 540 ? (width - 12) / 2 : width;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final layout in TimetableLayout.values)
              SizedBox(
                width: tileWidth,
                child: Semantics(
                  selected: layout == selected,
                  child: Card(
                    color: layout == selected
                        ? colors.secondaryContainer
                        : colors.surfaceContainerLow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: layout == selected
                            ? colors.primary
                            : colors.outlineVariant,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => onChanged(layout),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ExcludeSemantics(
                              child: SizedBox(
                                width: double.infinity,
                                height: 44,
                                child: CustomPaint(
                                  painter: _LayoutPreview(layout, colors),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    layout.label,
                                    style: style.titleMedium,
                                  ),
                                ),
                                if (layout == selected)
                                  Icon(
                                    Icons.check_circle,
                                    size: 18,
                                    color: colors.primary,
                                  ),
                              ],
                            ),
                            Text(layout.description, style: style.bodySmall),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _LayoutPreview extends CustomPainter {
  const _LayoutPreview(this.layout, this.colors);

  final TimetableLayout layout;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final accent = colors.primary.withValues(alpha: .62);
    final block = colors.primary.withValues(alpha: .16);
    final ink = colors.onSurface.withValues(alpha: .25);
    void box(double x, double y, double w, double h, Color color) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, w, h),
          const Radius.circular(3),
        ),
        Paint()..color = color,
      );
    }

    switch (layout) {
      case TimetableLayout.cards:
        for (final y in [0.0, 24.0]) {
          box(0, y, width, 20, block);
          box(5, y + 5, 10, 10, accent);
          box(22, y + 8, width * .36, 4, ink);
        }
      case TimetableLayout.compact:
        for (final y in [4.0, 18.0, 32.0]) {
          box(0, y, 12, 6, accent);
          box(20, y, width * .52, 4, ink);
          box(0, y + 10, width, 1, block);
        }
      case TimetableLayout.timeline:
        box(5, 2, 2, 40, ink);
        for (final y in [3.0, 17.0, 31.0]) {
          box(2, y, 8, 8, accent);
          box(17, y, width - 17, 9, block);
        }
      case TimetableLayout.grid:
        for (final x in [0.0, (width + 6) / 2]) {
          for (final y in [0.0, 24.0]) {
            box(x, y, (width - 6) / 2, 20, block);
            box(x + 5, y + 5, (width - 6) * .23, 4, accent);
          }
        }
      case TimetableLayout.week:
        for (var day = 0; day < 5; day++) {
          final column = (width + 4) / 5;
          box(day * column, 0, column - 4, 8, day == 1 ? accent : ink);
          box(day * column, 12, column - 4, 30, block);
        }
      case TimetableLayout.focus:
        box(0, 0, width, 25, block);
        box(7, 6, width * .18, 4, accent);
        box(7, 14, width * .48, 5, ink);
        box(1, 32, width * .65, 4, ink);
        box(1, 40, width * .52, 3, block);
    }
  }

  @override
  bool shouldRepaint(_LayoutPreview oldDelegate) =>
      oldDelegate.layout != layout || oldDelegate.colors != colors;
}

class TimetableWeek extends StatelessWidget {
  const TimetableWeek({
    super.key,
    required this.days,
    required this.selected,
    required this.onSelect,
  });

  final List<({DateTime date, List<Lesson> lessons})> days;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 148).floor().clamp(2, 4);
        final width = (constraints.maxWidth - 8 * (columns - 1)) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final day in days)
              SizedBox(
                width: width,
                child: Semantics(
                  selected: dayKey(day.date) == dayKey(selected),
                  child: Card(
                    color: dayKey(day.date) == dayKey(selected)
                        ? theme.colorScheme.secondaryContainer
                        : theme.colorScheme.surfaceContainerLow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => onSelect(day.date),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              DateFormat('E d').format(day.date),
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${day.lessons.length} ${day.lessons.length == 1 ? 'lesson' : 'lessons'}',
                              style: theme.textTheme.bodySmall,
                            ),
                            for (final lesson in day.lessons.take(2))
                              Text(
                                lesson.subject,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class TimetableLessons extends StatelessWidget {
  const TimetableLessons({
    super.key,
    required this.layout,
    required this.lessons,
    required this.date,
    required this.periodFor,
  });

  final TimetableLayout layout;
  final List<Lesson> lessons;
  final DateTime date;
  final SchedulePeriod? Function(String) periodFor;

  (Lesson, String) _focus() {
    final now = DateTime.now();
    if (dayKey(now) != dayKey(date)) return (lessons.first, 'First lesson');
    final minutes = now.hour * 60 + now.minute;
    final timed = [
      for (final lesson in lessons)
        if (periodFor(lesson.period) case final period?) (lesson, period),
    ]..sort((a, b) => a.$2.start.compareTo(b.$2.start));
    for (final (lesson, period) in timed) {
      if (minutes >= period.start && minutes < period.end) {
        return (lesson, 'In progress');
      }
    }
    for (final (lesson, period) in timed) {
      if (minutes < period.start) return (lesson, 'Next up');
    }
    return timed.isEmpty
        ? (lessons.first, 'First lesson')
        : (timed.last.$1, 'Last timed lesson');
  }

  @override
  Widget build(BuildContext context) {
    if (lessons.isEmpty) return const SizedBox.shrink();
    final (focus, heading) = layout == TimetableLayout.focus
        ? _focus()
        : (null, null);
    if (layout == TimetableLayout.grid) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(1);
          final columns = ((constraints.maxWidth + 10) / (150 * scale))
              .floor()
              .clamp(1, 3);
          final width = (constraints.maxWidth - 10 * (columns - 1)) / columns;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final lesson in lessons)
                SizedBox(
                  width: width,
                  child: _LessonCard(
                    lesson,
                    periodFor(lesson.period),
                    layout: layout,
                  ),
                ),
            ],
          );
        },
      );
    }
    final style =
        layout == TimetableLayout.focus || layout == TimetableLayout.week
        ? TimetableLayout.compact
        : layout;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (focus != null && heading != null) ...[
          Text(heading, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          _LessonCard(focus, periodFor(focus.period)),
          const SizedBox(height: 12),
        ],
        for (final lesson in lessons)
          if (!identical(lesson, focus))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _LessonCard(
                lesson,
                periodFor(lesson.period),
                layout: style,
              ),
            ),
      ],
    );
  }
}

class _LessonCard extends StatelessWidget {
  const _LessonCard(
    this.lesson,
    this.period, {
    this.layout = TimetableLayout.cards,
  });

  final Lesson lesson;
  final SchedulePeriod? period;
  final TimetableLayout layout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hex = lesson.color;
    final accent = hex == null
        ? colors.primaryContainer
        : Color.alphaBlend(
            Color(0xff000000 | int.parse(hex.substring(1), radix: 16))
                .withValues(
                  alpha: colors.brightness == Brightness.dark ? .27 : .22,
                ),
            colors.surfaceContainerHigh,
          );
    final compact = layout != TimetableLayout.cards;
    final label = period;
    final details = [
      lesson.room,
      lesson.teacher,
    ].where((value) => value.isNotEmpty).join(' · ');
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          lesson.subject,
          style: compact
              ? theme.textTheme.titleSmall
              : theme.textTheme.titleLarge,
        ),
        if (details.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(details, style: theme.textTheme.bodyMedium),
        ],
        if (label != null) ...[
          const SizedBox(height: 4),
          Text(
            [
              if (label.name != lesson.period) label.name,
              '${SchedulePeriod.clockTime(label.start)}–${SchedulePeriod.clockTime(label.end)}',
            ].join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
    final badge = Container(
      constraints: BoxConstraints(maxWidth: compact ? 64 : 50),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        lesson.period,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelMedium,
      ),
    );
    return Card(
      color: layout == TimetableLayout.grid ? colors.surfaceContainerLow : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 14 : 24),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 12 : 20),
        child: switch (layout) {
          TimetableLayout.grid => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [badge, const SizedBox(height: 8), body],
          ),
          TimetableLayout.timeline => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 3,
                height: 42,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: .65),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              badge,
              const SizedBox(width: 10),
              Expanded(child: body),
            ],
          ),
          _ => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              badge,
              const SizedBox(width: 12),
              Expanded(child: body),
            ],
          ),
        },
      ),
    );
  }
}
