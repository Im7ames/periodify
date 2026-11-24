import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'update_host_stub.dart'
    if (dart.library.io) 'update_host_io.dart'
    if (dart.library.js_interop) 'update_host_web.dart';

const _repository = 'Im7ames/periodify';
const _releaseBase = 'https://github.com/$_repository/releases';

int compareVersions(String a, String b) {
  final first = a.split('.').map(int.parse).toList();
  final second = b.split('.').map(int.parse).toList();
  for (var index = 0; index < 3; index++) {
    final result = first[index].compareTo(second[index]);
    if (result != 0) return result;
  }
  return 0;
}

class AppUpdate {
  const AppUpdate(this.version, {this.package, this.sha256, this.bytes = 0});

  final String version;
  final Uri? package;
  final String? sha256;
  final int bytes;

  static const names = {
    TargetPlatform.android: ['periodify-android.apk'],
    TargetPlatform.windows: [
      'periodify-windows.exe',
      'periodify-windows-unsigned.exe',
    ],
    TargetPlatform.macOS: [
      'periodify-macos.dmg',
      'periodify-macos-unnotarized.dmg',
    ],
    TargetPlatform.linux: ['periodify-linux.deb'],
  };

  static AppUpdate? fromManifest(
    String version,
    String raw,
    TargetPlatform platform,
  ) {
    final document = jsonDecode(raw) as Map<String, dynamic>;
    if (document['schema'] != 1 || document['version'] != version) return null;
    final assets = (document['assets'] as List)
        .whereType<Map<String, dynamic>>();
    for (final name in names[platform] ?? const <String>[]) {
      final candidate = assets
          .where((asset) => asset['name'] == name)
          .firstOrNull;
      if (candidate == null) continue;
      final url = '$_releaseBase/download/v$version/$name';
      final digest = candidate['sha256'];
      final size = candidate['size'];
      if (candidate['url'] == url &&
          digest is String &&
          size is int &&
          size > 0 &&
          size <= 300000000 &&
          RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
        return AppUpdate(
          version,
          package: Uri.parse(url),
          sha256: digest,
          bytes: size,
        );
      }
    }
    return null;
  }

  String get action => switch (kIsWeb ? null : defaultTargetPlatform) {
    TargetPlatform.android => 'Install update',
    TargetPlatform.macOS => 'Open installer',
    _ => 'Restart to update',
  };

  Future<void> install() => installUpdate(package, sha256, bytes);
}

class UpdateService {
  const UpdateService();

  static final _versionPattern = RegExp(r'^\d+\.\d+\.\d+$');

  Future<String> localVersion() async {
    final source = await rootBundle.loadString('pubspec.yaml');
    return RegExp(
      r'^version:\s*(\d+\.\d+\.\d+)',
      multiLine: true,
    ).firstMatch(source)!.group(1)!;
  }

  Future<AppUpdate?> check() async {
    final installed = await localVersion();
    if (kIsWeb) {
      final metadata = Uri.base
          .resolve('version.json')
          .replace(
            queryParameters: {
              'check': DateTime.now().millisecondsSinceEpoch.toString(),
            },
          );
      final response = await http
          .get(metadata)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final version =
          (jsonDecode(response.body) as Map<String, dynamic>)['version']
              as String?;
      return version != null &&
              _versionPattern.hasMatch(version) &&
              compareVersions(version, installed) > 0
          ? AppUpdate(version)
          : null;
    }
    if (!AppUpdate.names.containsKey(defaultTargetPlatform)) return null;

    final response = await http
        .get(
          Uri.https('api.github.com', '/repos/$_repository/releases', {
            'per_page': '12',
          }),
          headers: {'Accept': 'application/vnd.github+json'},
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw StateError('Release feed unavailable');
    }

    final versions = <String>[];
    for (final release in (jsonDecode(
      response.body,
    ) as List).whereType<Map<String, dynamic>>()) {
      final tag = release['tag_name'];
      if (tag is! String || !tag.startsWith('v') || release['draft'] == true) {
        continue;
      }
      final version = tag.substring(1);
      if (!_versionPattern.hasMatch(version) ||
          compareVersions(version, installed) <= 0) {
        continue;
      }
      if ((release['assets'] as List).whereType<Map<String, dynamic>>().any(
        (asset) => asset['name'] == 'updates.json',
      )) {
        versions.add(version);
      }
    }
    versions.sort((a, b) => compareVersions(b, a));
    for (final version in versions) {
      final manifest = await http
          .get(Uri.parse('$_releaseBase/download/v$version/updates.json'))
          .timeout(const Duration(seconds: 12));
      if (manifest.statusCode != 200) continue;
      final update = AppUpdate.fromManifest(
        version,
        manifest.body,
        defaultTargetPlatform,
      );
      if (update != null) return update;
    }
    return null;
  }
}
