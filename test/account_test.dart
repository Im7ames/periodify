import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:periodify/account.dart';
import 'package:periodify/periods.dart';

void main() {
  test('account codes encrypt and authenticate the synced data', () async {
    const client = AccountClient();
    final code = AccountClient.createCode();
    const clear = AccountData(
      null,
      [
        SchedulePeriod(
          name: 'Tutorial',
          bromcomLabel: 'P7',
          start: 540,
          end: 600,
        ),
      ],
      2,
      1,
    );
    final encrypted = await client.encrypt(code, clear);
    final second = await client.encrypt(code, clear);
    expect(encrypted, isNot(equals(second)));
    expect((await client.decrypt(code, encrypted)).encode(), clear.encode());
    expect(jsonDecode(clear.encode())['schema'], 2);
    await expectLater(
      client.decrypt(AccountClient.createCode(), encrypted),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('migrates a legacy account without changing its canonical data', () {
    const legacy =
        '{"schema":1,"snapshot":null,"bells":{"P1":"09:00-10:00"},"repeatWeeks":2,"theme":1}';
    final migrated = AccountData.decode(legacy);
    expect(migrated.periods.single.name, 'P1');
    expect(migrated.periods.single.start, 540);
    expect(migrated.encode(), legacy);
    expect(SchedulePeriod.matchKey('Period 07'), SchedulePeriod.matchKey('P7'));
  });
}
