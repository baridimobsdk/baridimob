# baridimob

**Unofficial TypeScript / JavaScript SDK for BaridiMob — Algérie Poste (بريد الجزائر)**

[![npm](https://img.shields.io/npm/v/baridimob)](https://www.npmjs.com/package/baridimob)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/baridimobsdk/baridimob/blob/main/LICENSE)
![Node](https://img.shields.io/badge/node-%3E%3D18-brightgreen)

Read your BaridiMob accounts, verify incoming payments, send transfers and pay bills from Node.js.

- Zero runtime dependencies
- Full TypeScript types
- ESM and CommonJS
- Automatic session renewal

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
- [Receipts and profile](#receipts-and-profile)
- [Session storage](#session-storage)
- [Configuration](#configuration)
- [Error handling](#error-handling)
- [Security](#security)

---

## Installation

```bash
npm install baridimob
```

Requires **Node.js 18 or later**.

## Quick start

```ts
import { createBaridiMob, fileStorage } from 'baridimob';

const bm = createBaridiMob({
  storage: fileStorage('./.baridimob/session.json'),
});

// 1. Log in
const result = await bm.auth.login({ login: 'your-login', password: 'your-password' });

// 2. First time on this machine only: confirm the device by SMS
if (result.state === 'otp_required') {
  await bm.auth.requestDeviceOtp();          // an SMS code is sent to your phone
  await bm.auth.confirmDevice('123456');     // the code you received
}

// 3. Use the API
const accounts = await bm.accounts.list();
console.log(accounts[0].number, accounts[0].balance);
```

## How login works

1. **First login on a machine:** BaridiMob asks to confirm the new device. `login()` returns `{ state: 'otp_required' }`. Call `requestDeviceOtp()`, then `confirmDevice(code)` with the SMS code.
2. **The device keys and session are saved** in the storage you provide (here a file).
3. **Next logins** reuse the saved device. No SMS is needed.
4. **When the session expires**, the SDK logs in again automatically and retries the request.

```ts
bm.auth.currentDeviceId(); // the registered device id, or null
await bm.auth.logout();    // ends the session and deletes the saved device:
                           // the next login will ask for an SMS code again
```

## Accounts and history

```ts
const accounts = await bm.accounts.list();          // all accounts
const account  = await bm.accounts.get(accounts[0].id);
const balance  = await bm.accounts.balance();        // balance of the first account
```

**Transaction history**

```ts
// One page
const page = await bm.accounts.transactions({
  account: account.number,
  from: new Date('2026-01-01'),
  to: new Date(),
  page: 1,
});

// All pages at once
const all = await bm.accounts.allTransactions({ account: account.number, from: '2026-01-01' });

// Stream page by page (memory-friendly)
for await (const tx of bm.accounts.iterTransactions({ account: account.number })) {
  console.log(tx.date, tx.amount, tx.description);
}

// Find one transaction by its reference number
const tx = await bm.accounts.findTransaction({ account: account.number, refNum: '012345678901' });
```

Each `Transaction` contains `amount` (positive = incoming, negative = outgoing), `currency`, `description`, `date`, `fee`, `refNum`, and the original server data in `raw`.

## Cards

```ts
const cards = await bm.cards.list();          // regular and virtual
const card = await bm.cards.get(cards[0]!.id);
const limits = await bm.cards.limits(card.id);

const page = await bm.cards.history({ card: card.id, from: new Date(2026, 0, 1) });
const movements = await bm.cards.allHistory({ card: card.id });

for await (const movement of bm.cards.iterHistory({ card: card.id })) {
  console.log(movement.date, movement.amount);
}
```

`Card` carries `number`, `name`, `brand`, `status`, `expDate` (`yyyyMM`),
`type`, `balance`, `currency`, `embossedName`, `linkedAccounts` and the raw
payload. `status` is `0` valid, `20` temporary block, `21` permanent block,
`99` expired, `12` not activated, `1` invalid PIN limit, `10` fraud block.

`number` is the full card number, exactly as BaridiMob sends it. Keep it out of
logs and error reports.

`CardLimit` carries `type` (`0` amount, `1` number of operations), `amount` and
`usedAmount` or `opCount` and `usedOpCount`, `active`, `changeable`,
`permanent`, `perTransaction` and `endTime`.

`history` accepts `state: 'all' | 'hold' | 'processed'`.

BaridiMob ignores the `category` filter of `/cards` (verified live), so `list()`
makes a single request that returns every card. Use `card.category` (`regular`
or `virtual`) to tell them apart.

## Verify an incoming payment

Useful for shops and services that accept payment by BaridiMob transfer. The customer gives you the transfer's reference number, and you check that the money has really arrived.

```ts
const check = await bm.payments.verifyPayment({
  refNum: '012345678901',  // reference number given by the customer
  amount: 2500,            // expected amount (optional)
});

if (check.verified) {
  // payment received: deliver the order
} else {
  console.log(check.reason);
}
```

| `reason` | Meaning |
|----------|---------|
| `ok` | Payment found, incoming, and the amount matches |
| `not_found` | No transaction with this reference number |
| `not_incoming` | The transaction exists but is not money received |
| `amount_mismatch` | The amount differs from the expected one |
| `duplicate` | Several incoming transactions share this reference: check manually |

By default, the search covers **the last 30 days** of **the first account**. Use `account`, `from` and `to` to change this.

## Transfers

Every transfer requires an SMS code. `send()` prepares the transfer and sends the SMS, then `confirm()` executes it:

```ts
const pending = await bm.transfers.send({
  amount: 1000,
  sourceId: account.number,            // your account
  targetId: '00799999000000000000',    // recipient's RIP
});

// show a screen asking the user for the SMS code, then:
const receipt = await pending.confirm('123456');
```

For full control, the same flow is available step by step: `arm()` → `requestOtp(transRef)` → `exec({ ..., transRef, otp })`.

## Bill payments

```ts
// 1. Browse what can be paid
const categories = await bm.payments.categories();
const providers  = await bm.payments.providers(categories[0].cid);

// 2. Prepare the payment
const prepared = await bm.payments.check({
  pid: providers[0].pid,
  amount: 500,
  source: { type: 'card', id: 'your-card-id' },
  params: { phone: '0600000000' },     // fields required by this provider
});

// 3. Confirm with the SMS code
await bm.payments.requestOtp(prepared.transRef);
await bm.payments.exec({
  pid: providers[0].pid,
  amount: 500,
  source: { type: 'card', id: 'your-card-id' },
  params: { phone: '0600000000' },
  transRef: prepared.transRef,
  otp: '123456',
});
```

An account can be named as the source in the API, but BaridiMob refuses it for
`paymentCheck` (verified live); use a card.

**Bills through the dynamic engine.** Some services (Algérie Télécom, ADE,
SEAL, Sonelgaz, AADL…) return the form themselves:

```ts
const groups = await bm.payments.dynamic.groups();
const operation = groups[0]!.operations[0]!;

const form = await bm.payments.dynamic.step(operation.id); // first form
const values = {
  phone: '0600000000',
  sourceId: 'card-scid',
  sourceType: '1',
  amount: '500',
  currency: 'DZD',
};

// for a later step, send the current step id and every value so far
// const next = await bm.payments.dynamic.step(operation.id, values, form.id);

const checked = await bm.payments.dynamic.check(operation.id, values);
await bm.payments.dynamic.requestOtp(checked.transRef);
const result = await bm.payments.dynamic.exec({
  operationId: operation.id,
  transRef: checked.transRef,
  otp: '123456',
  params: values,
});
console.log(result.recentOpId, result.recentOpType);
```

`check()` returns `DynamicCheckResult`; `exec()` returns `DynamicExecResult`.
`complete()` is for an extra confirmation step (such as 3D Secure) when the
server asks for one. Values are sent as `param.<id>`.

> **Not yet verified live:** `check()`, `exec()` and `complete()` use the
> endpoints of the official app, but their requests have not been tested against
> the real server yet. `groups()`, `operation()` and `step()` are verified.

## Receipts and profile

```ts
import { writeFile } from 'node:fs/promises';

const operations = await bm.receipts.list();                     // recent operations
const pdf = await bm.receipts.download(operations[0].uid);       // PDF as Uint8Array
await writeFile('receipt.pdf', pdf);

// The receipt of a movement from the history, or null
const [movement] = (await bm.accounts.transactions({ account })).transactions;
const receipt = await bm.receipts.downloadFor(movement!);
if (receipt) await writeFile('movement.pdf', receipt);

const profile = await bm.profile.get();                          // account holder information
```

`receipts.find(transaction)` returns the recent operation behind a history
movement, matched by its reference number (or by time and amount).
BaridiMob keeps receipts only for the last few operations, so `find()` and
`downloadFor()` return `null` for older ones.

## Session storage

The storage keeps the device keys and session cookies between runs.

| Storage | Use case |
|---------|----------|
| `fileStorage(path)` | Scripts and servers: saved to a JSON file |
| `memoryStorage()` | Tests and short-lived processes: lost when the process stops |
| Your own | Database, Redis, secret manager… |

To use your own storage, implement three methods:

```ts
import type { SessionStorage } from 'baridimob';

const myStorage: SessionStorage = {
  async load()        { /* return the saved session, or null */ },
  async save(session) { /* save it (encrypted!) */ },
  async clear()       { /* delete it */ },
};
```

You can also move a session manually with `bm.exportSession()` and `bm.importSession(session)`.

## Configuration

All options are optional:

```ts
const bm = createBaridiMob({
  storage: fileStorage('./session.json'),
  locale: 'fr',        // 'ar' (default) | 'fr' | 'en'
  timeoutMs: 30_000,   // request timeout
  retries: 2,          // retries on network errors
});
```

| Option | Default | Description |
|--------|---------|-------------|
| `storage` | none | Where the session is saved. Without it, the device must be confirmed again at every start. |
| `locale` | `'ar'` | Language of server messages and labels |
| `timeoutMs` | `30000` | Request timeout in milliseconds |
| `retries` | `2` | Number of retries on network errors |
| `deviceName` | `'BaridiMob SDK'` | Device name shown in BaridiMob |
| `timeZone` | `'GMT+01:00'` | Time zone sent to the server |
| `baseUrl` | official server | Server URL (must be HTTPS) |
| `allowInsecure` | `false` | Allow plain HTTP for non-local URLs (testing only) |
| `fetchImpl` | global `fetch` | Custom `fetch` implementation (proxy, logging…) |

## Error handling

All errors extend `BaridiMobError`, so you can catch them precisely:

```ts
import { InvalidCredentialsError, InvalidOtpError, NetworkError } from 'baridimob';

try {
  await bm.auth.login({ login, password });
} catch (error) {
  if (error instanceof InvalidCredentialsError) { /* wrong login or password */ }
  else if (error instanceof NetworkError)       { /* no connection */ }
  else throw error;
}
```

| Error | When |
|-------|------|
| `InvalidCredentialsError` | Wrong login or password |
| `InvalidOtpError` / `ExpiredOtpError` | Wrong or expired SMS code |
| `TooManyAttemptsError` | Too many failed attempts |
| `AccountLockedError` | The account is locked |
| `PasswordExpiredError` | The password must be changed in the official app |
| `SessionExpiredError` | Session expired and no credentials to log in again |
| `NetworkError` / `TimeoutError` | Connection problem |
| `ServerError` | The server returned an error |
| `ApiResultError` | Any other server error. Inspect `resultCode` and `resultName`. |

## Security

- **The saved session is a live credential.** It contains the session cookies and the device private key. Never commit it or log it. In production, encrypt it (for example AES-GCM with a key from a secret manager).
- **HTTPS is enforced.** Plain HTTP is refused, except for `localhost` / `127.0.0.1` or with `allowInsecure: true`.
- **Moving money always requires an SMS code** that you pass explicitly. Reading data never does.
- Add `.baridimob/` (or wherever you store the session) to your `.gitignore`.

## Disclaimer

This is an independent community project. It is **not affiliated with, endorsed by, or supported by Algérie Poste**. BaridiMob may change its service at any time, which can break this SDK. Use it at your own risk.

## License

MIT
