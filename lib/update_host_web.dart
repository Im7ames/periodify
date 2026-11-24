import 'package:web/web.dart' as web;

Future<void> installUpdate(Uri? package, String? digest, int bytes) async {
  web.window.location.reload();
}
