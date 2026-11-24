import 'package:flutter/material.dart';

import 'periods.dart';

class PeriodEditor extends StatefulWidget {
  const PeriodEditor({
    super.key,
    this.period,
    this.suggestedLabel,
    required this.scrapedLabels,
    required this.labelInUse,
  });

  final SchedulePeriod? period;
  final String? suggestedLabel;
  final List<String> scrapedLabels;
  final bool Function(String) labelInUse;

  @override
  State<PeriodEditor> createState() => _PeriodEditorState();
}

class _PeriodEditorState extends State<PeriodEditor> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(
    text: widget.period?.name ?? widget.suggestedLabel,
  );
  late final label = TextEditingController(
    text: widget.period?.bromcomLabel ?? widget.suggestedLabel,
  );
  late int start = widget.period?.start ?? 9 * 60;
  late int end = widget.period?.end ?? 10 * 60;
  String? timeError;

  @override
  void dispose() {
    name.dispose();
    label.dispose();
    super.dispose();
  }

  Future<void> chooseTime({required bool starts}) async {
    final minutes = starts ? start : end;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
      helpText: starts ? 'Period start' : 'Period end',
    );
    if (!mounted || time == null) return;
    final value = time.hour * 60 + time.minute;
    setState(() {
      if (starts) {
        start = value;
      } else {
        end = value;
      }
      timeError = null;
    });
  }

  void save() {
    final valid = form.currentState!.validate();
    setState(
      () => timeError = end <= start
          ? 'End time must be after start time.'
          : null,
    );
    if (!valid || timeError != null) return;
    Navigator.pop(
      context,
      SchedulePeriod(
        name: name.text.trim(),
        bromcomLabel: label.text.trim().isEmpty
            ? name.text.trim()
            : label.text.trim(),
        start: start,
        end: end,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(widget.period == null ? 'Add period' : 'Edit period'),
    content: SizedBox(
      width: 360,
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: name,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 60,
              decoration: const InputDecoration(
                labelText: 'Period name',
                counterText: '',
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Give this period a name.'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: label,
              maxLength: 60,
              decoration: InputDecoration(
                labelText: 'Bromcom label (optional)',
                helperText: 'Matches by name when blank.',
                counterText: '',
                suffixIcon: widget.scrapedLabels.isEmpty
                    ? null
                    : PopupMenuButton<String>(
                        tooltip: 'Choose a label from Bromcom',
                        icon: const Icon(Icons.arrow_drop_down),
                        onSelected: (value) {
                          label.text = value;
                          if (name.text.trim().isEmpty) name.text = value;
                        },
                        itemBuilder: (_) => [
                          for (final source in widget.scrapedLabels)
                            PopupMenuItem(
                              value: source,
                              enabled: !widget.labelInUse(source),
                              child: Text(source),
                            ),
                        ],
                      ),
              ),
              validator: (value) {
                final source = (value ?? '').trim();
                return widget.labelInUse(
                      source.isEmpty ? name.text.trim() : source,
                    )
                    ? 'This Bromcom label is already linked.'
                    : null;
              },
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => chooseTime(starts: true),
                  child: Text('Start ${SchedulePeriod.clockTime(start)}'),
                ),
                OutlinedButton(
                  onPressed: () => chooseTime(starts: false),
                  child: Text('End ${SchedulePeriod.clockTime(end)}'),
                ),
              ],
            ),
            if (timeError case final message?)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  message,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: save, child: const Text('Save period')),
    ],
  );
}
