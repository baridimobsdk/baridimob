// Lists your BaridiMob accounts.
//
//   BARIDIMOB_LOGIN=... BARIDIMOB_PASSWORD=... dart run example/example.dart
//
// The first run asks for the SMS code that confirms this device. The device
// is saved in .baridimob/session.json, so later runs need no SMS.
import 'dart:io';

import 'package:baridimob/baridimob.dart';

Future<void> main() async {
  final login = Platform.environment['BARIDIMOB_LOGIN'];
  final password = Platform.environment['BARIDIMOB_PASSWORD'];
  if (login == null || password == null) {
    stderr.writeln('Set BARIDIMOB_LOGIN and BARIDIMOB_PASSWORD.');
    exitCode = 64;
    return;
  }

  final bm = BaridiMob(storage: FileStorage('.baridimob/session.json'));
  try {
    final result = await bm.auth.login(login: login, password: password);
    if (result.isOtpRequired) {
      await bm.auth.requestDeviceOtp();
      stdout.write('SMS code: ');
      await bm.auth.confirmDevice(stdin.readLineSync()?.trim() ?? '');
    }

    for (final account in await bm.accounts.list()) {
      print('${account.number}: ${account.balance} ${account.currency}');
    }
  } on BaridiMobError catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  } finally {
    bm.close();
  }
}
