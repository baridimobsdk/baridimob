# baridimob

**Unofficial Python SDK for BaridiMob — Algérie Poste (بريد الجزائر)**

[![PyPI](https://img.shields.io/pypi/v/baridimob)](https://pypi.org/project/baridimob/)
[![Python](https://img.shields.io/pypi/pyversions/baridimob)](https://pypi.org/project/baridimob/)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/baridimobsdk/baridimob/blob/main/LICENSE)

Read your BaridiMob accounts, verify incoming payments, send transfers and pay bills from Python.

- Two dependencies: `httpx` and `cryptography`
- Fully typed (dataclasses)
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
- [Withdrawals without a card](#withdrawals-without-a-card)
- [Receipts and profile](#receipts-and-profile)
- [Session storage](#session-storage)
- [Configuration](#configuration)
- [Error handling](#error-handling)
- [Security](#security)

---

## Installation

```bash
pip install baridimob
```

Requires **Python 3.10 or later**.

## Quick start

```python
from baridimob import Config, FileStorage, create_client

bm = create_client(Config(storage=FileStorage("./.baridimob/session.json")))

# 1. Log in
result = bm.auth.login("your-login", "your-password")

# 2. First time on this machine only: confirm the device by SMS
if result.state == "otp_required":
    bm.auth.request_device_otp()        # an SMS code is sent to your phone
    bm.auth.confirm_device("123456")    # the code you received

# 3. Use the API
accounts = bm.accounts.list()
print(accounts[0].number, accounts[0].balance)
```

## How login works

1. **First login on a machine:** BaridiMob asks to confirm the new device. `login()` returns a result with `state == "otp_required"`. Call `request_device_otp()`, then `confirm_device(code)` with the SMS code.
2. **The device keys and session are saved** in the storage you provide (here a file).
3. **Next logins** reuse the saved device. No SMS is needed.
4. **When the session expires**, the SDK logs in again automatically and retries the request.

```python
bm.auth.current_device_id()  # the registered device id, or None
bm.auth.logout()             # ends the session and deletes the saved device:
                             # the next login will ask for an SMS code again
```

## Accounts and history

```python
accounts = bm.accounts.list()             # all accounts
account  = bm.accounts.get(accounts[0].id)
balance  = bm.accounts.balance()          # balance of the first account
```

**Transaction history**

```python
from datetime import date

# One page
page = bm.accounts.transactions(account.number, date(2026, 1, 1), date.today(), page=1)

# All pages at once
everything = bm.accounts.all_transactions(account.number, "2026-01-01")

# Stream page by page (memory-friendly)
for tx in bm.accounts.iter_transactions(account.number):
    print(tx.date, tx.amount, tx.description)

# Find one transaction by its reference number
tx = bm.accounts.find_transaction(account.number, "012345678901")
```

Each `Transaction` contains `amount` (positive = incoming, negative = outgoing), `currency`, `description`, `date`, `fee`, `ref_num`, and the original server data in `raw`.

## Cards

```python
cards = bm.cards.list()                 # regular and virtual
card = bm.cards.get(cards[0].id)
limits = bm.cards.limits(card.id)

page = bm.cards.history(card.id, from_value=date(2026, 1, 1))
movements = bm.cards.all_history(card.id)

for movement in bm.cards.iter_history(card.id):
    print(movement.date, movement.amount)
```

`Card` carries `number`, `name`, `brand`, `status`, `exp_date` (`yyyyMM`),
`type`, `balance`, `currency`, `embossed_name`, `linked_accounts` and the raw
payload. `status` is `0` valid, `20` temporary block, `21` permanent block,
`99` expired, `12` not activated, `1` invalid PIN limit, `10` fraud block.

`number` is the full card number, exactly as BaridiMob sends it. Keep it out of
logs and error reports; `repr()` leaves it out.

`CardLimit` carries `type` (`0` amount, `1` number of operations), `amount` and
`used_amount` or `op_count` and `used_op_count`, `active`, `changeable`,
`permanent`, `per_transaction` and `end_time`.

`history` accepts `state="all"`, `"hold"` or `"processed"`.

BaridiMob ignores the `category` filter of `/cards` (verified live), so `list()`
makes a single request that returns every card. Use `card.category` (`regular`
or `virtual`) to tell them apart.

## Verify an incoming payment

Useful for shops and services that accept payment by BaridiMob transfer. The customer gives you the transfer's reference number, and you check that the money has really arrived.

```python
check = bm.payments.verify_payment(
    "012345678901",   # reference number given by the customer
    amount=2500,      # expected amount (optional)
)

if check.verified:
    ...  # payment received: deliver the order
else:
    print(check.reason)
```

| `reason` | Meaning |
|----------|---------|
| `ok` | Payment found, incoming, and the amount matches |
| `not_found` | No transaction with this reference number |
| `not_incoming` | The transaction exists but is not money received |
| `amount_mismatch` | The amount differs from the expected one |
| `duplicate` | Several incoming transactions share this reference: check manually |

By default, the search covers **the last 30 days** of **the first account**. Use `account=`, `from_value=` and `to_value=` to change this.

## Transfers

Every transfer requires an SMS code. `send()` prepares the transfer and sends the SMS, then `confirm()` executes it:

```python
pending = bm.transfers.send(
    1000,                       # amount
    account.number,             # your account
    "00799999000000000000",     # recipient's RIP
)

# ask the user for the SMS code, then:
receipt = pending.confirm("123456")
```

For full control, the same flow is available step by step: `arm()` → `request_otp(trans_ref)` → `exec(..., trans_ref, otp)`.

## Bill payments

```python
# 1. Browse what can be paid
categories = bm.payments.categories()
providers = bm.payments.providers(categories[0].cid)

# 2. Prepare the payment
prepared = bm.payments.check(
    providers[0].pid,
    500,
    source_type="card",                 # "card" or "account"
    source_id="your-card-id",
    params={"phone": "0600000000"},     # fields required by this provider
)

# 3. Confirm with the SMS code
bm.payments.request_otp(prepared.trans_ref)
bm.payments.exec(
    providers[0].pid,
    500,
    source_type="card",
    source_id="your-card-id",
    trans_ref=prepared.trans_ref,
    otp="123456",
    params={"phone": "0600000000"},
)
```

`source_type="account"` is part of the API, but BaridiMob refuses an account as
the payment source for `paymentCheck` (verified live); use a card.

**Bills through the dynamic engine.** Some services (Algérie Télécom, ADE,
SEAL, Sonelgaz, AADL…) return the form themselves, step by step:

```python
from baridimob import DynamicSource

groups = bm.payments.dynamic.groups()
operation = groups[0].operations[0]
card = bm.cards.list()[0]
source = DynamicSource.card(card.id)

# Fill each step until BaridiMob has none left (step.done). values() adds
# what BaridiMob expects besides what is typed: hidden fields (for an
# Algérie Télécom bill, billerServiceCode=FACTURE), the payment source and
# the amount. Later steps send the current step id and every value so far.
step = bm.payments.dynamic.step(operation.id)
values = {}
while not step.done:
    values.update(step.values(entered={"customerNumber": "044395258"}, source=source))
    step = bm.payments.dynamic.step(operation.id, values, step.id)

# check() moves no money and sends no SMS; for a bill, its details hold the
# subscriber, the bill and the amount due.
checked = bm.payments.dynamic.check(operation.id, values)
for detail in checked.details:
    print(detail.label, detail.amount.text if detail.amount else detail.text)
bm.payments.dynamic.request_otp(checked.trans_ref)
result = bm.payments.dynamic.exec(operation.id, checked.trans_ref, "123456", values)
print(result.recent_op_id, result.status)
```

- **Payment source:** dynamic forms name it with `DynamicSource`
  (`CLIENT_CARD_ID` for a card, `ACCOUNT_NUMBER` for an account). BaridiMob
  answers result 2 to the `1`/`2` of `payments.check`.
- **Amounts:** a `money` field may come filled (`input.amount`, a bill's amount
  due) or offer amounts to pick (`input.amount_choices` when
  `input.amount_mode == "select"`); pass the chosen one as
  `values(amount=...)`. Read-only fields (`input.readonly`) keep BaridiMob's
  value. Fields come in the order of their `ordinalNumber`.
- **Refusals** carry BaridiMob's own words, for example
  «لا توجد فواتير غير مدفوعة» (no unpaid bills): see
  [Error handling](#error-handling).

`check()` returns `DynamicCheckResult` (`trans_ref`, `confirmation_type`, `fee`,
`plan_date`, `details`, `amount`); `exec()` returns `DynamicExecResult`
(`recent_op_id`, `recent_op_type`, `status`, `details`). `complete()` is for
an extra confirmation step (such as 3D Secure) when the server asks for one.
Values are sent as `param.<id>`.

`groups()`, `operation()`, `step()` and `check()` (an internet top-up with a
card source) are verified against the live server. `exec()` and `complete()`
use the endpoints of the official app but have not been executed live yet.

## Withdrawals without a card

A cardless code takes cash out of an Algérie Poste ATM without the card.

```python
from datetime import datetime, timedelta, timezone

from baridimob import CardlessSource

# The codes not used yet.
for code in bm.cardless.list():
    print(code.code, code.amount, code.currency, code.id)

account = bm.accounts.list()[0]
code = bm.cardless.create(
    amount=2000,
    source=CardlessSource.account(account.id),  # or CardlessSource.card(card.id)
    expires_at=datetime.now(timezone.utc) + timedelta(days=1),  # less than six months
)
print(code.code, code.id)  # id: the authorisation number

# While it is unused, it can be deleted.
bm.cardless.delete(code.id)
```

`create()` reads the form again each time (its hidden `mb_model` is signed per
request) and is never retried automatically; the official app asks for no SMS
code here. Treat `code` like cash. A naive `expires_at` is read as Algeria
time.

> **Partly verified live:** `form()` and `list()` are verified. `create()`
> reached BaridiMob's balance check (an account without funds was refused with
> «رصيد الحساب غير كافٍ»); `delete()` has not run against a real code yet.

## Receipts and profile

```python
from pathlib import Path

operations = bm.receipts.list()                       # recent operations
pdf = bm.receipts.download(operations[0].uid)         # PDF as bytes
Path("receipt.pdf").write_bytes(pdf)

# The receipt of a movement from the history, or None
movement = bm.accounts.transactions(account).transactions[0]
receipt = bm.receipts.download_for(movement)
if receipt:
    Path("movement.pdf").write_bytes(receipt)

profile = bm.profile.get()                            # account holder information
```

`receipts.find(transaction)` returns the recent operation behind a history
movement, matched by its reference number (or by time and amount).
BaridiMob keeps receipts only for the last few operations, so `find()` and
`download_for()` return `None` for older ones.

## Session storage

The storage keeps the device keys and session cookies between runs.

| Storage | Use case |
|---------|----------|
| `FileStorage(path)` | Scripts and servers: saved to a JSON file |
| `MemoryStorage()` | Tests and short-lived processes: lost when the process stops |
| `RedisStorage(...)` | Distributed environments, multi-worker servers, serverless: saved in Redis |
| Your own | Database, secret manager… |

### Using Redis storage

Install with the optional `redis` extra:

```bash
pip install "baridimob[redis]"
```

Pass a Redis URL or an existing `redis.Redis` instance:

```python
from datetime import timedelta
from baridimob import Config, RedisStorage, create_client

# Using a connection URL with optional key prefix and TTL
storage = RedisStorage("redis://localhost:6379/0", prefix="baridimob:session:", ttl=timedelta(days=7))

# Or using an existing redis client instance
# import redis
# client = redis.Redis.from_url("redis://localhost:6379/0")
# storage = RedisStorage(redis_client=client)

bm = create_client(Config(storage=storage))
```

To use your own custom storage, write a class with three methods (it follows the `SessionStorage` protocol):

```python
from baridimob import SessionStorage, StoredSession

class MyStorage(SessionStorage):
    def load(self) -> StoredSession | None: ...   # return the saved session, or None
    def save(self, session: StoredSession) -> None: ...  # save it (encrypted!)
    def clear(self) -> None: ...                  # delete it
```

You can also move a session manually with `bm.export_session()` and `bm.import_session(session)`.

## Configuration

All options are optional:

```python
bm = create_client(Config(
    storage=FileStorage("./session.json"),
    locale="fr",     # "ar" (default) | "fr" | "en"
    timeout=30.0,    # request timeout in seconds
    retries=2,       # retries on network errors
))
```

| Option | Default | Description |
|--------|---------|-------------|
| `storage` | `None` | Where the session is saved. Without it, the device must be confirmed again at every start. |
| `locale` | `"ar"` | Language of server messages and labels |
| `timeout` | `30.0` | Request timeout in seconds |
| `retries` | `2` | Number of retries on network errors |
| `device_name` | `"BaridiMob SDK"` | Device name shown in BaridiMob |
| `time_zone` | `"GMT+01:00"` | Time zone sent to the server |
| `base_url` | official server | Server URL (must be HTTPS) |
| `allow_insecure` | `False` | Allow plain HTTP for non-local URLs (testing only) |
| `http_client` | `None` | Your own `httpx.Client` (proxy, logging…) |

## Error handling

All errors extend `BaridiMobError`, so you can catch them precisely:

```python
from baridimob import InvalidCredentialsError, NetworkError

try:
    bm.auth.login(login, password)
except InvalidCredentialsError:
    ...  # wrong login or password
except NetworkError:
    ...  # no connection
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
| `ApiResultError` | Any other server error. Inspect `result_code` and `result_name`. |

When BaridiMob explains a refusal, the error message (`str(error)`) is its own
words, in the session's language (for example «لا توجد فواتير غير مدفوعة»),
also in `description`.

## Security

- **The saved session is a live credential.** It contains the session cookies and the device private key. Never commit it or log it. In production, encrypt it.
- **HTTPS is enforced.** Plain HTTP is refused, except for `localhost` / `127.0.0.1` or with `allow_insecure=True`.
- **Moving money always requires an SMS code** that you pass explicitly. Reading data never does.
- Add `.baridimob/` (or wherever you store the session) to your `.gitignore`.

## Disclaimer

This is an independent community project. It is **not affiliated with, endorsed by, or supported by Algérie Poste**. BaridiMob may change its service at any time, which can break this SDK. Use it at your own risk.

## License

MIT
