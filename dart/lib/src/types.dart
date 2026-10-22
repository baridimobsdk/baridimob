import 'errors.dart';

/// Language of server messages and labels.
enum BaridiMobLocale {
  /// Arabic (default).
  ar('ar_DZ', 'ar-DZ'),

  /// French.
  fr('fr_FR', 'fr-FR'),

  /// English.
  en('en', 'en');

  const BaridiMobLocale(this.tag, this.acceptLanguage);

  /// Locale tag sent at login, for example `ar_DZ`.
  final String tag;

  /// Value of the `Accept-Language` header.
  final String acceptLanguage;

  /// Parses `ar`, `fr` or `en`. Unknown values fall back to [ar].
  static BaridiMobLocale parse(String? value) =>
      values.firstWhere((locale) => locale.name == value, orElse: () => ar);
}

/// Everything needed to resume a session: device keys and cookies.
///
/// The JSON format is shared with the TypeScript and Python SDKs, so a session
/// can be moved between them. Treat it as a secret: it is a live credential.
class StoredSession {
  /// Creates a session.
  StoredSession({
    required this.devid,
    required this.privateKeyPem,
    required this.devkey,
    required this.devkeyAlgorithm,
    Map<String, String>? cookies,
    this.locale = BaridiMobLocale.ar,
    this.account,
    this.version = 1,
  }) : cookies = cookies ?? {};

  /// Reads a session saved with [toJson] (or by the TypeScript/Python SDKs).
  ///
  /// Throws a [BaridiMobError] when the payload is not a valid session.
  factory StoredSession.fromJson(Map<String, Object?> json) {
    final version = json['version'] ?? 1;
    final devid = json['devid'];
    final privateKeyPem = json['privateKeyPem'] ?? json['private_key_pem'];
    final devkey = json['devkey'];
    final devkeyAlgorithm = json['devkeyAlgorithm'] ?? json['devkey_algorithm'];
    final cookies = json['cookies'] ?? const <String, Object?>{};
    final account = json['account'];
    if (version != 1 ||
        devid is! String ||
        privateKeyPem is! String ||
        devkey is! String ||
        devkeyAlgorithm is! String ||
        cookies is! Map ||
        (account != null && account is! String)) {
      throw BaridiMobError('Invalid stored session');
    }
    return StoredSession(
      devid: devid,
      privateKeyPem: privateKeyPem,
      devkey: devkey,
      devkeyAlgorithm: devkeyAlgorithm,
      cookies: {
        for (final entry in cookies.entries)
          if (entry.value is String) '${entry.key}': entry.value as String,
      },
      locale: BaridiMobLocale.parse(json['locale'] as String?),
      account: account as String?,
    );
  }

  /// Format version, currently `1`.
  final int version;

  /// Device id.
  final String devid;

  /// Device private key (PKCS#8 PEM).
  final String privateKeyPem;

  /// Device public key, as sent to BaridiMob.
  final String devkey;

  /// Device key algorithm, for example `RSA 2048`.
  final String devkeyAlgorithm;

  /// Session cookies.
  Map<String, String> cookies;

  /// Locale used when the device was registered.
  BaridiMobLocale locale;

  /// Login this session belongs to, once logged in.
  String? account;

  /// JSON representation, compatible with the TypeScript and Python SDKs.
  Map<String, Object?> toJson() => {
        'version': version,
        'devid': devid,
        'privateKeyPem': privateKeyPem,
        'devkey': devkey,
        'devkeyAlgorithm': devkeyAlgorithm,
        'cookies': Map<String, String>.of(cookies),
        'locale': locale.name,
        if (account != null) 'account': account,
      };

  /// A deep copy of this session.
  StoredSession copy() => StoredSession.fromJson(toJson());
}

/// Where a session is saved between runs.
///
/// Implement it to store the session in a database, a secret manager or,
/// in a Flutter app, the platform secure storage.
abstract interface class SessionStorage {
  /// Returns the saved session, or `null` when there is none.
  Future<StoredSession?> load();

  /// Saves [session], replacing any previous one.
  Future<void> save(StoredSession session);

  /// Deletes the saved session.
  Future<void> clear();
}

/// Outcome of a login attempt.
enum LoginState {
  /// Logged in: the API can be used.
  authenticated,

