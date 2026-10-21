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

Some services use dynamic forms. Explore them with `bm.payments.dynamic.groups()`, `.operation(id)` and `.step(id, params)`.

## Receipts and profile

```python
from pathlib import Path

operations = bm.receipts.list()                       # recent operations
pdf = bm.receipts.download(operations[0].uid)         # PDF as bytes
Path("receipt.pdf").write_bytes(pdf)

profile = bm.profile.get()                            # account holder information
```

## Session storage

The storage keeps the device keys and session cookies between runs.

| Storage | Use case |
|---------|----------|
| `FileStorage(path)` | Scripts and servers: saved to a JSON file |
| `MemoryStorage()` | Tests and short-lived processes: lost when the process stops |
| Your own | Database, Redis, secret manager… |

To use your own storage, write a class with three methods (it follows the `SessionStorage` protocol):

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

## Security

- **The saved session is a live credential.** It contains the session cookies and the device private key. Never commit it or log it. In production, encrypt it.
- **HTTPS is enforced.** Plain HTTP is refused, except for `localhost` / `127.0.0.1` or with `allow_insecure=True`.
- **Moving money always requires an SMS code** that you pass explicitly. Reading data never does.
- Add `.baridimob/` (or wherever you store the session) to your `.gitignore`.

## Disclaimer

This is an independent community project. It is **not affiliated with, endorsed by, or supported by Algérie Poste**. BaridiMob may change its service at any time, which can break this SDK. Use it at your own risk.

## License

MIT
