<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/banner-dark.svg">
  <img src="assets/banner-light.svg" alt="baridimob — The open-source SDK for BaridiMob, Algérie Poste" width="100%">
</picture>

<br>

Read your BaridiMob accounts and cards, verify incoming payments, send transfers, pay bills and make cardless ATM withdrawals from your own code.

[![npm](https://img.shields.io/npm/v/baridimob?label=npm)](https://www.npmjs.com/package/baridimob)
[![PyPI](https://img.shields.io/pypi/v/baridimob?label=PyPI)](https://pypi.org/project/baridimob/)
[![pub.dev](https://img.shields.io/pub/v/baridimob?label=pub.dev)](https://pub.dev/packages/baridimob)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

</div>

---

## Packages

The SDK is available for three languages. All of them expose the same features with the same names.

| Language | Install | Documentation |
|----------|---------|---------------|
| **TypeScript / JavaScript** | `npm install baridimob` | [typescript/README.md](typescript/README.md) |
| **Python** | `pip install baridimob` | [python/README.md](python/README.md) |
| **Dart / Flutter** | `flutter pub add baridimob` | [dart/README.md](dart/README.md) |

## What you can do

| Feature | Description |
|---------|-------------|
| **Login** | Sign in with your BaridiMob credentials. The device is confirmed once by SMS, then reused. |
| **Accounts** | List accounts, read the balance, browse the full transaction history. |
| **Cards** | List regular and virtual cards, read a card and its limits, and browse its movements. |
| **Payment verification** | Confirm that a customer's transfer has really arrived, by reference number and amount. |
| **Transfers** | Send money to another account (always confirmed by SMS code). |
| **Bill payments** | Mobile top-up (Mobilis, Djezzy, Ooredoo) through the static payment flow, and Algérie Télécom, Sonelgaz, ADE, SEAL and other bills through the dynamic FPE form engine. |
| **Cardless withdrawals** | Create, list and delete a code for cash at an Algérie Poste ATM, without the card. |
| **Receipts** | List recent operations and download their PDF receipts. |

## Quick look

**TypeScript**

```ts
import { createBaridiMob, fileStorage } from 'baridimob';

const bm = createBaridiMob({ storage: fileStorage('./session.json') });
await bm.auth.login({ login: 'your-login', password: 'your-password' });

const balance = await bm.accounts.balance();
```

**Python**

```python
from baridimob import Config, FileStorage, create_client

bm = create_client(Config(storage=FileStorage("./session.json")))
bm.auth.login("your-login", "your-password")

balance = bm.accounts.balance()
```

**Dart / Flutter**

```dart
import 'package:baridimob/baridimob.dart';

final bm = BaridiMob(storage: FileStorage('session.json'));
await bm.auth.login(login: 'your-login', password: 'your-password');

final balance = await bm.accounts.balance();
```

The first login on a new machine asks for an SMS code. See each package's documentation for the full flow.

## Repository layout

```
typescript/   npm package "baridimob"
python/       PyPI package "baridimob"
dart/         pub.dev package "baridimob" (Dart and Flutter)
```

## Security

This library handles real banking credentials. Please read this carefully:

- **The saved session is a live credential.** Anyone who has the session file can access the account. Never commit it, share it, or log it. Encrypt it at rest in production.
- **HTTPS is enforced.** Plain HTTP is refused, except for `localhost` during development.
- **Moving money always requires an SMS code** that you pass explicitly. Read-only operations never do.

If you find a security issue, please report it privately instead of opening a public issue.

## Disclaimer

This is an independent community project. It is **not affiliated with, endorsed by, or supported by Algérie Poste**. BaridiMob may change its service at any time, which can break this SDK. Use it at your own risk and in accordance with Algérie Poste's terms of service.

## License

[MIT](LICENSE)