  /// This device must be confirmed with an SMS code first.
  otpRequired,
}

/// Result of `auth.login()` and `auth.confirmDevice()`.
class LoginResult {
  const LoginResult._(this.state, this.devid);

  /// The user is logged in.
  const LoginResult.authenticated() : this._(LoginState.authenticated, null);

  /// The device [devid] must be confirmed with an SMS code.
  const LoginResult.otpRequired(String devid)
      : this._(LoginState.otpRequired, devid);

  /// Outcome of the attempt.
  final LoginState state;

  /// Device to confirm, when [state] is [LoginState.otpRequired].
  final String? devid;

  /// Whether the user is logged in.
  bool get isAuthenticated => state == LoginState.authenticated;

  /// Whether the device must be confirmed with an SMS code.
  bool get isOtpRequired => state == LoginState.otpRequired;

  @override
  bool operator ==(Object other) =>
      other is LoginResult && other.state == state && other.devid == devid;

  @override
  int get hashCode => Object.hash(state, devid);

  @override
  String toString() => 'LoginResult(${state.name})';
}

/// A bank account.
class Account {
  /// Creates an account.
  const Account({
    required this.id,
    required this.number,
    required this.balance,
    required this.currency,
    this.raw = const {},
  });

  /// Account id.
  final String id;

  /// Account number (RIP).
  final String number;

  /// Current balance.
  final double balance;

  /// Currency code, usually `DZD`.
  final String currency;

  /// Raw server data.
  final Map<String, Object?> raw;

  @override
  String toString() => 'Account(number: $number, balance: $balance $currency)';
}

/// An entry of the transaction history.
class Transaction {
  /// Creates a transaction.
  const Transaction({
    required this.amount,
    required this.currency,
    required this.description,
    required this.type,
    required this.tid,
    required this.timestamp,
    this.date,
    this.fee,
    this.refNum,
    this.raw = const {},
  });

  /// Amount: positive for money received, negative for money sent.
  final double amount;

  /// Currency code, usually `DZD`.
  final String currency;

  /// Description, in the client locale.
  final String description;

  /// Operation type.
  final String type;

  /// Transaction id.
  final String tid;

  /// Server timestamp, `yyyyMMddHHmmss` in Algeria time.
  final String timestamp;

  /// [timestamp] as a UTC [DateTime], or `null` when it cannot be parsed.
  final DateTime? date;

  /// Fee charged, if any.
  final double? fee;

  /// Reference number of the operation.
  final String? refNum;

  /// Raw server data.
  final Map<String, Object?> raw;

  @override
  String toString() =>
      'Transaction(refNum: $refNum, amount: $amount $currency, date: $date)';
}

/// A page of the transaction history.
class HistoryPage {
  /// Creates a page.
  const HistoryPage({required this.page, required this.transactions});

  /// Page number, starting at 1.
  final int page;

  /// Transactions of this page. Empty after the last page.
  final List<Transaction> transactions;
}

/// A payment card.
///
/// Called `Card` in the TypeScript and Python SDKs; the prefix avoids a clash
/// with Flutter's `Card` widget.
class BaridiMobCard {
  /// Creates a card.
  const BaridiMobCard({
    required this.id,
    required this.number,
    required this.name,
    required this.brand,
    required this.status,
    required this.expDate,
    this.type = 0,
    this.category,
    this.balance,
    this.currency,
    this.embossedName,
    this.active = true,
    this.pinNotSet = false,
    this.linkedAccounts = const [],
    this.isDebitAllowed = true,
    this.raw = const {},
  });

  /// Card id, used by the other card calls.
  final String id;

  /// Full card number, exactly as the server sends it. Keep it out of logs;
  /// [toString] leaves it out.
  final String number;

  /// Card name, when the holder gave it one.
  final String name;

  /// Brand, for example `VISA_CLASSIC`.
  final String brand;

  /// Card status: `0` valid, `1` invalid PIN limit, `10` fraud block,
  /// `12` not activated, `20` temporary block, `21` permanent block,
  /// `99` expired.
  final int status;

  /// Expiry, `yyyyMM`.
  final String expDate;

  /// `1` debit, `2` credit.
  final int type;

  /// `regular`, `virtual` or `external`.
  final String? category;

