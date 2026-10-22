## 0.4.0

- Dynamic bill forms, built like the official app: a `hidden` field's
  `settings.value` is sent (the `billerServiceCode=FACTURE` without which the
  Algérie Télécom bill inquiry fails with result 2), `money` fields expose their
  prefilled amount and their `SELECT` choices, fields honour `readonly` and
  come in the order of their `ordinalNumber`, and a form with no further step
  is `done`.
- `DynamicStep.values()` builds a step's values, adding the hidden fields, the
  payment source (`DynamicSource`: `CLIENT_CARD_ID` or `ACCOUNT_NUMBER`, which
  dynamic operations require instead of `1`/`2`) and the amount.
  `DynamicCheckResult.details` and `DynamicExecResult.details` carry what
  BaridiMob says (for a bill: subscriber, bill, amount due);
  `DynamicExecResult.status` its final state.
- `ApiResultError.description` holds BaridiMob's own words, now the default
  message (for example «لا توجد فواتير غير مدفوعة»).
- Cash withdrawals without a card: `cardless.form`, `list`, `create` and
  `delete` (`CardlessSource.account` or `.card`), with `formatDatePattern` for
  the expiry field.
- Verified live: the bill inquiry, `check()` with a card source, and
  `cardless.create()` up to BaridiMob's balance check.

## 0.3.0

- Receipts of history movements: `receipts.find(transaction)` returns the
  recent operation behind a movement (matched by reference number, or by
  time and amount), and `receipts.downloadFor(transaction)` its PDF, or
  `null` when BaridiMob no longer keeps it.
- `RecentOperation.operationId`, the reference shared with
  `Transaction.refNum`.

## 0.2.0

- Cards: list regular and virtual cards, read a card and its limits, and
  browse its movements (`cards.list`, `cards.get`, `cards.limits`,
  `cards.history`, `cards.allHistory`, `cards.iterHistory`). A card is a
  `BaridiMobCard`, so it does not clash with Flutter's `Card` widget.
- Dynamic payments: validate, confirm and execute bill operations
  (`dynamic.check`, `dynamic.requestOtp`, `dynamic.exec`,
  `dynamic.complete`), with the current step key on `dynamic.step` and the
  choices/access attributes of each form field. `check`, `exec` and
  `complete` are not yet verified against the live server.

## 0.1.0

- Initial release.
- Login with device confirmation by SMS, automatic session renewal.
- Accounts, balance and transaction history.
- Payment verification by reference number and amount.
- Transfers and bill payments, always confirmed by SMS code.
- Recent operations and PDF receipts, holder profile.
- Session storage in memory, in a file, or your own (for example secure storage).
