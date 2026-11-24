import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'model.dart';
import 'portal.dart';
import 'windows_title_bar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (usesWindowsTitleBar) await configureWindowsTitleBar();
  runApp(const PeriodifyApp());
}

const _destinations = [
  (label: 'Timetable', icon: Icons.calendar_view_day_outlined),
  (label: 'Watch', icon: Icons.watch_outlined),
  (label: 'Settings', icon: Icons.tune),
];

class PeriodifyApp extends StatefulWidget {
  const PeriodifyApp({super.key});
  @override
  State<PeriodifyApp> createState() => _AppState();
}

class _AppState extends State<PeriodifyApp> {
  ThemeMode mode = ThemeMode.system;
  ThemeData theme(Brightness b) => ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xff426c54),
      brightness: b,
    ),
    scaffoldBackgroundColor: b == Brightness.dark
        ? const Color(0xff101915)
        : const Color(0xfff3f7f4),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Periodify',
    theme: theme(Brightness.light),
    darkTheme: theme(Brightness.dark),
    themeMode: mode,
    home: Home(mode: mode, onTheme: (m) => setState(() => mode = m)),
  );
}

class Home extends StatefulWidget {
  const Home({super.key, required this.mode, required this.onTheme});
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onTheme;
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  Snapshot? snapshot;
  bool loading = true, busy = false;
  int page = 0;
  DateTime selected = DateUtils.dateOnly(DateTime.now());
  Map<String, String> bells = {};
  String watchStatus = 'Ready when your watch is';
  static const watch = MethodChannel('com.im7ames.periodify/watch');
  bool get android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get nativePortal =>
      !kIsWeb &&
      {
        TargetPlatform.android,
        TargetPlatform.windows,
        TargetPlatform.macOS,
      }.contains(defaultTargetPlatform);
  @override
  void initState() {
    super.initState();
    restore();
  }

