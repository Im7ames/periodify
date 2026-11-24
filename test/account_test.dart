import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:periodify/account.dart';

void main() {
  test('account codes encrypt and authenticate the synced data', () async {
    const client = AccountClient();
    final code = AccountClient.createCode();
    const clear = AccountData(null, {'P1': '09:00-10:00'}, 2, 1);
    final encrypted = await client.encrypt(code, clear);
    final second = await client.encrypt(code, clear);
    expect(encrypted, isNot(equals(second)));
    expect((await client.decrypt(code, encrypted)).encode(), clear.encode());
    await expectLater(
      client.decrypt(AccountClient.createCode(), encrypted),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });
}
