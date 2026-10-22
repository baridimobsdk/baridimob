# baridimob

**Unofficial Dart and Flutter SDK for BaridiMob — Algérie Poste (بريد الجزائر)**

[![pub package](https://img.shields.io/pub/v/baridimob)](https://pub.dev/packages/baridimob)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/baridimobsdk/baridimob/blob/main/LICENSE)

Read your BaridiMob accounts, verify incoming payments, send transfers, pay bills and make cardless ATM withdrawals from Dart and Flutter.

- Works in Flutter apps (Android, iOS, macOS, Windows, Linux) and in Dart servers and scripts
- Fully typed, documented API
- Automatic session renewal
- Same API and session format as the [TypeScript](https://www.npmjs.com/package/baridimob) and [Python](https://pypi.org/project/baridimob/) SDKs

> **Status:** version 0.x — the API may still change between minor versions.

---

## Contents

- [Installation](#installation)
- [Quick start](#quick-start)
- [How login works](#how-login-works)
- [Accounts and history](#accounts-and-history)
- [Cards](#cards)
- [Verify an incoming payment](#verify-an-incoming-payment)
- [Transfers](#transfers)
- [Bill payments](#bill-payments)
- [Withdrawals without a card](#withdrawals-without-a-card)
- [Receipts and profile](#receipts-and-profile)
- [Session storage](#session-storage)
- [Configuration](#configuration)
- [Error handling](#error-handling)
- [Platform support](#platform-support)
- [Security](#security)

---

## Installation

```bash
flutter pub add baridimob   # Flutter app
dart pub add baridimob      # Dart server or script
```

Requires **Dart 3.4 or later** (Flutter 3.22 or later).

## Quick start

```dart
import 'package:baridimob/baridimob.dart';

final bm = BaridiMob(storage: FileStorage('.baridimob/session.json'));

// 1. Log in
final result = await bm.auth.login(login: 'your-login', password: 'your-password');

// 2. First time on this device only: confirm it by SMS
if (result.isOtpRequired) {
  await bm.auth.requestDeviceOtp();          // an SMS code is sent to your phone
  await bm.auth.confirmDevice('123456');     // the code you received
}

// 3. Use the API
final accounts = await bm.accounts.list();
print('${accounts.first.number}: ${accounts.first.balance}');
```

A complete command-line example is in [`example/example.dart`](example/example.dart).

## How login works

1. **First login on a device:** BaridiMob asks to confirm the new device. `login()` returns a result with `isOtpRequired == true`. Call `requestDeviceOtp()`, then `confirmDevice(code)` with the SMS code.
2. **The device keys and session are saved** in the storage you provide.
3. **Next logins** reuse the saved device. No SMS is needed.
4. **When the session expires**, the SDK logs in again automatically and retries the request.

The first login generates an RSA key pair for the device. This runs in a background isolate, so your Flutter UI stays responsive.

```dart
bm.auth.currentDeviceId;   // the registered device id, or null
await bm.auth.logout();    // ends the session and deletes the saved device:
                           // the next login will ask for an SMS code again
```

## Accounts and history

```dart
final accounts = await bm.accounts.list();          // all accounts
final account  = await bm.accounts.get(accounts.first.id);
final balance  = await bm.accounts.balance();       // balance of the first account
```

**Transaction history**

```dart
// One page
final page = await bm.accounts.transactions(
  account: account.number,
  from: DateTime(2026, 1, 1),
  to: DateTime.now(),
  page: 1,
);

// All pages at once
final all = await bm.accounts.allTransactions(account: account.number, from: DateTime(2026, 1, 1));

// Stream page by page (memory-friendly)
await for (final tx in bm.accounts.iterTransactions(account: account.number)) {
  print('${tx.date} ${tx.amount} ${tx.description}');
}

// Find one transaction by its reference number
final tx = await bm.accounts.findTransaction(account: account.number, refNum: '012345678901');
```

Each `Transaction` contains `amount` (positive = incoming, negative = outgoing), `currency`, `description`, `date` (UTC), `fee`, `refNum`, and the original server data in `raw`.

Dates are sent to the server as calendar days in Algeria time: `DateTime(2026, 1, 31)` always means January 31.

## Cards

```dart
final cards = await bm.cards.list();          // regular and virtual
final card  = await bm.cards.get(cards.first.id);
final limits = await bm.cards.limits(card.id);

// One page, or the whole history of the card
final page = await bm.cards.history(card: card.id, from: DateTime(2026, 1, 1));
final movements = await bm.cards.allHistory(card: card.id);

// Read it page by page
await for (final movement in bm.cards.iterHistory(card: card.id)) {
  print('${movement.date} ${movement.amount}');
}
```

`BaridiMobCard` carries `number`, `name`, `brand`, `status`, `expDate`
(`yyyyMM`), `type`, `balance`, `currency`, `embossedName`, `linkedAccounts` and
the raw payload. `status` is `0` valid, `20` temporary block, `21` permanent
block, `99` expired, `12` not activated, `1` invalid PIN limit, `10` fraud
block. The class is called `Card` in the TypeScript and Python SDKs; the prefix
avoids a clash with Flutter's `Card` widget.

`number` is the full card number, exactly as BaridiMob sends it. Keep it out of
logs and error reports; `toString()` leaves it out.

`CardLimit` carries `type` (`0` amount, `1` number of operations), `amount` and
`usedAmount` or `opCount` and `usedOpCount`, `active`, `changeable`,
`permanent`, `perTransaction` and `endTime`.

`history` accepts `state: 'all' | 'hold' | 'processed'`. The card calls use the
same locale and signing as the account calls.

BaridiMob ignores the `category` filter of `/cards` (verified live), so `list()`
makes a single request that returns every card. Use `card.category` (`regular`
or `virtual`) to tell them apart.

## Verify an incoming payment

Useful for shops and services that accept payment by BaridiMob transfer. The customer gives you the transfer's reference number, and you check that the money has really arrived.

```dart
final check = await bm.payments.verifyPayment(
  refNum: '012345678901',  // reference number given by the customer
  amount: 2500,            // expected amount (optional)
);

if (check.verified) {
  // payment received: deliver the order
} else {
  print(check.reason);
}
```

| `reason` | Meaning |
|----------|---------|
| `VerifyPaymentReason.ok` | Payment found, incoming, and the amount matches |
| `VerifyPaymentReason.notFound` | No transaction with this reference number |
| `VerifyPaymentReason.notIncoming` | The transaction exists but is not money received |
| `VerifyPaymentReason.amountMismatch` | The amount differs from the expected one |
| `VerifyPaymentReason.duplicate` | Several incoming transactions share this reference: check manually |

By default, the search covers **the last 30 days** of **the first account**. Use `account`, `from` and `to` to change this.

## Transfers

Every transfer requires an SMS code. `send()` prepares the transfer and sends the SMS, then `confirm()` executes it:

```dart
final pending = await bm.transfers.send(
  amount: 1000,
  sourceId: account.number,             // your account
  targetId: '00799999000000000000',     // recipient's RIP
);

// show a screen asking the user for the SMS code, then:
final receipt = await pending.confirm('123456');
```

For full control, the same flow is available step by step: `arm()` → `requestOtp(transRef)` → `exec(..., transRef: ..., otp: ...)`.

## Bill payments

```dart
// 1. Browse what can be paid
final categories = await bm.payments.categories();
final providers  = await bm.payments.providers(categories.first.cid);

// 2. Prepare the payment
final prepared = await bm.payments.check(
  pid: providers.first.pid,
  amount: 500,
  source: const PaymentSource.card('your-card-id'),
  params: {'phone': '0600000000'},      // fields required by this provider
);

// 3. Confirm with the SMS code
await bm.payments.requestOtp(prepared.transRef);
await bm.payments.exec(
  pid: providers.first.pid,
  amount: 500,
  source: const PaymentSource.card('your-card-id'),
  params: {'phone': '0600000000'},
  transRef: prepared.transRef,
  otp: '123456',
);
```

`PaymentSource.account(id)` is part of the API, but BaridiMob currently refuses
an account as the payment source for `paymentCheck` (verified live); use a card.

**Bills through the dynamic engine.** Some services (Algérie Télécom, ADE,
SEAL, Sonelgaz, AADL…) return the form themselves, step by step:

```dart
final groups = await bm.payments.dynamic.groups();
final operation = groups.first.operations.first;
final card = (await bm.cards.list()).first;
final source = DynamicSource.card(card.id);

// Fill each step until BaridiMob has none left (step.done). values() adds
// what BaridiMob expects besides what is typed: hidden fields (for an
// Algérie Télécom bill, billerServiceCode=FACTURE), the payment source and
// the amount. Later steps send the current step id and every value so far.
var step = await bm.payments.dynamic.step(operation.id);
final values = <String, String>{};
while (!step.done) {
  values.addAll(step.values(
    entered: {'customerNumber': '044395258'},
    source: source,
  ));
  step = await bm.payments.dynamic.step(operation.id, values, step.id);
}

// check() moves no money and sends no SMS; for a bill, its details hold the
// subscriber, the bill and the amount due.
final checked = await bm.payments.dynamic.check(operation.id, values);
for (final detail in checked.details) {
  print('${detail.label}: ${detail.amount?.text ?? detail.text}');
}
await bm.payments.dynamic.requestOtp(checked.transRef);
final result = await bm.payments.dynamic.exec(
  operationId: operation.id,
  transRef: checked.transRef,
  otp: '123456',
  params: values,
);
print('${result.recentOpId} ${result.status}');
```

- **Payment source:** dynamic forms name it with `DynamicSource`
  (`CLIENT_CARD_ID` for a card, `ACCOUNT_NUMBER` for an account). BaridiMob
  answers result 2 to the `1`/`2` of `payments.check`.
- **Amounts:** a `money` field may come filled (`input.amount`, a bill's amount
  due) or offer amounts to pick (`input.amountChoices` when
  `input.amountMode == DynamicAmountMode.select`); pass the chosen one as
  `values(amount: ...)`. Read-only fields (`input.readonly`) keep BaridiMob's
  value. Fields come in the order of their `ordinalNumber`.
- **Refusals** carry BaridiMob's own words, for example
  «لا توجد فواتير غير مدفوعة» (no unpaid bills): see
  [Error handling](#error-handling).

`check()` returns `DynamicCheckResult` (`transRef`, `confirmationType`, `fee`,
`planDate`, `details`, `amount`); `exec()` returns `DynamicExecResult`
(`recentOpId`, `recentOpType`, `status`, `details`). `complete()` is for an
extra confirmation step (such as 3D Secure) when the server asks for one. All
values are sent as `param.<id>`.

`groups()`, `operation()`, `step()` and `check()` (an internet top-up with a
card source) are verified against the live server. `exec()` and `complete()`
use the endpoints of the official app but have not been executed live yet.

## Withdrawals without a card

A cardless code takes cash out of an Algérie Poste ATM without the card.

```dart
// The codes not used yet.
for (final code in await bm.cardless.list()) {
  print('${code.code} · ${code.amount} ${code.currency} · ${code.id}');
}

final account = (await bm.accounts.list()).first;
final code = await bm.cardless.create(
  amount: 2000,
  source: CardlessSource.account(account.id), // or CardlessSource.card(card.id)
  expiresAt: DateTime.now().add(const Duration(days: 1)), // less than six months
);
print('${code.code} (authorisation ${code.id})');

// While it is unused, it can be deleted.
await bm.cardless.delete(code.id);
```

`create()` reads the form again each time (its hidden `mb_model` is signed per
request) and is never retried automatically; the official app asks for no SMS
code here. Treat `code` like cash.

> **Partly verified live:** `form()` and `list()` are verified. `create()`
> reached BaridiMob's balance check (an account without funds was refused with
> «رصيد الحساب غير كافٍ»); `delete()` has not run against a real code yet.

## Receipts and profile

```dart
final operations = await bm.receipts.list();                   // recent operations
final pdf = await bm.receipts.download(operations.first.uid);  // PDF as Uint8List
await File('receipt.pdf').writeAsBytes(pdf);

// The receipt of a movement from the history, or null
final page = await bm.accounts.transactions(account: account);
final receipt = await bm.receipts.downloadFor(page.transactions.first);
if (receipt != null) await File('movement.pdf').writeAsBytes(receipt);

final profile = await bm.profile.get();                        // account holder information
```

`receipts.find(transaction)` returns the recent operation behind a history
movement, matched by its reference number (or by time and amount).
BaridiMob keeps receipts only for the last few operations, so `find()` and
`downloadFor()` return `null` for older ones.

## Session storage

The storage keeps the device keys and session cookies between runs.

| Storage | Use case |
|---------|----------|
| `FileStorage(path)` | Servers, scripts and desktop apps: saved to a JSON file |
| `MemoryStorage()` | Tests and short-lived processes: lost when the process stops |
| Your own | Mobile secure storage, database, secret manager… |

**In a Flutter mobile app, use the platform secure storage.** For example with [`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage):

```dart
import 'dart:convert';

import 'package:baridimob/baridimob.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureSessionStorage implements SessionStorage {
  static const _storage = FlutterSecureStorage();
  static const _key = 'baridimob_session';

  @override
  Future<StoredSession?> load() async {
    final json = await _storage.read(key: _key);
    return json == null
        ? null
        : StoredSession.fromJson(jsonDecode(json) as Map<String, Object?>);
  }

  @override
  Future<void> save(StoredSession session) =>
      _storage.write(key: _key, value: jsonEncode(session.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

final bm = BaridiMob(storage: SecureSessionStorage());
```

The session JSON is the same as in the TypeScript and Python SDKs. You can also move a session manually with `bm.exportSession()` and `bm.importSession(session)`.

## Configuration

All options are optional:

```dart
final bm = BaridiMob(
  storage: FileStorage('session.json'),
  locale: BaridiMobLocale.fr,              // ar (default), fr or en
  timeout: const Duration(seconds: 30),    // request timeout
  retries: 2,                              // retries on network errors
);
```

| Option | Default | Description |
|--------|---------|-------------|
| `storage` | `MemoryStorage()` | Where the session is saved. With memory storage, the device must be confirmed again at every start. |
| `locale` | `BaridiMobLocale.ar` | Language of server messages and labels |
| `timeout` | 30 seconds | Request timeout |
| `retries` | `2` | Number of retries on network errors. Requests that send an OTP or move money are never retried. |
| `deviceName` | `'BaridiMob SDK'` | Device name shown in BaridiMob |
| `timeZone` | `'GMT+01:00'` | Time zone sent to the server |
| `baseUrl` | official server | Server URL (must be HTTPS) |
| `allowInsecure` | `false` | Allow plain HTTP for non-local URLs (testing only) |
| `httpClient` | new `http.Client` | Your own [`http.Client`](https://pub.dev/packages/http) (proxy, logging…) |

Call `bm.close()` when you no longer need the client.

## Error handling

All errors extend `BaridiMobError`, so you can catch them precisely:

```dart
try {
  await bm.auth.login(login: login, password: password);
} on InvalidCredentialsError {
  // wrong login or password
} on NetworkError {
  // no connection
}
```

| Error | When |
|-------|------|
| `InvalidCredentialsError` | Wrong login or password |
| `InvalidOtpError` / `ExpiredOtpError` | Wrong or expired SMS code |
| `TooManyAttemptsError` | Too many failed attempts |
| `AccountLockedError` | The account is locked |
| `PasswordExpiredError` | The password must be changed in the official app |
| `DeviceConfirmationRequiredError` | The device is no longer trusted: confirm it again by SMS |
| `SessionExpiredError` | Session expired and no credentials to log in again |
| `NetworkError` / `TimeoutError` | Connection problem |
| `ServerError` | The server returned an error |
| `ApiResultError` | Any other server error. Inspect `resultCode` and `resultName`. |

When BaridiMob explains a refusal, the error `message` is its own words, in the
session's language (for example «لا توجد فواتير غير مدفوعة»), also in
`description`.

## Platform support

| Platform | Supported |
|----------|-----------|
| Android, iOS | Yes |
| macOS, Windows, Linux | Yes |
| Dart servers and scripts | Yes |
| Web | No: browsers block direct requests to the BaridiMob server (CORS) |

- **Android:** release builds need the `INTERNET` permission in `AndroidManifest.xml`.
- **macOS:** enable the `com.apple.security.network.client` entitlement.

## Security

- **The saved session is a live credential.** It contains the session cookies and the device private key. Never commit it or log it. In a mobile app, keep it in the platform secure storage; on a server, encrypt it.
- **HTTPS is enforced.** Plain HTTP is refused, except for `localhost` / `127.0.0.1` or with `allowInsecure: true`.
- **Moving money always requires an SMS code** that you pass explicitly. Reading data never does.
- Add `.baridimob/` (or wherever you store the session file) to your `.gitignore`.

## Disclaimer

This is an independent community project. It is **not affiliated with, endorsed by, or supported by Algérie Poste**. BaridiMob may change its service at any time, which can break this SDK. Use it at your own risk.

## License

MIT