  void notice(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> restore() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('snapshot');
      if (raw != null) snapshot = Snapshot.decode(raw);
      final b = p.getString('bells');
      if (b != null) bells = Map<String, String>.from(jsonDecode(b) as Map);
      final t = p.getInt('theme');
      if (t != null && t >= 0 && t < 3) widget.onTheme(ThemeMode.values[t]);
    } catch (_) {
      if (mounted) {
        notice('Could not read saved data. Import or scrape a new snapshot.');
      }
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> save(Snapshot result) async {
    setState(() => busy = true);
    try {
      final p = await SharedPreferences.getInstance();
      if (!await p.setString('snapshot', result.encode())) {
        throw StateError('Storage failed');
      }
      if (!mounted) return;
      setState(() {
        snapshot = result;
        selected = DateTime.parse(result.lessons.first.date);
      });
      notice('Saved on this device. Available offline.');
      if (android) await syncWatch();
    } catch (_) {
      if (mounted) notice('Could not save this snapshot.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> connect() async {
    if (!nativePortal) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Bring your timetable with you'),
          content: const Text(
            'Web and Linux use exported snapshots. Scrape on Android, Windows or macOS, export the snapshot, then import it here. Browser security prevents this website from reading your Bromcom session.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Got it'),
            ),
          ],
        ),
      );
      return;
    }
    final result = await Navigator.push<Snapshot>(
      context,
      MaterialPageRoute(builder: (_) => PortalPage(previous: snapshot)),
    );
    if (result != null && mounted) await save(result);
  }

  Future<void> importData() async {
    try {
      final f = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(label: 'Periodify snapshot', extensions: ['json']),
        ],
      );
      if (f == null) return;
      if (await f.length() > 2000000) throw const FormatException();
      final data = Snapshot.decode(await f.readAsString());
      if (data.lessons.isEmpty) throw const FormatException();
      if (mounted) await save(data);
    } catch (_) {
      if (mounted) {
        notice('Not a valid Periodify snapshot. Nothing was replaced.');
      }
    }
  }

  Future<void> exportData() async {
    if (snapshot == null) return;
    try {
      if (android) {
        await watch.invokeMethod<void>('export', snapshot!.encode());
        return;
      }
      final f = XFile.fromData(
        Uint8List.fromList(utf8.encode(snapshot!.encode())),
        mimeType: 'application/json',
        name: 'periodify.json',
      );
      if (kIsWeb) {
        await f.saveTo('periodify.json');
      } else {
        final location = await getSaveLocation(suggestedName: 'periodify.json');
        if (location != null) await f.saveTo(location.path);
      }
    } catch (_) {
      if (mounted) notice('Export is unavailable on this device.');
    }
  }

  Future<void> syncWatch() async {
    if (!android || snapshot == null) return;
    try {
      final data = jsonDecode(snapshot!.encode()) as Map<String, dynamic>;
      data['bells'] = bells;
      await watch.invokeMethod<void>('sync', jsonEncode(data));
      if (mounted) setState(() => watchStatus = 'Queued for your paired watch');
    } catch (_) {
      if (mounted) {
        setState(
          () => watchStatus =
              'Sync failed. Check Google Play services and try again.',
        );
      }
    }
  }

  Future<void> editBell(String period) async {
    final start = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
      helpText: '$period start',
    );
    if (start == null || !mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (start.hour + 1) % 24, minute: start.minute),
      helpText: '$period end',
    );
    if (end == null || !mounted) return;
    if (end.hour * 60 + end.minute <= start.hour * 60 + start.minute) {
      notice('End time must be after start time.');
      return;
    }
    String format(TimeOfDay t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final updated = {...bells, period: '${format(start)}-${format(end)}'};
    final p = await SharedPreferences.getInstance();
    await p.setString('bells', jsonEncode(updated));
    if (mounted) setState(() => bells = updated);
    if (android) await syncWatch();
  }

  Future<void> setTheme(ThemeMode m) async {
    widget.onTheme(m);
    final p = await SharedPreferences.getInstance();
    await p.setInt('theme', m.index);
  }

  void selectPage(int index) => setState(() => page = index);

  PreferredSizeWidget windowsTitleBar(BuildContext context) {
    final media = MediaQuery.of(context);
    final showLabels = media.size.width >= 400 + media.textScaler.scale(250);
    final colors = Theme.of(context).colorScheme;

    return WindowsTitleBar(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.view_timeline_rounded,
              size: 17,
              color: colors.onPrimaryContainer,
              semanticLabel: showLabels ? null : 'Periodify',
            ),
          ),
          if (showLabels) ...[
            const SizedBox(width: 9),
            const Text('Periodify'),
          ],
        ],
      ),
      navigation: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          for (final (index, destination) in _destinations.indexed)
            Tooltip(
              message: showLabels ? '' : destination.label,
              child: Semantics(
                selected: page == index,
                child: TextButton(
                  onPressed: () => selectPage(index),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(40, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: EdgeInsets.symmetric(
                      horizontal: showLabels ? 12 : 8,
                    ),
                    foregroundColor: page == index
                        ? colors.onSecondaryContainer
                        : colors.onSurfaceVariant,
                    backgroundColor: page == index
                        ? colors.secondaryContainer
                        : null,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 7,
                    children: [
                      Icon(destination.icon, size: 18),
                      if (showLabels) Text(destination.label),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 850;
    return Scaffold(
      appBar: usesWindowsTitleBar
          ? windowsTitleBar(context)
          : AppBar(
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.view_timeline_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'periodify',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: 'Change theme',
                  onPressed: () => setTheme(
                    widget.mode == ThemeMode.dark
                        ? ThemeMode.light
                        : ThemeMode.dark,
                  ),
                  icon: Icon(
                    widget.mode == ThemeMode.dark
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined,
                  ),
                ),
                const SizedBox(width: 12),
              ],
            ),
      bottomNavigationBar: wide || usesWindowsTitleBar
          ? null
          : NavigationBar(
              selectedIndex: page,
              onDestinationSelected: selectPage,
              destinations: [
                for (final destination in _destinations)
                  NavigationDestination(
                    icon: Icon(destination.icon),
                    label: destination.label,
                  ),
              ],
            ),
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (wide && !usesWindowsTitleBar)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: NavigationRail(
                  backgroundColor: Colors.transparent,
                  selectedIndex: page,
                  onDestinationSelected: selectPage,
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final destination in _destinations)
                      NavigationRailDestination(
                        icon: Icon(destination.icon),
                        label: Text(destination.label),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1060),
                        child: ListView(
                          padding: EdgeInsets.all(wide ? 36 : 20),
                          children: page == 0
                              ? timetable()
                              : page == 1
                              ? watchPage()
                              : settings(),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> heading(String eyebrow, String title, String subtitle) => [
    Text(
      eyebrow.toUpperCase(),
      style: TextStyle(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w700,
        letterSpacing: 2,
        fontSize: 12,
      ),
    ),
    const SizedBox(height: 12),
    Text(
      title,
      style: const TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.2,
      ),
    ),
    const SizedBox(height: 8),
    Text(subtitle, style: const TextStyle(fontSize: 16, height: 1.5)),
    const SizedBox(height: 28),
  ];
  Widget panel(Widget child) => Card(
    child: Padding(padding: const EdgeInsets.all(24), child: child),
  );
  List<Widget> timetable() {
    final lessons =
        snapshot?.lessons.where((l) => l.date == dayKey(selected)).toList() ??
        <Lesson>[];
    final week = selected.subtract(Duration(days: selected.weekday - 1));
    return [
      Text(
        'Timetable',
        style: Theme.of(context).textTheme.headlineLarge
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 20),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          FilledButton.icon(
            onPressed: busy ? null : connect,
            icon: const Icon(Icons.sync),
            label: const Text('Scrape'),
          ),
          OutlinedButton.icon(
            onPressed: busy ? null : importData,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 52),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('Import snapshot'),
          ),
        ],
      ),
      const SizedBox(height: 24),
      if (snapshot == null)
        panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.calendar_view_day_outlined,
                size: 32,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              const Text(
                'No timetable saved',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                nativePortal
                    ? 'Sign in to Bromcom with Microsoft and scrape the week you want to save, or import a snapshot.'
                    : 'Import a snapshot exported from Periodify on Android, Windows, or macOS.',
                style: const TextStyle(fontSize: 16, height: 1.6),
              ),
            ],
          ),
        )
      else ...[
        Text(
          'Saved ${DateFormat('d MMM, HH:mm').format(snapshot!.scrapedAt.toLocal())} · Updates only when you scrape',
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            IconButton(
              tooltip: 'Previous week',
              onPressed: () => setState(
                () => selected = selected.subtract(const Duration(days: 7)),
              ),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                DateFormat('MMMM yyyy').format(selected),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Next week',
              onPressed: () => setState(
                () => selected = selected.add(const Duration(days: 7)),
              ),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List.generate(7, (i) {
            final d = week.add(Duration(days: i));
            return ChoiceChip(
              selected: dayKey(d) == dayKey(selected),
              onSelected: (_) => setState(() => selected = d),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('${DateFormat('E').format(d)} ${d.day}'),
              ),
            );
          }),
        ),
        const SizedBox(height: 24),
        Text(
          DateFormat('EEEE, d MMMM').format(selected),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        if (lessons.isEmpty)
          panel(
            const Text(
              'No saved lessons for this day. Scrape this week in Bromcom to check its timetable.',
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
          ),
        ...lessons.map(
          (l) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: panel(
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      l.period,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.subject,
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          [
                            l.room,
                            l.teacher,
                          ].where((s) => s.isNotEmpty).join(' · '),
                          style: const TextStyle(fontSize: 15, height: 1.5),
                        ),
                        if (bells[l.period] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              bells[l.period]!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
      if (snapshot?.homeworkAt != null) ...[
        const SizedBox(height: 24),
        const Text(
          'Homework',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        ...snapshot!.homework.map(
          (h) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: panel(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    h['title'] ?? '',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    [
                      h['subject'],
                      h['due'],
                      h['status'],
                    ].whereType<String>().join(' · '),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
      const SizedBox(height: 32),
      const Text('Independent of Bromcom.', style: TextStyle(fontSize: 13)),
    ];
  }

  List<Widget> watchPage() => [
    ...heading(
      'A glance is enough',
      'Your next room. On your wrist.',
      'Sync your saved timetable from Android to a paired Wear OS watch.',
    ),
    panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.watch_rounded, size: 60),
          const SizedBox(height: 24),
          Text(
            watchStatus,
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          const Text(
            'Install Periodify on both devices. Keep Bluetooth and Google Play services available. Saved snapshots are transferred through the Wear OS Data Layer.',
            style: TextStyle(fontSize: 16, height: 1.6),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: android && snapshot != null ? syncWatch : null,
            icon: const Icon(Icons.sync),
            label: const Text('Sync saved timetable'),
          ),
          if (!android)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('Watch sync is available from the Android app.'),
            ),
          const SizedBox(height: 12),
          const Text(
            'The watch never scrapes Bromcom. It displays your last saved snapshot.',
          ),
        ],
      ),
    ),
  ];
  List<Widget> settings() => [
    ...heading(
      'Make it yours',
      'Small details. Better days.',
      'Your data and preferences stay on this device.',
    ),
    panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Appearance',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ThemeMode.values
                .map(
                  (m) => ChoiceChip(
                    label: Text(m.name),
                    selected: widget.mode == m,
                    onSelected: (_) => setTheme(m),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    ),
    const SizedBox(height: 16),
    panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Bell times',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Bromcom provides period labels. Set your school’s times for the watch’s now/next view.',
          ),
          const SizedBox(height: 12),
          if (snapshot == null)
            const Text('Import a timetable to set period times.'),
          ...{...?snapshot?.lessons.map((l) => l.period)}.map(
            (p) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(p),
              subtitle: Text(bells[p] ?? 'Not set'),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => editBell(p),
            ),
          ),
        ],
      ),
    ),
    const SizedBox(height: 16),
    panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your snapshot',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          const Text(
            'Exported files contain your timetable. Share them only with devices and people you trust.',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed: snapshot == null ? null : exportData,
                icon: const Icon(Icons.ios_share),
                label: const Text('Export'),
              ),
              TextButton(
                onPressed: snapshot == null ? null : clearData,
                child: const Text('Clear data'),
              ),
            ],
          ),
        ],
      ),
    ),
  ];
  Future<void> clearData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Clear saved timetable?'),
        content: const Text(
          'Removes this device’s timetable and clears the paired watch on next sync. Bromcom is unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final p = await SharedPreferences.getInstance();
    await p.remove('snapshot');
    if (android) {
      try {
        await watch.invokeMethod<void>('clear');
      } catch (_) {
        if (mounted) {
          notice('Phone cleared. Reconnect your watch and clear its copy.');
        }
      }
    }
    if (mounted) setState(() => snapshot = null);
  }
}