  /// Card balance.
  final double? balance;

  /// Balance currency, usually `DZD`.
  final String? currency;

  /// Name embossed on the card.
  final String? embossedName;

  /// Whether the card is active.
  final bool active;

  /// Whether the PIN was never set.
  final bool pinNotSet;

  /// Accounts linked to the card.
  final List<String> linkedAccounts;

  /// Whether debit operations are allowed.
  final bool isDebitAllowed;

  /// Raw server data.
  final Map<String, Object?> raw;

  /// Whether the card is in the valid state.
  bool get isValid => status == 0;

  /// Whether the card is temporarily blocked.
  bool get isTemporarilyBlocked => status == 20;

  /// Whether the card is permanently blocked.
  bool get isPermanentlyBlocked => status == 21;

  /// Whether the card has expired.
  bool get isExpired => status == 99;

  @override
  String toString() =>
      'BaridiMobCard(id: $id, brand: $brand, status: $status, expDate: $expDate)';
}

/// One spending or operation limit on a card.
class CardLimit {
  /// Creates a limit.
  const CardLimit({
    required this.uid,
    required this.name,
    this.description,
    this.type = 0,
    this.amount,
    this.usedAmount,
    this.opCount,
    this.usedOpCount,
    this.currency,
    this.active = true,
    this.changeable = false,
    this.permanent = false,
    this.perTransaction = false,
    this.endTime,
    this.raw = const {},
  });

  /// Limit id.
  final String uid;

  /// Limit name, in the client locale.
  final String name;

  /// Limit description, in the client locale.
  final String? description;

  /// `0` for an amount, `1` for a number of operations.
  final int type;

  /// Maximum amount, when [type] is `0`.
  final double? amount;

  /// Amount used.
  final double? usedAmount;

  /// Maximum number of operations, when [type] is `1`.
  final int? opCount;

  /// Operations used.
  final int? usedOpCount;

  /// Amount currency.
  final String? currency;

  /// Whether the limit is active.
  final bool active;

  /// Whether the limit can be changed.
  final bool changeable;

  /// Whether the limit is permanent.
  final bool permanent;

  /// Whether the limit applies to one operation.
  final bool perTransaction;

  /// End of a temporary limit, `yyyyMMddHHmmss`.
  final String? endTime;

  /// Raw server data.
  final Map<String, Object?> raw;

  /// Whether this is a count limit rather than an amount limit.
  bool get isCount => type == 1;

  @override
  String toString() => 'CardLimit(uid: $uid, name: $name, active: $active)';
}

/// Why [VerifyPaymentResult.verified] is true or false.
enum VerifyPaymentReason {
  /// Payment found, incoming, and the amount matches.
  ok('ok'),

  /// No transaction with this reference number.
  notFound('not_found'),

  /// The amount differs from the expected one.
  amountMismatch('amount_mismatch'),

  /// The transaction exists but is not money received.
  notIncoming('not_incoming'),

  /// Several incoming transactions share this reference: check manually.
  duplicate('duplicate');

  const VerifyPaymentReason(this.code);

  /// Same value as in the TypeScript and Python SDKs, for example `not_found`.
  final String code;
}

/// Result of `payments.verifyPayment()`.
class VerifyPaymentResult {
  /// Creates a result.
  const VerifyPaymentResult({
    required this.verified,
    required this.reason,
    required this.transaction,
    required this.matches,
  });

  /// Whether the payment was received with the expected amount.
  final bool verified;

  /// Why the payment is (or is not) verified.
  final VerifyPaymentReason reason;

  /// The matching incoming transaction, if any.
  final Transaction? transaction;

  /// Every transaction with this reference number in the searched period.
  final List<Transaction> matches;
}

/// Holder information.
class Profile {
  /// Creates a profile.
  const Profile({
    required this.actorId,
    this.clientName,
    this.lastLogin,
    this.financialOperationsDisabled = false,
    this.raw = const {},
  });

  /// Client id.
  final String actorId;

  /// Client name.
  final String? clientName;

  /// Last login, as sent by the server.
  final String? lastLogin;

  /// Whether payments and transfers are disabled on this account.
  final bool financialOperationsDisabled;

  /// Raw server data.
  final Map<String, Object?> raw;
}

