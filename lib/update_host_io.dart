import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

const _androidUpdates = MethodChannel('com.im7ames.periodify/update');

Future<void> installUpdate(Uri? package, String? digest, int bytes) async {
  if (package == null || digest == null) throw StateError('No installer');
  final cache = Platform.isAndroid
      ? await _androidUpdates.invokeMethod<String>('cacheDirectory')
      : Directory.systemTemp.path;
  if (cache == null) throw StateError('No update cache directory');
  final root = await Directory('$cache/periodify-updates')
      .create(recursive: true);
  final directory = await root.createTemp('download-');
  final file = File('${directory.path}/${package.pathSegments.last}');
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client.getUrl(package);
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode != HttpStatus.ok) {
      throw StateError('Installer download unavailable');
    }
    var downloaded = 0;
    final sink = file.openWrite();
    try {
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        downloaded += chunk.length;
        if (downloaded > bytes) {
          throw StateError('Installer is larger than expected');
        }
        sink.add(chunk);
      }
    } finally {
      await sink.close();
    }
    if (downloaded != bytes ||
        (await sha256.bind(file.openRead()).first).toString() != digest) {
      throw StateError('Installer checksum mismatch');
    }
    if (Platform.isWindows) {
      await Process.start(file.path, [
        '/SILENT',
        '/NORESTART',
        '/PERIODIFYUPDATE',
      ], mode: ProcessStartMode.detached);
      await windowManager.close();
    } else if (Platform.isAndroid) {
      await _androidUpdates.invokeMethod<void>('install', file.path);
    } else if (Platform.isLinux &&
        await File('/usr/bin/pkexec').exists() &&
        await File('/usr/bin/dpkg').exists()) {
      final installed = await Process.run('/usr/bin/pkexec', [
        '/usr/bin/dpkg',
        '-i',
        file.path,
      ]);
      if (installed.exitCode != 0) {
        throw StateError('Linux did not install the update');
      }
      await directory.delete(recursive: true);
      await Process.start(
        Platform.resolvedExecutable,
        [],
        mode: ProcessStartMode.detached,
      );
      exit(0);
    } else {
      final opened = await Process.run(
        Platform.isMacOS ? '/usr/bin/open' : 'xdg-open',
        [file.path],
      );
      if (opened.exitCode != 0) {
        throw StateError('The system could not open the installer');
      }
    }
  } catch (_) {
    if (await directory.exists()) await directory.delete(recursive: true);
    rethrow;
  } finally {
    client.close();
  }
}
