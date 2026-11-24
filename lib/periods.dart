class SchedulePeriod {
  const SchedulePeriod({
    required this.name,
    required this.bromcomLabel,
    required this.start,
    required this.end,
  });

  final String name;
  final String bromcomLabel;
  final int start;
  final int end;

  static String matchKey(String label) {
    final cleaned = label.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final numbered = RegExp(r'^(?:(?:p|period)\s*)?0*([0-9]+)$')
        .firstMatch(cleaned);
    return numbered == null ? cleaned : 'p${numbered.group(1)}';
  }

  static String clockTime(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

  String get timeRange => '${clockTime(start)}-${clockTime(end)}';

  Map<String, Object> toJson() => {
    'name': name,
    'bromcomLabel': bromcomLabel,
    'start': start,
    'end': end,
  };

  static List<SchedulePeriod> decode(Object? periods, {Object? legacyBells}) {
    if (periods is List) {
      final result = <SchedulePeriod>[];
      final labels = <String>{};
      for (final entry in periods) {
        if (entry
            case {
              'name': final String name,
              'bromcomLabel': final String label,
              'start': final int start,
              'end': final int end,
            }
            when name.trim().isNotEmpty &&
                label.trim().isNotEmpty &&
                start >= 0 &&
                end < 1440 &&
                start < end &&
                labels.add(label)) {
          result.add(
            SchedulePeriod(
              name: name,
              bromcomLabel: label,
              start: start,
              end: end,
            ),
          );
        }
      }
      return result;
    }

    if (legacyBells is! Map) return [];
    final timeRange = RegExp(
      r'^([01]\d|2[0-3]):([0-5]\d)-([01]\d|2[0-3]):([0-5]\d)$',
    );
    final result = <SchedulePeriod>[];
    for (final entry in legacyBells.entries) {
      final label = entry.key;
      final value = entry.value;
      if (label is! String || label.trim().isEmpty || value is! String) {
        continue;
      }
      final match = timeRange.firstMatch(value);
      if (match == null) continue;
      final start = int.parse(match[1]!) * 60 + int.parse(match[2]!);
      final end = int.parse(match[3]!) * 60 + int.parse(match[4]!);
      if (start < end) {
        result.add(
          SchedulePeriod(
            name: label,
            bromcomLabel: label,
            start: start,
            end: end,
          ),
        );
      }
    }
    return result;
  }
}