/// A recent operation, with the [uid] needed to download its receipt.
class RecentOperation {
  /// Creates an operation.
  const RecentOperation({
    required this.uid,
    required this.type,
    required this.pid,
    required this.amount,
    required this.currency,
    required this.timestamp,
    this.date,
    this.providerName,
    this.sourceType,
    this.sourceId,
    this.status,
    this.operationId,
    this.raw = const {},
  });

  /// Operation id, used by `receipts.download()`.
  final String uid;

  /// Operation type.
  final String type;

  /// Provider id.
  final String pid;

  /// Amount.
  final double amount;

  /// Currency code.
  final String currency;

  /// Server timestamp, `yyyyMMddHHmmss` in Algeria time.
  final String timestamp;

  /// [timestamp] as a UTC [DateTime].
  final DateTime? date;

  /// Provider name, for example `Mobilis`.
  final String? providerName;

  /// `1` for a card, `2` for an account.
  final int? sourceType;

  /// Card or account used.
  final String? sourceId;

  /// Operation status.
  final int? status;

  /// The operation's reference: the same value as [Transaction.refNum] in
  /// the account history.
  final String? operationId;

  /// Raw server data.
  final Map<String, Object?> raw;
}

/// A payment category, for example mobile networks.
class PaymentCategory {
  /// Creates a category.
  const PaymentCategory(
      {required this.cid, required this.name, this.image, this.raw = const {}});

  /// Category id.
  final String cid;

  /// Category name.
  final String name;

  /// Image id.
  final String? image;

  /// Raw server data.
  final Map<String, Object?> raw;
}

/// A field a provider needs, for example the phone number to top up.
class ProviderParam {
  /// Creates a field.
  const ProviderParam({
    required this.id,
    required this.name,
    required this.type,
    this.pattern,
    this.min,
    this.max,
    this.value,
    this.description,
    this.hasExternalHandler = false,
  });

  /// Field id, used as the key in `params`.
  final String id;

  /// Field name.
  final String name;

  /// Field type, for example `PHONE`.
  final String type;

  /// Input pattern.
  final String? pattern;

  /// Minimum length or value.
  final num? min;

  /// Maximum length or value.
  final num? max;

  /// Default value.
  final String? value;

  /// Field description.
  final String? description;

  /// Whether the value comes from an external handler.
  final bool hasExternalHandler;
}

/// A biller, for example Mobilis.
class PaymentProvider {
  /// Creates a provider.
  const PaymentProvider({
    required this.pid,
    required this.name,
    this.mappedId,
    this.cid,
    this.scenario,
    this.categoryName,
    this.params = const [],
    this.raw = const {},
  });

  /// Provider id, used by `payments.check()` and `payments.exec()`.
  final String pid;

  /// Provider name.
  final String name;

  /// Stable code, for example `MOBILIS`.
  final String? mappedId;

  /// Category id.
  final String? cid;

  /// Payment scenario.
  final String? scenario;

  /// Category name.
  final String? categoryName;

  /// Fields to send in `params`.
  final List<ProviderParam> params;

  /// Raw server data.
  final Map<String, Object?> raw;
}

/// Kind of payment source.
enum PaymentSourceType {
  /// A card (`sourceType=1`).
  card,

  /// An account (`sourceType=2`).
  account,
}

/// The card or account a payment is taken from.
class PaymentSource {
  /// Pays with the card [id].
  const PaymentSource.card(this.id) : type = PaymentSourceType.card;

  /// Pays from the account [id].
  const PaymentSource.account(this.id) : type = PaymentSourceType.account;

  /// Card or account.
  final PaymentSourceType type;

  /// Card or account id.
  final String id;
}

/// A payment prepared by `payments.check()`, waiting for its SMS code.
class PaymentCheckResult {
  /// Creates a result.
  const PaymentCheckResult(
      {required this.transRef, this.confirmationType, this.raw = const {}});

  /// Reference to pass to `requestOtp()` and `exec()`.
  final String transRef;

  /// Confirmation method, usually `otp`.
  final String? confirmationType;

  /// Raw server data.
  final Map<String, Object?> raw;
}

/// Result of an executed payment.
class PaymentExecResult {
  /// Creates a result.
  const PaymentExecResult({this.raw = const {}});

