import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:intl/intl.dart';

import 'model.dart';
import 'windows_title_bar.dart';

class PortalPage extends StatefulWidget {
  const PortalPage({super.key, this.previous, this.repeatWeeks = 0});
  final Snapshot? previous;
  final int repeatWeeks;
  @override
  State<PortalPage> createState() => _PortalPageState();
}

class _PortalPageState extends State<PortalPage> {
  InAppWebViewController? controller;
  bool busy = false;
  bool homeworkOpen = false;
  String? error;
  double progress = 0;
  final captured = <Snapshot>[];

  DateTime? get nextWeek => captured.isEmpty
      ? null
      : DateTime.parse('${captured.first.week}T00:00:00Z')
            .add(Duration(days: captured.length * 7));

  String get instructions {
    if (homeworkOpen) {
      return 'Open the Homework table, then press Scrape homework.';
    }
    if (widget.repeatWeeks <= 1) {
      return 'Sign in with Microsoft. Open My Timetable, choose a week, then press Scrape.';
    }
    final week = ScheduleRotation.label(captured.length);
    final next = nextWeek;
    if (next == null) {
      return 'Open My Timetable after signing in. Choose the teaching week that starts your rotation, then scrape $week.';
    }
    return '${ScheduleRotation.label(captured.length - 1)} captured. Select the week starting ${DateFormat('d MMM y').format(next)} in Bromcom, then scrape $week.';
  }

  Future<void> scrape() async {
    if (busy || controller == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final url = await controller!.getUrl();
      if (url?.scheme != 'https' ||
          url?.host != 'www.bromcomvle.com' ||
          !['/timetable', '/homework'].contains(url?.path.toLowerCase())) {
        throw const FormatException(
          'Sign in with Microsoft, open My Timetable, and select your week first.',
        );
      }
      if (url?.path.toLowerCase() == '/homework') {
        if (captured.isNotEmpty) {
          throw const FormatException(
            'Finish the timetable rotation before scraping homework.',
          );
        }
        final previous = widget.previous;
        if (previous == null) {
          throw const FormatException(
            'Scrape a timetable first, then return to import homework.',
          );
        }
        final source = await controller!.evaluateJavascript(
          source: "document.querySelector('#HomeworkTable')?.outerHTML || ''",
        );
        final homework = parseHomework(source as String? ?? '');
        if (mounted) {
          Navigator.pop(
            context,
            previous.withHomework(homework, DateTime.now()),
          );
        }
        return;
      }
      // This is the only extraction call. No page-load or scheduled scraping.
      final source = await controller!.evaluateJavascript(
        source: r'''(() => {
        const table = document.querySelector('table#Timetable');
        const select = document.querySelector('#WeekStartDate');
        if (!table || !select || document.querySelector('#loading')?.offsetParent) return '';
        const copy = select.cloneNode(true);
        [...copy.options].forEach(o => {o.removeAttribute('selected'); if(o.value === select.value) o.setAttribute('selected', 'selected');});
        return table.outerHTML + copy.outerHTML;
      })()''',
      );
      final result = parseTimetable(source as String? ?? '');
      final next = nextWeek;
      if (next != null && result.week != dayKey(next)) {
        throw FormatException(
          'Select the week starting ${DateFormat('d MMM y').format(next)} for ${ScheduleRotation.label(captured.length)}.',
        );
      }
      if (!mounted) return;
      captured.add(result);
      if (captured.length < widget.repeatWeeks) return;

      final rotation = widget.repeatWeeks == 0
          ? null
          : ScheduleRotation(widget.repeatWeeks, captured.first.teachingWeek);
      Navigator.pop(
        context,
        mergeTimetableWeeks(widget.previous, captured, rotation),
      );
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException ? e.message : 'Could not read the portal. Please wait for it to load and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      PopupMenuButton<String>(
        tooltip: 'Portal section',
        onSelected: (path) => controller?.loadUrl(
          urlRequest: URLRequest(
            url: WebUri('https://www.bromcomvle.com/$path'),
          ),
        ),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'Timetable', child: Text('Timetable')),
          PopupMenuItem(value: 'Homework', child: Text('Homework')),
        ],
      ),
    ];
    const title = Text('Bromcom', maxLines: 1, overflow: TextOverflow.ellipsis);
    return Scaffold(
      appBar: usesWindowsTitleBar
          ? WindowsTitleBar(
              title: title,
              leading: const BackButton(),
              actions: actions,
            )
          : AppBar(title: title, actions: actions),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(error ?? instructions),
            ),
            if (widget.repeatWeeks > 1)
              LinearProgressIndicator(
                value: captured.length / widget.repeatWeeks,
                semanticsLabel:
                    '${captured.length} of ${widget.repeatWeeks} weeks captured',
              ),
            if (progress < 1) LinearProgressIndicator(value: progress),
            Expanded(
              child: InAppWebView(
                initialUrlRequest: URLRequest(
                  url: WebUri('https://www.bromcomvle.com/'),
                ),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  useShouldOverrideUrlLoading: true,
                  supportMultipleWindows: false,
                ),
                onWebViewCreated: (c) => controller = c,
                onProgressChanged: (_, value) {
                  if (mounted) setState(() => progress = value / 100);
                },
                onLoadStop: (_, url) {
                  if (!mounted) return;
                  final isHomework =
                      url?.host == 'www.bromcomvle.com' &&
                      url?.path.toLowerCase() == '/homework';
                  setState(() => homeworkOpen = isHomework);
                },
                shouldOverrideUrlLoading: (_, action) async =>
                    action.request.url?.scheme == 'https'
                    ? NavigationActionPolicy.ALLOW
                    : NavigationActionPolicy.CANCEL,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: busy ? null : scrape,
                  icon: const Icon(Icons.download_rounded),
                  label: Text(
                    busy
                        ? 'Reading portal…'
                        : homeworkOpen
                        ? 'Scrape homework'
                        : widget.repeatWeeks > 1
                        ? 'Scrape ${ScheduleRotation.label(captured.length)}'
                        : 'Scrape visible timetable or homework',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
