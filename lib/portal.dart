import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'model.dart';

class PortalPage extends StatefulWidget {
  const PortalPage({super.key, this.previous});
  final Snapshot? previous;
  @override
  State<PortalPage> createState() => _PortalPageState();
}

class _PortalPageState extends State<PortalPage> {
  InAppWebViewController? controller;
  bool busy = false;
  String? error;
  double progress = 0;
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
            Snapshot(
              lessons: previous.lessons,
              scrapedAt: previous.scrapedAt,
              week: previous.week,
              school: previous.school,
              homework: homework,
              homeworkAt: DateTime.now(),
            ),
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
      if (mounted) {
        Navigator.pop(
          context,
          Snapshot(
            lessons:
                [
                  ...?widget.previous?.lessons.where((l) {
                    final d = DateTime.parse(l.date);
                    final start = DateTime.parse(result.week);
                    return d.isBefore(start) ||
                        !d.isBefore(start.add(const Duration(days: 7)));
                  }),
                  ...result.lessons,
                ]..sort((a, b) {
                  final day = a.date.compareTo(b.date);
                  return day != 0 ? day : a.order.compareTo(b.order);
                }),
            scrapedAt: result.scrapedAt,
            week: result.week,
            homework: widget.previous?.homework ?? [],
            homeworkAt: widget.previous?.homeworkAt,
          ),
        );
      }
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Bromcom'),
      actions: [
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
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              error ?? 'Sign in using Bromcom’s Microsoft button. Select a week in My Timetable, then press Scrape. Your password stays in the sign-in page.',
            ),
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