  /// Raw server data.
  final Map<String, Object?> raw;
}

/// Reference to a dynamic operation or step.
class DynamicOperationRef {
  /// Creates a reference.
  const DynamicOperationRef({required this.id, required this.label});

  /// Id.
  final String id;

  /// Label.
  final String label;
}

/// A group of dynamic operations.
class DynamicGroup {
  /// Creates a group.
  const DynamicGroup({
    required this.id,
    required this.label,
    this.type,
    this.image,
    this.operations = const [],
    this.raw = const {},
  });

  /// Group id.
  final String id;

  /// Group label.
  final String label;

  /// Group type.
  final String? type;

  /// Image id.
  final String? image;

  /// Operations of this group.
  final List<DynamicOperationRef> operations;

  /// Raw server data.
  final Map<String, Object?> raw;
}

/// Metadata of a dynamic operation.
class DynamicOperationInfo {
  /// Creates the metadata.
  const DynamicOperationInfo({
    required this.id,
    required this.label,
    this.firstStep,
    this.saveTemplateEnabled = false,
    this.raw = const {},
  });

  /// Operation id.
  final String id;

  /// Operation label.
  final String label;

  /// First step of the form.
  final DynamicOperationRef? firstStep;

  /// Whether the operation can be saved as a template.
  final bool saveTemplateEnabled;

  /// Raw server data.
  final Map<String, Object?> raw;
}

/// An amount as BaridiMob writes it in a dynamic form.
class DynamicAmount {
  /// Creates an amount.
  const DynamicAmount({required this.text, this.currency});

  /// The amount as the server wrote it, for example `1500.00`. It is sent
  /// back unchanged.
  final String text;

  /// Its currency, for example `DZD`, when the server gives one.
  final String? currency;

  /// The amount as a number, or `null` when [text] is not one.
  double? get value => double.tryParse(text.trim().replaceAll(',', '.'));
}

/// How a `money` field is filled.
enum DynamicAmountMode {
  /// The user types the amount.
  input,

  /// The user picks one of [DynamicStepInput.amountChoices], for example
  /// the amount of a bill.
  select,
}

/// One amount offered by a `money` field in [DynamicAmountMode.select].
class DynamicAmountChoice {
  /// Creates a choice.
  const DynamicAmountChoice({required this.label, required this.amount});

  /// Label shown to the user.
  final String label;

  /// The amount.
  final DynamicAmount amount;
}

/// Where a dynamic payment takes the money from.
///
/// Dynamic operations name the source by type: a card is `CLIENT_CARD_ID`,
/// an account `ACCOUNT_NUMBER`. They do not accept the `1`/`2` of
/// `payments.check` (BaridiMob answers result 2).
class DynamicSource {
  const DynamicSource._(this.id, this.type);

  /// A card, by its id ([BaridiMobCard.id]).
  const DynamicSource.card(String id) : this._(id, cardType);

  /// An account, by its number.
  const DynamicSource.account(String number) : this._(number, accountType);

  /// Type of a card source.
  static const String cardType = 'CLIENT_CARD_ID';

  /// Type of an account source.
  static const String accountType = 'ACCOUNT_NUMBER';

  /// Card id or account number.
  final String id;

  /// Source type sent to BaridiMob.
  final String type;
}

/// A field of a dynamic form step.
class DynamicStepInput {
  /// Creates a field.
  const DynamicStepInput({
    required this.id,
    required this.label,
    required this.type,
    this.required = false,
    this.settings,
    this.choices = const [],
    this.accessAttributes = const [],
    this.value,
    this.amount,
    this.amountMode = DynamicAmountMode.input,
    this.amountChoices = const [],
    this.readonly = false,
    this.ordinalNumber,
    this.description,
    this.raw = const {},
  });

  /// Field id.
  final String id;

  /// Field label.
  final String label;

  /// Field type, for example `string`, `phone`, `hidden`, `source_storage`,
  /// `select`, `money`.
  final String type;

  /// Whether the field must be filled.
  final bool required;

  /// Field settings, as sent by the server.
  final Object? settings;

  /// Choices of a `select` field.
  final List<DynamicChoice> choices;

  /// Access attributes, for example `payment_source`.
  final List<String> accessAttributes;

