import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account.dart';
import 'model.dart';
import 'portal.dart';
import 'updates.dart';
import 'windows_title_bar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (usesWindowsTitleBar) await configureWindowsTitleBar();
  runApp(const PeriodifyApp(autoUpdateChecks: true));
}

const _destinations = [
  (label: 'Timetable', icon: Icons.calendar_view_day_outlined),
  (label: 'Watch', icon: Icons.watch_outlined),
  (label: 'Settings', icon: Icons.tune),
];

enum _SettingsPage { appearance, timetable, data, account, updates }

class PeriodifyApp extends StatefulWidget {
  const PeriodifyApp({super.key, this.autoUpdateChecks = false});
  final bool autoUpdateChecks;
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
    home: Home(
      mode: mode,
      onTheme: (m) => setState(() => mode = m),
      autoUpdateChecks: widget.autoUpdateChecks,
    ),
  );
}

class Home extends StatefulWidget {
  const Home({
    super.key,
    required this.mode,
    required this.onTheme,
    required this.autoUpdateChecks,
  });
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onTheme;
  final bool autoUpdateChecks;
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  Snapshot? snapshot;
  bool loading = true, busy = false;
  int page = 0;
  int repeatWeeks = 0;
  _SettingsPage? settingsPage;
  static const accountClient = AccountClient();
  AccountSession? account;
  bool syncing = false, syncConflict = false;
  String? syncStatus;
  Timer? accountTimer;
  static const updateService = UpdateService();
  AppUpdate? availableUpdate;
  String? updateStatus;
  bool checkingUpdate = false, installingUpdate = false;
  Timer? updateTimer;
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
    unawaited(restore().then((_) => restoreAccount()));
    if (widget.autoUpdateChecks) {
      unawaited(checkUpdate());
      updateTimer = Timer.periodic(
        const Duration(minutes: 30),
        (_) => unawaited(checkUpdate()),
      );
    }
  }

  @override
  void dispose() {
    accountTimer?.cancel();
    updateTimer?.cancel();
    super.dispose();
  }

  Future<void> checkUpdate({bool manual = false}) async {
    if (checkingUpdate || installingUpdate) return;
    setState(() {
      checkingUpdate = true;
      if (manual) updateStatus = 'Checking for updates…';
    });
    try {
      final offer = await updateService.check();
      if (mounted) {
        setState(() {
          availableUpdate = offer;
          updateStatus = offer == null
              ? 'You’re up to date.'
              : 'Periodify ${offer.version} is available.';
        });
      }
    } catch (_) {
      if (mounted && manual) {
        setState(
          () => updateStatus = 'Could not check for updates. Try again later.',
        );
      }
    } finally {
      if (mounted) setState(() => checkingUpdate = false);
    }
  }

  Future<void> installUpdate() async {
    final offer = availableUpdate;
    if (offer == null || installingUpdate || busy || syncing) return;
    setState(() {
      installingUpdate = true;
      updateStatus = kIsWeb
          ? 'Reloading…'
          : 'Downloading and verifying the update…';
    });
    try {
      await offer.install();
      if (mounted) {
        setState(
          () => updateStatus =
              'Follow the installer prompts, then reopen Periodify.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => updateStatus =
              error is PlatformException && error.code == 'INSTALL_PERMISSION'
              ? 'Allow Periodify to install apps in Android Settings, then try again.'
              : 'Could not install the update. Try again or download the installer from GitHub.',
        );
      }
    } finally {
      if (mounted) setState(() => installingUpdate = false);
    }
  }

  Widget updateCard({required bool showCheck}) {
    final offer = availableUpdate;
    return panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(updateStatus ?? 'Check for a new version of Periodify.'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (offer != null)
                FilledButton.icon(
                  onPressed: installingUpdate || busy || syncing
                      ? null
                      : installUpdate,
                  icon: const Icon(Icons.system_update_alt),
                  label: Text(offer.action),
                ),
              if (showCheck)
                OutlinedButton(
                  onPressed: checkingUpdate || installingUpdate
                      ? null
                      : () => checkUpdate(manual: true),
                  child: const Text('Check for updates'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void notice(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> restore() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('snapshot');
      if (raw != null) snapshot = Snapshot.decode(raw);
      final savedRepeat = p.getInt('repeatWeeks') ?? 0;
      repeatWeeks =
          snapshot?.rotation?.weeks ??
          (savedRepeat >= 0 && savedRepeat <= ScheduleRotation.maxWeeks
              ? savedRepeat
              : 0);
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
      if (result.rotation == null && repeatWeeks > 0) {
        result = result.withRotation(
          ScheduleRotation(repeatWeeks, result.teachingWeek),
        );
      }
      if (!await p.setString('snapshot', result.encode())) {
        throw StateError('Storage failed');
      }
      if (!mounted) return;
      setState(() {
        snapshot = result;
        repeatWeeks = result.rotation?.weeks ?? 0;
        selected = result.teachingWeek;
      });
      notice('Saved on this device. Available offline.');
      if (android) await syncWatch();
    } catch (_) {
      if (mounted) notice('Could not save this snapshot.');
    } finally {
      if (mounted) {
        setState(() => busy = false);
        unawaited(syncNow());
      }
    }
  }

  Future<void> connect() async {
    if (syncing) return;
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
      MaterialPageRoute(
        builder: (_) =>
            PortalPage(previous: snapshot, repeatWeeks: repeatWeeks),
      ),
    );
    if (result != null && mounted) await save(result);
  }

  Future<void> importData() async {
    if (syncing) return;
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
    final current = snapshot;
    if (!android || current == null) return;
    try {
      final data = {
        'schema': 1,
        'scrapedAt': current.scrapedAt.toUtc().toIso8601String(),
        if (current.rotation case final rotation?)
          'rotation': rotation.toJson(),
        'bells': bells,
        'lessons': [
          for (final lesson in current.lessons)
            {
              'date': lesson.date,
              'period': lesson.period,
              'subject': lesson.subject,
              'room': lesson.room,
              'color': ?lesson.color,
            },
        ],
      };
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
    unawaited(syncNow());
  }

  Future<void> setTheme(ThemeMode m) async {
    widget.onTheme(m);
    final p = await SharedPreferences.getInstance();
    await p.setInt('theme', m.index);
    unawaited(syncNow());
  }

  Future<AccountData> localAccountData() async {
    final p = await SharedPreferences.getInstance();
    return AccountData(
      snapshot,
      bells,
      repeatWeeks,
      p.getInt('theme') ?? widget.mode.index,
    );
  }

  Future<void> restoreAccount() async {
    if (!mounted || AccountClient.endpoint == null) return;
    try {
      final session = await AccountSession.restore();
      if (!mounted || session == null) return;
      setState(() => account = session);
      scheduleAccountSync();
      await syncNow();
    } catch (_) {
      if (mounted) {
        setState(
          () => syncStatus =
              'Could not open secure account storage on this device.',
        );
      }
    }
  }

  void scheduleAccountSync() {
    accountTimer?.cancel();
    accountTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(syncNow()),
    );
  }

  Future<void> accountOperation(Future<void> Function() run) async {
    if (syncing || busy || installingUpdate) return;
    setState(() {
      syncing = true;
      syncStatus = 'Syncing…';
    });
    try {
      await run();
    } catch (error) {
      if (mounted) {
        setState(
          () => syncStatus = error is AccountError
              ? error.message
              : 'Could not sync. Check your connection or try again.',
        );
      }
    } finally {
      if (mounted) setState(() => syncing = false);
    }
  }

  Future<void> updateAccount(AccountSession session) async {
    await session.save();
    if (!mounted) return;
    setState(() {
      account = session;
      syncStatus = 'Synced';
      syncConflict = false;
    });
  }

  Future<void> applyAccountData(AccountData remote) async {
    final p = await SharedPreferences.getInstance();
    final saved = remote.snapshot;
    final writes = await Future.wait([
      saved == null
          ? p.remove('snapshot')
          : p.setString('snapshot', saved.encode()),
      p.setString('bells', jsonEncode(remote.bells)),
      p.setInt('repeatWeeks', remote.repeatWeeks),
      p.setInt('theme', remote.theme),
    ]);
    if (writes.contains(false)) {
      throw const AccountError('Could not save account data on this device.');
    }
    if (!mounted) return;
    widget.onTheme(ThemeMode.values[remote.theme]);
    setState(() {
      snapshot = saved;
      bells = remote.bells;
      repeatWeeks = remote.repeatWeeks;
    });
    if (android) {
      if (saved == null) {
        try {
          await watch.invokeMethod<void>('clear');
        } catch (_) {
          if (mounted) {
            notice('Synced the phone. The watch could not be reached.');
          }
        }
      } else {
        await syncWatch();
      }
    }
  }

  Future<void> syncNow({
    bool keepDevice = false,
    bool useAccount = false,
  }) async {
    final session = account;
    if (session == null || (syncConflict && !keepDevice && !useAccount)) return;
    await accountOperation(() async {
      final remote = await accountClient.read(session.code);
      if (remote == null) {
        throw const AccountError(
          'The cloud account no longer exists. Sign out to keep using this device.',
        );
      }
      if (!mounted) return;
      final local = await localAccountData();
      final fingerprint = await local.fingerprint;
      final localChanged = fingerprint != session.fingerprint;
      final remoteChanged = remote.revision != session.revision;
      if (remoteChanged && localChanged && !keepDevice && !useAccount) {
        if (await remote.data.fingerprint == fingerprint) {
          await updateAccount(
            AccountSession(session.code, remote.revision, fingerprint),
          );
          return;
        }
        if (mounted) {
          setState(() {
            syncConflict = true;
            syncStatus = 'This device and the account both changed. Choose which data to keep.';
          });
        }
        return;
      }
      if (useAccount || (remoteChanged && !keepDevice)) {
        if (busy || !mounted) return;
        await applyAccountData(remote.data);
        await updateAccount(
          AccountSession(
            session.code,
            remote.revision,
            await remote.data.fingerprint,
          ),
        );
      } else if (localChanged || keepDevice) {
        await updateAccount(
          await accountClient.write(
            session.code,
            local,
            revision: remote.revision,
          ),
        );
      } else if (mounted) {
        setState(() => syncStatus = 'Synced');
      }
    });
  }

  Future<void> createAccount() async {
    await accountOperation(() async {
      final code = AccountClient.createCode();
      final session = await accountClient.write(code, await localAccountData());
      await updateAccount(session);
      if (!mounted) return;
      scheduleAccountSync();
      await showAccountCode(session);
    });
  }

  Future<void> showAccountCode(AccountSession session) => showDialog<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('Your sync code'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Save this code somewhere private. Enter it on any device you want to sync. Anyone with the code can access the account.',
          ),
          const SizedBox(height: 16),
          SelectableText(session.code),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('Done'),
        ),
        FilledButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: session.code));
            if (dialog.mounted) Navigator.pop(dialog);
          },
          child: const Text('Copy code'),
        ),
      ],
    ),
  );

  Future<void> signIn() async {
    var code = '';
    final submitted = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Sign in to Periodify'),
        content: TextField(
          autofocus: true,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (value) => code = value.trim(),
          onSubmitted: (_) => Navigator.pop(dialog, code),
          decoration: const InputDecoration(labelText: 'Sync code'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, code),
            child: const Text('Sign in'),
          ),
        ],
      ),
    );
    if (submitted == null || !mounted) return;
    await accountOperation(() async {
      final remote = await accountClient.read(submitted);
      if (remote == null) {
        throw const AccountError('No account matches that sync code.');
      }
      if (!mounted) return;
      if (snapshot != null || bells.isNotEmpty) {
        final approved = await confirmAccountAction(
          'Use account data?',
          'Signing in will replace the timetable, homework, and preferences saved on this device with the account copy.',
          'Use account data',
        );
        if (!approved || !mounted) {
          if (mounted) setState(() => syncStatus = null);
          return;
        }
      }
      await applyAccountData(remote.data);
      await updateAccount(
        AccountSession(
          submitted,
          remote.revision,
          await remote.data.fingerprint,
        ),
      );
      if (mounted) scheduleAccountSync();
    });
  }

  Future<bool> confirmAccountAction(
    String title,
    String body,
    String action,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> signOut({bool deleteCloud = false}) async {
    final session = account;
    if (session == null) return;
    if (deleteCloud &&
        !await confirmAccountAction(
          'Delete this sync account?',
          'This deletes the account copy from Cloudflare and stops sync on all devices. The copy saved on this device stays available.',
          'Delete account',
        )) {
      return;
    }
    if (!mounted) return;
    await accountOperation(() async {
      if (deleteCloud) await accountClient.delete(session);
      await AccountSession.signOut();
      accountTimer?.cancel();
      if (mounted) {
        setState(() {
          account = null;
          syncStatus = null;
          syncConflict = false;
        });
      }
    });
  }

  Future<void> setRepeatWeeks(int weeks) async {
    if (busy || repeatWeeks == weeks) return;
    setState(() => busy = true);
    try {
      final p = await SharedPreferences.getInstance();
      final current = snapshot;
      final updated = current?.withRotation(
        weeks == 0
            ? null
            : ScheduleRotation(
                weeks,
                current.rotation?.start ?? current.teachingWeek,
              ),
      );
      if (!await p.setInt('repeatWeeks', weeks) ||
          (updated != null &&
              !await p.setString('snapshot', updated.encode()))) {
        throw StateError('Storage failed');
      }
      if (!mounted) return;
      setState(() {
        repeatWeeks = weeks;
        snapshot = updated;
      });
      if (android) await syncWatch();
    } catch (_) {
      if (mounted) notice('Could not save the schedule rotation.');
    } finally {
      if (mounted) {
        setState(() => busy = false);
        unawaited(syncNow());
      }
    }
  }

  void selectPage(int index) => setState(() {
    page = index;
    settingsPage = null;
  });

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
                          children: [
                            if (availableUpdate != null &&
                                (page != 2 ||
                                    settingsPage != _SettingsPage.updates)) ...[
                              updateCard(showCheck: false),
                              const SizedBox(height: 16),
                            ],
                            ...(page == 0
                                ? timetable()
                                : page == 1
                                ? watchPage()
                                : settings()),
                          ],
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

  Color periodBackground(Lesson lesson) {
    final colors = Theme.of(context).colorScheme;
    final hex = lesson.color;
    if (hex == null) return colors.primaryContainer;
    final color = Color(0xff000000 | int.parse(hex.substring(1), radix: 16));
    final opacity = colors.brightness == Brightness.dark ? 0.27 : 0.22;
    return Color.alphaBlend(
      color.withValues(alpha: opacity),
      colors.surfaceContainerHigh,
    );
  }

  List<Widget> timetable() {
    final current = snapshot;
    final lessons = current?.lessonsFor(selected) ?? <Lesson>[];
    final week = weekStart(selected);
    final rotation = current?.rotation;
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
        if (rotation != null) ...[
          const SizedBox(height: 8),
          Text(
            '${ScheduleRotation.label(rotation.indexFor(selected))} of rotation${current!.hasWeek(selected) ? '' : ' · Repeating timetable'}',
          ),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            IconButton(
              tooltip: 'Previous week',
              onPressed: () => setState(
                () => selected = DateTime(
                  selected.year,
                  selected.month,
                  selected.day - 7,
                ),
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
                () => selected = DateTime(
                  selected.year,
                  selected.month,
                  selected.day + 7,
                ),
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
                      color: periodBackground(l),
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
  List<Widget> settings() {
    final pages = <_SettingsPage, (String, String, IconData)>{
      _SettingsPage.appearance: ('Appearance', 'Theme', Icons.palette_outlined),
      _SettingsPage.timetable: (
        'Timetable',
        'Schedule rotation and bell times',
        Icons.calendar_view_week_outlined,
      ),
      _SettingsPage.data: (
        'Data',
        'Import, export and clear snapshots',
        Icons.storage_outlined,
      ),
      _SettingsPage.account: (
        'Account',
        'Sync timetable, homework and preferences',
        Icons.account_circle_outlined,
      ),
      _SettingsPage.updates: (
        'Updates',
        'Check for a new version',
        Icons.system_update_alt,
      ),
    };
    final section = settingsPage;
    return [
      if (section != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => settingsPage = null),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Settings'),
          ),
        ),
      Text(
        section == null ? 'Settings' : pages[section]!.$1,
        style: Theme.of(context).textTheme.headlineLarge
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 20),
      ...switch (section) {
        null => [
          for (final entry in pages.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: ListTile(
                  leading: Icon(entry.value.$3),
                  title: Text(entry.value.$1),
                  subtitle: Text(entry.value.$2),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => setState(() => settingsPage = entry.key),
                ),
              ),
            ),
        ],
        _SettingsPage.appearance => [
          panel(
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final theme in ThemeMode.values)
                  ChoiceChip(
                    label: Text(theme.name),
                    selected: widget.mode == theme,
                    onSelected: (_) => setTheme(theme),
                  ),
              ],
            ),
          ),
        ],
        _SettingsPage.timetable => timetableSettings(),
        _SettingsPage.data => dataSettings(),
        _SettingsPage.account => [accountSettings()],
        _SettingsPage.updates => [updateCard(showCheck: true)],
      },
    ];
  }

  Widget accountSettings() {
    final session = account;
    final available = AccountClient.endpoint != null;
    final canAct = available && !syncing && !busy;
    return panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            available
                ? 'Sync your timetable, homework and settings across devices. Periodify encrypts the data on your device before uploading it.'
                : 'Account sync is unavailable in this build.',
          ),
          if (syncStatus case final status?) ...[
            const SizedBox(height: 12),
            Text(status, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: session == null
                ? [
                    FilledButton(
                      onPressed: canAct ? createAccount : null,
                      child: const Text('Create sync account'),
                    ),
                    OutlinedButton(
                      onPressed: canAct ? signIn : null,
                      child: const Text('Sign in'),
                    ),
                  ]
                : [
                    if (syncConflict) ...[
                      FilledButton(
                        onPressed: canAct
                            ? () => syncNow(useAccount: true)
                            : null,
                        child: const Text('Use account data'),
                      ),
                      OutlinedButton(
                        onPressed: canAct
                            ? () => syncNow(keepDevice: true)
                            : null,
                        child: const Text('Keep this device’s data'),
                      ),
                    ] else
                      FilledButton(
                        onPressed: canAct ? syncNow : null,
                        child: const Text('Sync now'),
                      ),
                    OutlinedButton(
                      onPressed: canAct ? () => showAccountCode(session) : null,
                      child: const Text('Show sync code'),
                    ),
                    TextButton(
                      onPressed: canAct ? signOut : null,
                      child: const Text('Sign out'),
                    ),
                    TextButton(
                      onPressed: canAct
                          ? () => signOut(deleteCloud: true)
                          : null,
                      child: const Text('Delete account'),
                    ),
                  ],
          ),
        ],
      ),
    );
  }

  List<Widget> timetableSettings() => [
    panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<int>(
            initialValue: repeatWeeks,
            decoration: const InputDecoration(labelText: 'Schedule rotation'),
            isExpanded: true,
            items: [
              const DropdownMenuItem(value: 0, child: Text('No repeat')),
              for (var weeks = 1; weeks <= ScheduleRotation.maxWeeks; weeks++)
                DropdownMenuItem(
                  value: weeks,
                  child: Text('Every $weeks ${weeks == 1 ? 'week' : 'weeks'}'),
                ),
            ],
            onChanged: busy
                ? null
                : (weeks) {
                    if (weeks != null) setRepeatWeeks(weeks);
                  },
          ),
          const SizedBox(height: 12),
          Text(
            repeatWeeks > 0
                ? 'Scrape $repeatWeeks ${repeatWeeks == 1 ? 'teaching week' : 'consecutive teaching weeks'} in one session to set your rotation.'
                : 'Show lessons on the dates you saved from Bromcom.',
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
  ];

  List<Widget> dataSettings() => [
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
                onPressed: busy ? null : importData,
                icon: const Icon(Icons.file_open_outlined),
                label: const Text('Import'),
              ),
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
        content: Text(
          account == null
              ? 'Remove the saved timetable and homework from this device and its paired watch?'
              : 'Remove the saved timetable and homework from your synced devices and paired watch?',
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
    if (mounted) {
      setState(() => snapshot = null);
      unawaited(syncNow());
    }
  }
}
