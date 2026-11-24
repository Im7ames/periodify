import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'model.dart';
import 'periods.dart';

class AccountData {
  const AccountData(this.snapshot, this.periods, this.repeatWeeks, this.theme);

  final Snapshot? snapshot;
  final List<SchedulePeriod> periods;
  final int repeatWeeks;
  final int theme;

  String encode() {
    final ordered = [...periods]
      ..sort((left, right) => left.bromcomLabel.compareTo(right.bromcomLabel));
    // Keep the legacy payload for plain times. Older clients reject version 2
    // instead of discarding custom names when they save another setting.
    final hasCustomNames = ordered.any(
      (period) => period.name != period.bromcomLabel,
    );
    return jsonEncode({
      'schema': hasCustomNames ? 2 : 1,
      'snapshot': snapshot?.encode(),
      if (hasCustomNames)
        'periods': ordered.map((period) => period.toJson()).toList()
      else
        'bells': {
          for (final period in ordered) period.bromcomLabel: period.timeRange,
        },
      'repeatWeeks': repeatWeeks,
      'theme': theme,
    });
  }

  factory AccountData.decode(String raw) {
    final document = jsonDecode(raw) as Map<String, dynamic>;
    final snapshot = document['snapshot'] as String?;
    final repeatWeeks = document['repeatWeeks'] as int;
    final theme = document['theme'] as int;
    final schema = document['schema'];
    final supported =
        schema == 1 || (schema == 2 && document['periods'] is List);
    if (!supported ||
        repeatWeeks < 0 ||
        repeatWeeks > ScheduleRotation.maxWeeks ||
        theme < 0 ||
        theme > 2) {
      throw const FormatException('Unsupported account data.');
    }
    return AccountData(
      snapshot == null ? null : Snapshot.decode(snapshot),
      SchedulePeriod.decode(
        document['periods'],
        legacyBells: document['bells'],
      ),
      repeatWeeks,
      theme,
    );
  }

  Future<String> get fingerprint async =>
      (await Sha256().hash(utf8.encode(encode()))).toString();
}

class AccountSession {
  const AccountSession(this.code, this.revision, this.fingerprint);

  static const storage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );
  static const _key = 'periodify-sync-session-v1';

  final String code;
  final String revision;
  final String fingerprint;

  static Future<AccountSession?> restore() async {
    final raw = await storage.read(key: _key);
    if (raw == null) return null;
    final saved = jsonDecode(raw) as Map<String, dynamic>;
    return AccountSession(
      saved['code'] as String,
      saved['revision'] as String,
      saved['fingerprint'] as String,
    );
  }

  Future<void> save() => storage.write(
    key: _key,
    value: jsonEncode({
      'code': code,
      'revision': revision,
      'fingerprint': fingerprint,
    }),
  );

  static Future<void> signOut() => storage.delete(key: _key);
}

class AccountError implements Exception {
  const AccountError(this.message);
  final String message;
}

typedef RemoteAccountData = ({String revision, AccountData data});

class AccountClient {
  const AccountClient();

  static const _configured = String.fromEnvironment(
    'PERIODIFY_SYNC_URL',
    defaultValue: 'https://periodify-sync.123058.workers.dev',
  );
  static Uri? get endpoint {
    final uri = Uri.tryParse(_configured);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    return uri.resolve('/v1/state');
  }

  static String createCode() {
    final random = Random.secure();
    return _unpad(List.generate(32, (_) => random.nextInt(256)));
  }

  static String _unpad(List<int> bytes) =>
      base64UrlEncode(bytes).replaceAll('=', '');

  static Future<Hash> _derive(String code, String purpose) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(code)) {
      throw const AccountError('Enter your full Periodify sync code.');
    }
    final bytes = base64Url.decode(base64Url.normalize(code));
    if (_unpad(bytes) != code) {
      throw const AccountError('This sync code is invalid.');
    }
    return Sha256().hash([
      ...utf8.encode('Periodify sync v1 $purpose\u0000'),
      ...bytes,
    ]);
  }

  Future<Uint8List> encrypt(String code, AccountData data) async {
    final key = SecretKey((await _derive(code, 'encryption')).bytes);
    final box = await AesGcm.with256bits().encrypt(
      utf8.encode(data.encode()),
      secretKey: key,
    );
    return Uint8List.fromList([
      ...box.nonce,
      ...box.mac.bytes,
      ...box.cipherText,
    ]);
  }

  Future<AccountData> decrypt(String code, Uint8List bytes) async {
    if (bytes.length < 28) {
      throw const AccountError('Account data is incomplete.');
    }
    final key = SecretKey((await _derive(code, 'encryption')).bytes);
    final box = SecretBox(
      bytes.sublist(28),
      nonce: bytes.sublist(0, 12),
      mac: Mac(bytes.sublist(12, 28)),
    );
    final clear = await AesGcm.with256bits().decrypt(box, secretKey: key);
    return AccountData.decode(utf8.decode(clear));
  }

  Future<http.Response> _send(
    String method,
    String code, {
    Uint8List? body,
    Map<String, String> headers = const {},
  }) async {
    final uri = endpoint;
    if (uri == null) {
      throw const AccountError('Account sync is unavailable in this build.');
    }
    final token = _unpad((await _derive(code, 'authentication')).bytes);
    final request = http.Request(method, uri)..followRedirects = false;
    request.headers.addAll({...headers, 'Authorization': 'Bearer $token'});
    if (body != null) request.bodyBytes = body;
    final client = http.Client();
    try {
      return await client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 15));
    } finally {
      client.close();
    }
  }

  Future<RemoteAccountData?> read(String code) async {
    final response = await _send('GET', code);
    if (response.statusCode == 404) return null;
    final revision = _revision(response, 200);
    return (revision: revision, data: await decrypt(code, response.bodyBytes));
  }

  Future<AccountSession> write(
    String code,
    AccountData data, {
    String? revision,
  }) async {
    final response = await _send(
      'PUT',
      code,
      body: await encrypt(code, data),
      headers: {
        'Content-Type': 'application/octet-stream',
        if (revision == null) 'If-None-Match': '*' else 'If-Match': revision,
      },
    );
    return AccountSession(
      code,
      _revision(response, revision == null ? 201 : 204),
      await data.fingerprint,
    );
  }

  Future<void> delete(AccountSession session) async {
    final response = await _send(
      'DELETE',
      session.code,
      headers: {'If-Match': session.revision},
    );
    if (response.statusCode != 204) throw _error(response.statusCode);
  }

  String _revision(http.Response response, int expected) {
    if (response.statusCode != expected) throw _error(response.statusCode);
    return response.headers['etag'] ??
        (throw const AccountError('Missing account revision.'));
  }

  AccountError _error(int status) => switch (status) {
    412 => const AccountError(
      'Another device updated the account. Sync again before saving.',
    ),
    413 => const AccountError('This snapshot is too large to sync.'),
    429 => const AccountError(
      'The sync service is busy. Try again in a minute.',
    ),
    _ => const AccountError('The sync service could not complete the request.'),
  };
}