  /// What BaridiMob already filled in, read like the official app: `value`,
  /// else `settings.value` for a `hidden` field, else
  /// `settings.defaultValue` for `string` and `phone`. Amounts are in
  /// [amount].
  final String? value;

  /// The amount BaridiMob filled in a `money` field, for example the amount
  /// of a bill.
  final DynamicAmount? amount;

  /// Whether a `money` field is typed or picked from [amountChoices].
  final DynamicAmountMode amountMode;

  /// Amounts a `money` field offers in [DynamicAmountMode.select].
  final List<DynamicAmountChoice> amountChoices;

  /// Shown but not editable. Its value is still sent.
  final bool readonly;

  /// Position of the field in the form.
  final int? ordinalNumber;

  /// Help text.
  final String? description;

  /// Raw server data.
  final Map<String, Object?> raw;

  /// Whether the field is hidden: never shown, always sent.
  bool get isHidden => type == 'hidden';

  /// Whether the field is the payment source.
  bool get isSource => type == 'source_storage';

  /// Whether the field is an amount.
  bool get isMoney => type == 'money';

  /// Whether the field is a choice.
  bool get isSelect => type == 'select';

  /// A setting as text, for example `setting('amountKey')`.
  String? setting(String key) {
    final all = settings;
    if (all is! Map) return null;
    final value = all[key];
    if (value is String) return value;
    if (value is num || value is bool) return '$value';
    return null;
  }

  String _key(String name, String fallback) {
    final key = setting(name);
    return key == null || key.isEmpty ? fallback : key;
  }

  /// The values this field sends, built like the official app:
  ///
  /// * `hidden`: its [value], even when empty.
  /// * `source_storage`: the [source] under the `idKey` and `typeKey`
  ///   settings.
  /// * `money`: an [amount] (or the amount [entered] as text, or the one
  ///   BaridiMob filled) under `amountKey`, with its currency under
  ///   `currencyKey`.
  /// * other fields: what the user [entered], else the prefilled [value];
  ///   nothing when empty. A [readonly] field keeps BaridiMob's value.
  ///
  /// Fields of an unknown type send nothing, as in the official app.
  Map<String, String> valuesFor({
    String? entered,
    DynamicSource? source,
    DynamicAmount? amount,
  }) {
    switch (type) {
      case 'hidden':
        return {id: value ?? ''};
      case 'source_storage':
        if (source == null) return const {};
        return {
          _key('idKey', 'sourceId'): source.id,
          _key('typeKey', 'sourceType'): source.type,
        };
      case 'money':
        final typed = entered?.trim();
        final chosen = readonly
            ? this.amount
            : amount ??
                (typed != null && typed.isNotEmpty
                    ? DynamicAmount(text: typed)
                    : this.amount);
        if (chosen == null || chosen.text.trim().isEmpty) return const {};
        return {
          _key('amountKey', 'amount'): chosen.text.trim(),
          _key('currencyKey', 'currency'): chosen.currency ??
              this.amount?.currency ??
              setting('defaultCurrency') ??
              'DZD',
        };
      case 'string':
      case 'phone':
      case 'text':
      case 'email':
      case 'select':
      case 'datetime':
      case 'monthyear':
        final text = readonly ? value : (entered ?? value);
        if (text == null || text.isEmpty) return const {};
        return {id: text};
      default:
        return const {};
    }
  }
}

/// One choice of a dynamic select field.
class DynamicChoice {
  /// Creates a choice.
  const DynamicChoice({required this.value, required this.label});

  /// Value sent to the server.
  final String value;

  /// Label shown to the user.
  final String label;
}

/// A step of a dynamic form.
class DynamicStep {
  /// Creates a step.
  const DynamicStep({
    required this.id,
    required this.label,
    this.inputs = const [],
    this.done = false,
    this.raw = const {},
  });

  /// Step id: send it as `currentStepKey` with the values of this step.
  final String id;

  /// Step label.
  final String label;

  /// Fields of this step, in the order of their `ordinalNumber`.
  final List<DynamicStepInput> inputs;

  /// True when BaridiMob sent no further step: the form is complete, call
  /// `check` with every value so far.
  final bool done;

  /// Raw server data.
  final Map<String, Object?> raw;

  /// The values to send for this step, built like the official app (see
  /// [DynamicStepInput.valuesFor]): what the user [entered] (field id →
  /// text or chosen value), the payment [source] and an [amount]. Add them
  /// to the values of the earlier steps.
  Map<String, String> values({
    Map<String, String> entered = const {},
    DynamicSource? source,
    DynamicAmount? amount,
  }) =>
      {
        for (final input in inputs)
          ...input.valuesFor(
            entered: entered[input.id],
            source: source,
            amount: amount,
          ),
      };
}

/// A piece of information BaridiMob returns about an operation, for a bill
/// the subscriber, the bill number or the amount due.
class DynamicDetail {
  /// Creates a detail.
  const DynamicDetail({
    required this.id,
    required this.label,
    required this.type,
    this.text,
    this.amount,
    this.raw = const {},
  });

  /// Detail id.
  final String id;

  /// Label shown to the user.
  final String label;

  /// Type: `string`, `money`, `datetime`, `boolean`…
  final String type;

  /// The value as text, for every type but `money`.
  final String? text;

  /// The value of a `money` detail.
  final DynamicAmount? amount;

  /// Raw server data.
  final Map<String, Object?> raw;
}

/// The result of `dynamic.check()`: a prepared operation waiting for its
/// confirmation code.
class DynamicCheckResult {
  /// Creates a result.
  const DynamicCheckResult({
    required this.transRef,
    this.confirmationType,
    this.fee,
    this.currency,
    this.planDate,
    this.details = const [],
    this.raw = const {},
  });

  /// Reference to pass to `exec()`.
  final String transRef;

  /// Confirmation method, usually `otp`.
  final String? confirmationType;

  /// Fee charged, if any.
  final double? fee;

  /// Fee currency.
  final String? currency;

  /// Planned execution date, when the server gives one.
  final String? planDate;

  /// What BaridiMob says about the operation (for a bill: subscriber, bill,
  /// amount due).
  final List<DynamicDetail> details;

  /// Raw server data.
  final Map<String, Object?> raw;

  /// The first amount among [details], when there is one.
  DynamicAmount? get amount {
    for (final detail in details) {
      if (detail.amount != null) return detail.amount;
    }
    return null;
  }
}

/// The result of `dynamic.exec()`.
class DynamicExecResult {
  /// Creates a result.
  const DynamicExecResult({
    this.transRef,
    this.recentOpId,
    this.recentOpType,
    this.authid,
    this.confirmationType,
    this.status,
    this.fee,
    this.currency,
    this.details = const [],
    this.raw = const {},
  });

  /// Operation reference.
  final String? transRef;

  /// Id of the recent operation created by the server.
  final String? recentOpId;

  /// Type of the recent operation.
  final String? recentOpType;

  /// Authentication id, when the server asks for an extra confirmation step.
  final String? authid;

  /// Further confirmation method, if the server asks for one.
  final String? confirmationType;

  /// Status of the operation, for example `COMPLETED`.
  final String? status;

  /// Fee charged, if any.
  final double? fee;

  /// Fee currency.
  final String? currency;

  /// What BaridiMob says about the executed operation.
  final List<DynamicDetail> details;

  /// Raw server data.
  final Map<String, Object?> raw;
}

/// The result of `dynamic.complete()`.
class DynamicCompleteResult {
  /// Creates a result.
  const DynamicCompleteResult({
    this.recentOpId,
    this.recentOpType,
    this.authid,
    this.raw = const {},
  });

  /// Id of the recent operation created by the server.
  final String? recentOpId;

  /// Type of the recent operation.
  final String? recentOpType;

  /// Authentication id, when present.
  final String? authid;

  /// Raw server data.
  final Map<String, Object?> raw;
}

/// A field of the form of a new cardless withdrawal code.
class CardlessInput {
  /// Creates a field.
  const CardlessInput({
    required this.id,
    required this.label,
    required this.type,
    this.description,
    this.required = false,
    this.readonly = false,
    this.value,
    this.stereotype,
    this.pattern,
    this.future = false,
    this.choices = const [],
    this.raw = const {},
  });

  /// Field id, sent as `param.<id>`.
  final String id;

  /// Field label.
  final String label;

  /// Field type: `select`, `datetime`, `hidden`…
  final String type;

  /// Help text.
  final String? description;

  /// Whether the field must be filled.
  final bool required;

  /// Shown but not editable.
  final bool readonly;

  /// What BaridiMob filled in, for example the signed `mb_model` of a
  /// hidden field. Hidden values are sent back unchanged.
  final String? value;

  /// Stereotype; a blank hidden value with `deviceId`, `devicePublicKey` or
  /// `devicePublicKeyAlgorithm` takes this device's data.
  final String? stereotype;

  /// Date pattern of a `datetime` field, for example
  /// `yyyy-MM-dd'T'HH:mm:ss.SSSXXX`.
  final String? pattern;

  /// Whether a `datetime` field must be in the future.
  final bool future;

  /// Choices of a `select` field.
  final List<DynamicChoice> choices;

  /// Raw server data.
  final Map<String, Object?> raw;
}

/// The form of a new cardless withdrawal code, as BaridiMob sends it.
class CardlessForm {
  /// Creates a form.
  const CardlessForm({this.inputs = const [], this.raw = const {}});

  /// Fields of the form.
  final List<CardlessInput> inputs;

  /// Raw server data.
  final Map<String, Object?> raw;

  /// Kinds of withdrawal offered, for example `ATM_CASHWITHDRAWAL`.
  List<DynamicChoice> get types {
    for (final input in inputs) {
      if (input.type == 'select' && input.choices.isNotEmpty) {
        return input.choices;
      }
    }
    return const [];
  }
}

/// Where a cardless withdrawal takes the money from.
class CardlessSource {
  const CardlessSource._(this.id, this.isCard);

  /// An account, by its id ([Account.id]).
  const CardlessSource.account(String id) : this._(id, false);

  /// A card, by its id ([BaridiMobCard.id]).
  const CardlessSource.card(String id) : this._(id, true);

  /// Account or card id.
  final String id;

  /// Whether the source is a card.
  final bool isCard;
}

/// A cardless withdrawal code: what to type at an Algérie Poste ATM to take
/// the cash without a card. Treat [code] like cash.
class CardlessCode {
  /// Creates a code.
  const CardlessCode({
    required this.id,
    this.code,
    this.amount,
    this.currency,
    this.status,
    this.details = const [],
    this.raw = const {},
  });

  /// Operation id, shown by BaridiMob as the authorisation number.
  final String id;

  /// The withdrawal code.
  final String? code;

  /// Amount to withdraw.
  final double? amount;

  /// Currency of [amount].
  final String? currency;

  /// Status, as BaridiMob words it.
  final String? status;

  /// Other information BaridiMob gives, for example the expiry date.
  final List<DynamicDetail> details;

  /// Raw server data.
  final Map<String, Object?> raw;
}

/// A transfer prepared by `transfers.arm()`, waiting for its SMS code.
class TransferArmResult {
  /// Creates a result.
  const TransferArmResult(
      {required this.transRef, this.confirmationType, this.raw = const {}});

  /// Reference to pass to `requestOtp()` and `exec()`.
  final String transRef;

  /// Confirmation method, usually `otp`.
  final String? confirmationType;

  /// Raw server data.
  final Map<String, Object?> raw;
}

/// Result of an executed transfer.
class TransferExecResult {
  /// Creates a result.
  const TransferExecResult({this.raw = const {}});

  /// Raw server data.
  final Map<String, Object?> raw;
}

/// A transfer whose SMS code has been sent. Call [confirm] with the code.
class TransferPending {
  /// Creates a pending transfer.
  TransferPending({
    required this.transRef,
    required this.amount,
    required this.sourceId,
    required this.targetId,
    required this.confirmationType,
    required Future<TransferExecResult> Function(String otp) confirm,
  }) : _confirm = confirm;

  /// Transfer reference.
  final String transRef;

  /// Amount to send.
  final num amount;

  /// Your account.
  final String sourceId;

  /// Recipient account (RIP).
  final String targetId;

  /// Confirmation method, usually `otp`.
  final String? confirmationType;

  final Future<TransferExecResult> Function(String otp) _confirm;

  /// Executes the transfer with the SMS [otp].
  Future<TransferExecResult> confirm(String otp) => _confirm(otp);
}
