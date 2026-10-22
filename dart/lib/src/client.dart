import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'errors.dart';
import 'http.dart';
import 'keys.dart';
import 'parse.dart';
import 'result.dart';
import 'sign.dart';
import 'storage.dart';
import 'types.dart';

/// Computes the password sent to `login/hash` when the server asks for a
/// hashed login (result 143).
typedef PasswordHasher = FutureOr<String> Function(
    String login, String password);

const String _formContentType = 'application/x-www-form-urlencoded';
const int _maxHistoryPages = 100;
const Set<String> _localHosts = {'localhost', '127.0.0.1', '::1'};

/// Client for the BaridiMob API.
///
/// ```dart
/// final bm = BaridiMob(storage: FileStorage('session.json'));
/// final result = await bm.auth.login(login: 'login', password: 'password');
/// if (result.isOtpRequired) {
///   await bm.auth.requestDeviceOtp();
///   await bm.auth.confirmDevice('123456');
/// }
/// final accounts = await bm.accounts.list();
/// ```
class BaridiMob {
  /// Creates a client. Every option is optional.
  ///
  /// * [storage] keeps the device keys and session between runs. Without it,
  ///   the device must be confirmed by SMS again at every start.
  /// * [locale] is the language of server messages and labels.
  /// * [timeout] and [retries] apply to each request. Requests that send an
  ///   OTP or move money are never retried.
  /// * [baseUrl] must use HTTPS, except for `localhost` or with
  ///   [allowInsecure].
  /// * [httpClient] lets you provide your own `http.Client` (proxy, logging).
  BaridiMob({
    SessionStorage? storage,
    this.locale = BaridiMobLocale.ar,
    String baseUrl = defaultBaseUrl,
    bool allowInsecure = false,
    this.hashPassword,
    String specRevision = defaultSpecRevision,
    this.timeZone = 'GMT+01:00',
    this.deviceName = 'BaridiMob SDK',
    Duration timeout = const Duration(seconds: 30),
    int retries = 2,
    String userAgent = defaultUserAgent,
    http.Client? httpClient,
  })  : storage = storage ?? MemoryStorage(),
        _ownsHttpClient = httpClient == null,
        _transport = HttpTransport(
          baseUrl: _resolveBaseUrl(baseUrl, allowInsecure),
          specRevision: specRevision,
          locale: locale,
          timeout: timeout,
          retries: retries,
          userAgent: userAgent,
          client: httpClient ?? http.Client(),
        );

  /// Where the session is saved.
  final SessionStorage storage;

  /// Language of server messages and labels.
  final BaridiMobLocale locale;

  /// Custom hasher for the hashed login fallback. Defaults to
  /// `sha256(login + password)`.
  final PasswordHasher? hashPassword;

  /// Time zone sent at login.
  final String timeZone;

  /// Device name shown in BaridiMob.
  final String deviceName;

  final HttpTransport _transport;
  final bool _ownsHttpClient;

  StoredSession? _session;
  bool _loaded = false;
  ({String login, String password})? _credentials;
  Future<LoginResult>? _reloginInFlight;

  /// Login, device confirmation and logout.
  late final AuthModule auth = AuthModule._(this);

  /// Accounts, balance and transaction history.
  late final AccountsModule accounts = AccountsModule._(this);

  /// Cards, their history and limits.
  late final CardsModule cards = CardsModule._(this);

  /// Payment verification and bill payments.
  late final PaymentsModule payments = PaymentsModule._(this);

  /// Transfers to other accounts.
  late final TransfersModule transfers = TransfersModule._(this);

  /// Recent operations and PDF receipts.
  late final ReceiptsModule receipts = ReceiptsModule._(this);

  /// Cash withdrawals without a card: codes to type at an ATM.
  late final CardlessModule cardless = CardlessModule._(this);

  /// Holder information.
  late final ProfileModule profile = ProfileModule._(this);

  /// Returns a copy of the current session (device keys and cookies), or
  /// `null` before the first login. Treat it as a secret.
  Future<StoredSession?> exportSession() async {
    final session = await _loadSession();
    if (session == null) return null;
    session.cookies = _transport.cookieSnapshot();
    return session.copy();
  }

  /// Replaces the current session with [session] and saves it to [storage].
  Future<void> importSession(StoredSession session) async {
    _session = session.copy();
    _loaded = true;
    _credentials = null;
    _transport.restoreCookies(session.cookies);
    await storage.save(_session!);
  }

  /// Closes the HTTP client created by this instance. A client passed as
  /// `httpClient` is left open.
  void close() {
    if (_ownsHttpClient) _transport.client.close();
  }

  // Session --------------------------------------------------------------

  Future<StoredSession?> _loadSession() async {
    if (!_loaded) {
      _session = await storage.load();
      final session = _session;
      if (session != null) _transport.restoreCookies(session.cookies);
      _loaded = true;
    }
    return _session;
  }

  StoredSession _requireSession() {
    final session = _session;
    if (session == null) {
      throw DeviceFlowError('No device session: call login() first');
    }
    return session;
  }

  Future<void> _persist() async {
    final session = _session;
    if (session == null) return;
    session.cookies = _transport.cookieSnapshot();
    await storage.save(session);
  }

  Future<StoredSession> _ensureDevice() async {
    final existing = await _loadSession();
    if (existing != null) return existing;
    // RSA key generation takes a moment: keep it off the UI isolate.
    final keys = await Isolate.run(generateDeviceKeys);
    return _session = StoredSession(
      devid: keys.devid,
      privateKeyPem: keys.privateKeyPem,
      devkey: keys.devkey,
      devkeyAlgorithm: keys.devkeyAlgorithm,
      locale: locale,
    );
  }

  // Login ----------------------------------------------------------------

  Future<LoginResult> _performLogin(String login, String password) async {
    final current = await _ensureDevice();
    final previousCookies = _transport.cookieSnapshot();
    _transport.clearCookies();

    Future<Map<String, Object?>> attempt(String endpoint, String pwd) async {
      final params = {
        'devid': current.devid,
        'devkeyAlgorithmHash': algorithmHash(current.devkeyAlgorithm),
        'name': login,
        'pwd': pwd,
        'lang': locale.name,
        'locale': locale.tag,
        'timeZone': timeZone,
      };
      try {
        final response = await _transport.send(
          method: 'POST',
          endpoint: endpoint,
          body: signParams(params, current.privateKeyPem),
          contentType: _formContentType,
        );
        return asRecord(response.data);
      } catch (_) {
        _transport.restoreCookies(previousCookies);
        rethrow;
      }
    }

    var body = await attempt('login', password);
    var code = resultCodeOf(body);

    if (code == 143) {
      final hasher = hashPassword;
      final hashed = hasher != null
          ? await hasher(login, password)
          : sha256Hex('$login$password');
      body = await attempt('login/hash', hashed);
      code = resultCodeOf(body);
      if (code == 143) {
        _transport.restoreCookies(previousCookies);
        throw HashedRetryError(143, body);
      }
    }

    if (code == 0) {
      current.account = login;
      await _persist();
      return const LoginResult.authenticated();
    }
    if (code == 106 || code == 107) {
      current.account = login;
      await _persist();
      return LoginResult.otpRequired(current.devid);
    }
    _transport.restoreCookies(previousCookies);
    if (code == null) {
      throw ServerError(-1, body, 'Response is missing numeric result code');
    }
    throw errorForResult(code, body, devid: current.devid);
  }

  Future<LoginResult> _sharedRelogin(
      ({String login, String password}) credentials) {
    return _reloginInFlight ??=
        _performLogin(credentials.login, credentials.password)
            .whenComplete(() => _reloginInFlight = null);
  }

  // Requests -------------------------------------------------------------

  Future<SendResult> _sendOnce(_RequestSpec spec) {
    final session = _requireSession();
    if (spec.method == 'GET') {
      return _transport.send(
        method: 'GET',
        endpoint: spec.endpoint,
        query: signQuery(spec.params, session.privateKeyPem),
        safe: spec.safe,
        binary: spec.binary,
      );
    }
    final json = spec.json;
    if (json != null) {
      return _transport.send(
        method: 'POST',
        endpoint: spec.endpoint,
        body: signJsonBody(json, session.privateKeyPem),
        contentType: 'application/json',
        safe: spec.safe,
      );
    }
    return _transport.send(
      method: 'POST',
      endpoint: spec.endpoint,
      body: signParams(spec.params, session.privateKeyPem),
      contentType: _formContentType,
      safe: spec.safe,
    );
  }

  Future<SendResult> _sendWithRelogin(_RequestSpec spec) async {
    await _loadSession();
    final current = _requireSession();
    var response = await _sendOnce(spec);
    final code =
        response.bytes != null ? 0 : resultCodeOf(asRecord(response.data));
    if (code == 101 || code == 102) {
      final credentials = _credentials;
      if (credentials == null) throw SessionExpiredError();
      final relogin = await _sharedRelogin(credentials);
      if (!relogin.isAuthenticated) {
        throw DeviceConfirmationRequiredError(
            106, asRecord(response.data), current.devid);
      }
      response = await _sendOnce(spec);
    }
    return response;
  }

  Future<Map<String, Object?>> _request(_RequestSpec spec) async {
    final response = await _sendWithRelogin(spec);
    final body = asRecord(response.data);
    raiseForResult(body, devid: _session?.devid);
    await _persist();
    return body;
  }

  Future<Uint8List> _requestBinary(_RequestSpec spec) async {
    final response = await _sendWithRelogin(spec);
    final bytes = response.bytes;
    if (bytes != null) {
      await _persist();
      return bytes;
    }
    final body = asRecord(response.data);
    raiseForResult(body, devid: _session?.devid);
    throw ServerError(-1, body, 'Expected a binary response');
  }

  Future<Map<String, Object?>> _get(String endpoint,
          [Map<String, String> params = const {}]) =>
      _request(_RequestSpec('GET', endpoint, params: params));

  Future<List<Transaction>> _historyPage(
    String account,
    DateTime? from,
    DateTime? to,
    int page,
  ) async {
    final params = {
      'account': account,
      'page': '$page',
      if (from != null) 'startDate': toDateParam(from),
      if (to != null) 'endDate': toDateParam(to),
    };
    return parseHistory(await _get('accountHistory', params));
  }

  Stream<Transaction> _transactions(
      String account, DateTime? from, DateTime? to) async* {
    for (var page = 1; page <= _maxHistoryPages; page++) {
      final items = await _historyPage(account, from, to, page);
      if (items.isEmpty) return;
      yield* Stream.fromIterable(items);
    }
  }

  Future<List<Transaction>> _cardHistoryPage(
    String card,
    DateTime? from,
    DateTime? to,
    int page,
    String? state,
  ) async {
    final params = {
      'card': card,
      'page': '$page',
      if (from != null) 'startDate': toDateParam(from),
      if (to != null) 'endDate': toDateParam(to),
      if (state != null) 'transactionState': state,
    };
    return parseHistory(await _get('cardHistory', params));
  }

  Stream<Transaction> _cardTransactions(
    String card,
    DateTime? from,
    DateTime? to,
    String? state,
  ) async* {
    for (var page = 1; page <= _maxHistoryPages; page++) {
      final items = await _cardHistoryPage(card, from, to, page, state);
      if (items.isEmpty) return;
      yield* Stream.fromIterable(items);
    }
  }
}

class _RequestSpec {
  _RequestSpec(
    this.method,
    this.endpoint, {
    this.params = const {},
    this.json,
    this.safe = true,
    this.binary = false,
  });

  final String method;
  final String endpoint;
  final Map<String, String> params;
  final Map<String, Object?>? json;
  final bool safe;
  final bool binary;
}

String _resolveBaseUrl(String raw, bool allowInsecure) {
  final Uri url;
  try {
    url = Uri.parse(raw);
  } on FormatException {
    throw BaridiMobError('Invalid baseUrl: $raw');
  }
  if (url.host.isEmpty) throw BaridiMobError('Invalid baseUrl: $raw');
  final normalized = '${url.scheme}://${url.authority}${url.path}'
      .replaceFirst(RegExp(r'/+$'), '');
  if (url.scheme == 'https') return normalized;
  if (url.scheme == 'http' &&
      (_localHosts.contains(url.host) || allowInsecure)) {
    return normalized;
  }
  throw BaridiMobError(
    'baseUrl must use https (http is allowed only for localhost or with allowInsecure: true)',
  );
}

/// Login, device confirmation and logout.
class AuthModule {
  AuthModule._(this._client);

  final BaridiMob _client;

  /// Logs in.
  ///
  /// On a new device the result is [LoginResult.isOtpRequired]: call
  /// [requestDeviceOtp], then [confirmDevice] with the SMS code. The device is
  /// then saved and later logins need no SMS.
  Future<LoginResult> login(
      {required String login, required String password}) async {
    final client = _client;
    final session = await client._loadSession();
    final bound = session?.account;
    if (bound != null && bound != login) {
      throw BaridiMobError(
        'Stored session belongs to a different account: call logout() or use a separate storage',
      );
    }
    client._credentials = null;
    final result = await client._performLogin(login, password);
    client._credentials = (login: login, password: password);
    return result;
  }

  /// Sends the SMS code that confirms this device.
  Future<void> requestDeviceOtp() async {
    final client = _client;
    await client._loadSession();
    final current = client._requireSession();
    final response = await client._transport.send(
      method: 'POST',
      endpoint: 'deviceAttach',
      body: signParams({
        'devkey': current.devkey,
        'devid': current.devid,
        'devkeyAlgorithm': current.devkeyAlgorithm,
      }, current.privateKeyPem),
      contentType: _formContentType,
      safe: false,
    );
    raiseForResult(asRecord(response.data), devid: current.devid);
    await client._persist();
  }

  /// Confirms this device with the SMS [otp], then logs in again.
  Future<LoginResult> confirmDevice(String otp) async {
    final client = _client;
    await client._loadSession();
    final current = client._requireSession();
    final response = await client._transport.send(
      method: 'POST',
      endpoint: 'deviceConfirm',
      body: signParams({
        'devcode': otp,
        'devid': current.devid,
        'devkeyAlgorithm': current.devkeyAlgorithm,
        'devname': client.deviceName,
      }, current.privateKeyPem),
      contentType: _formContentType,
      safe: false,
    );
    raiseForResult(asRecord(response.data), devid: current.devid);
    await client._persist();

    final credentials = client._credentials;
    if (credentials == null) {
      throw DeviceFlowError(
          'Credentials are not in memory: call login() again after confirming');
    }
    return client._performLogin(credentials.login, credentials.password);
  }

  /// Ends the session and deletes the saved device. The next login will ask
  /// for an SMS code again.
  Future<void> logout() async {
    final client = _client;
    final session = await client._loadSession();
    if (session != null) {
      try {
        await client._transport.send(
          method: 'GET',
          endpoint: 'logout',
          query: signQuery(const {}, session.privateKeyPem),
        );
      } on Exception {
        // The local session is cleared even if the server cannot be reached.
      }
    }
    await client.storage.clear();
    client._transport.clearCookies();
    client._session = null;
    client._loaded = true;
    client._credentials = null;
  }

  /// Id of the registered device, or `null` before the first login.
  String? get currentDeviceId => _client._session?.devid;
}

/// Accounts, balance and transaction history.
class AccountsModule {
  AccountsModule._(this._client);

  final BaridiMob _client;

  /// All accounts.
  Future<List<Account>> list() async =>
      parseAccounts(await _client._get('accounts'));

  /// One account by [id].
  Future<Account> get(String id) async =>
      parseAccountResponse(await _client._get('account', {'id': id}));

  /// Balance of the first account.
  Future<double> balance() async {
    final accounts = await list();
    if (accounts.isEmpty) throw DeviceFlowError('No account available');
    return accounts.first.balance;
  }

  /// One page of the history of [account], between [from] and [to].
  Future<HistoryPage> transactions({
    required String account,
    DateTime? from,
    DateTime? to,
    int page = 1,
  }) async =>
      HistoryPage(
          page: page,
          transactions: await _client._historyPage(account, from, to, page));

  /// The whole history of [account] between [from] and [to].
  Future<List<Transaction>> allTransactions({
    required String account,
    DateTime? from,
    DateTime? to,
  }) =>
      _client._transactions(account, from, to).toList();

  /// The history of [account], fetched page by page as you read it.
  Stream<Transaction> iterTransactions({
    required String account,
    DateTime? from,
    DateTime? to,
  }) =>
      _client._transactions(account, from, to);

  /// The transaction with reference number [refNum], or `null`.
  Future<Transaction?> findTransaction({
    required String account,
    required String refNum,
    DateTime? from,
    DateTime? to,
  }) async {
    final bounds = dayBounds(from, to);
    await for (final transaction in _client._transactions(account, from, to)) {
      if (transaction.refNum != refNum) continue;
      if (!isWithinBounds(transaction, bounds.start, bounds.end)) continue;
      return transaction;
    }
    return null;
  }
}

/// Cards, their history and limits.
class CardsModule {
  CardsModule._(this._client);

  final BaridiMob _client;

  /// All the cards of the client, regular and virtual.
  ///
  /// BaridiMob ignores the `category` filter, so one request returns every
  /// card; read [BaridiMobCard.category] to tell them apart.
  Future<List<BaridiMobCard>> list() async =>
      parseCards(await _client._get('cards', {'category': 'REGULAR'}));

  /// One card by [id], with its dynamic details.
  Future<BaridiMobCard> get(String id) async =>
      parseCardResponse(await _client._get('card', {'id': id}));

  /// The limits of the card [id].
  Future<List<CardLimit>> limits(String id) async => parseCardLimits(
        await _client._get('cardLimits', {
          'card': id,
          'language': _client.locale.name,
          'locale': _client.locale.tag,
        }),
      );

  /// One page of the movements of [card], between [from] and [to].
  ///
  /// [state] is `all`, `hold` or `processed`; `null` leaves it to the server.
  Future<HistoryPage> history({
    required String card,
    DateTime? from,
    DateTime? to,
    int page = 1,
    String? state,
  }) async =>
      HistoryPage(
        page: page,
        transactions:
            await _client._cardHistoryPage(card, from, to, page, state),
      );

  /// The whole history of [card] between [from] and [to].
  Future<List<Transaction>> allHistory({
    required String card,
    DateTime? from,
    DateTime? to,
    String? state,
  }) =>
      _client._cardTransactions(card, from, to, state).toList();

  /// The history of [card], fetched page by page as you read it.
  Stream<Transaction> iterHistory({
    required String card,
    DateTime? from,
    DateTime? to,
    String? state,
  }) =>
      _client._cardTransactions(card, from, to, state);
}

/// Payment verification and bill payments.
class PaymentsModule {
  PaymentsModule._(this._client);

  final BaridiMob _client;

  /// Dynamic payment forms (for example Algérie Télécom).
  late final DynamicPaymentsModule dynamic = DynamicPaymentsModule._(_client);

  /// Checks that a transfer with reference number [refNum] was received.
  ///
  /// By default the search covers the last 30 days of the first account.
  /// When [amount] is given, the received amount must match it.
  Future<VerifyPaymentResult> verifyPayment({
    required String refNum,
    num? amount,
    String? account,
    DateTime? from,
    DateTime? to,
  }) async {
    final end = to ?? DateTime.now();
    final start = from ?? DateTime.now().subtract(const Duration(days: 30));
    final target =
        account ?? (await _client.accounts.list()).firstOrNull?.number;
    if (target == null) throw DeviceFlowError('No account available');
    final bounds = dayBounds(start, end);

    final matches = <Transaction>[];
    await for (final transaction in _client._transactions(target, start, end)) {
      if (transaction.refNum != refNum) continue;
      if (!isWithinBounds(transaction, bounds.start, bounds.end)) continue;
      matches.add(transaction);
    }

    if (matches.isEmpty) {
      return VerifyPaymentResult(
        verified: false,
        reason: VerifyPaymentReason.notFound,
        transaction: null,
        matches: matches,
      );
    }
    final incoming =
        matches.where((transaction) => transaction.amount > 0).toList();
    if (incoming.isEmpty) {
      return VerifyPaymentResult(
        verified: false,
        reason: VerifyPaymentReason.notIncoming,
        transaction: null,
        matches: matches,
      );
    }
    if (incoming.length > 1) {
      return VerifyPaymentResult(
        verified: false,
        reason: VerifyPaymentReason.duplicate,
        transaction: incoming.first,
        matches: matches,
      );
    }
    final transaction = incoming.single;
    if (amount != null && (transaction.amount - amount).abs() > 0.009) {
      return VerifyPaymentResult(
        verified: false,
        reason: VerifyPaymentReason.amountMismatch,
        transaction: transaction,
        matches: matches,
      );
    }
    return VerifyPaymentResult(
      verified: true,
      reason: VerifyPaymentReason.ok,
      transaction: transaction,
      matches: matches,
    );
  }

  /// Payment categories, for example mobile networks.
  Future<List<PaymentCategory>> categories() async =>
      parsePaymentCategories(await _client._get('paymentCategories'));

  /// Billers of the category [cid].
  Future<List<PaymentProvider>> providers(String cid) async =>
      parsePaymentProviders(
          await _client._get('paymentProviders', {'cid': cid}));

  /// Prepares a payment to the provider [pid]. Then call [requestOtp] and
  /// [exec] with the returned `transRef`.
  ///
  /// [params] holds the fields the provider needs (see
  /// [PaymentProvider.params]), for example `{'phone': '0600000000'}`.
  Future<PaymentCheckResult> check({
    required String pid,
    required num amount,
    required PaymentSource source,
    Map<String, String> params = const {},
    String currency = 'DZD',
  }) async {
    final body = await _client._request(_RequestSpec(
      'POST',
      'paymentCheck',
      params: {
        'pid': pid,
        'amount': numberToString(amount),
        'currency': currency,
        'sourceType': _sourceType(source),
        'sourceId': source.id,
        for (final entry in params.entries) 'param.${entry.key}': entry.value,
      },
    ));
    return PaymentCheckResult(
      transRef: asString(body['transRef']) ?? '',
      confirmationType: asString(asRecord(body['confirmReq'])['type']),
      raw: body,
    );
  }

  /// Sends the SMS code for the payment [transRef].
  Future<void> requestOtp(String transRef) async {
    await _client._request(
      _RequestSpec('GET', 'getOTPbySMS',
          params: {'transRef': transRef}, safe: false),
    );
  }

  /// Executes the payment prepared by [check] with the SMS [otp].
  /// Never retried automatically.
  Future<PaymentExecResult> exec({
    required String pid,
    required num amount,
    required PaymentSource source,
    required String transRef,
    required String otp,
    Map<String, String> params = const {},
    String currency = 'DZD',
  }) async {
    final body = await _client._request(_RequestSpec(
      'POST',
      'paymentExec',
      params: {
        'pid': pid,
        'amount': numberToString(amount),
        'currency': currency,
        'sourceType': _sourceType(source),
        'sourceId': source.id,
        'transRef': transRef,
        'flags': '0',
        'confirmVal': otp,
        for (final entry in params.entries) 'param.${entry.key}': entry.value,
      },
      safe: false,
    ));
    return PaymentExecResult(raw: body);
  }

  static String _sourceType(PaymentSource source) =>
      source.type == PaymentSourceType.card ? '1' : '2';
}

/// Dynamic payment forms.
class DynamicPaymentsModule {
  DynamicPaymentsModule._(this._client);

  final BaridiMob _client;

  /// Groups of dynamic operations.
  Future<List<DynamicGroup>> groups() async =>
      parseDynamicGroups(await _client._get('dynamic/groups'));

  /// Metadata of the operation [id].
  Future<DynamicOperationInfo> operation(String id) async =>
      parseDynamicOperation(
          await _client._get('dynamic/operation', {'operationId': id}));

  /// Submits [params] to the operation [operationId] and returns the next
  /// step.
  ///
  /// [currentStepKey] is the `id` of the step being filled; omit it for the
  /// first call with a fresh operation. [params] are every value so far:
  /// build each step's with [DynamicStep.values] (it adds the hidden values
  /// BaridiMob needs, such as `billerServiceCode=FACTURE` for Algérie
  /// Télécom bills) and merge them. When the form is complete the next step
  /// is [DynamicStep.done]: call [check].
  Future<DynamicStep> step(
    String operationId, [
    Map<String, Object?> params = const {},
    String? currentStepKey,
  ]) async =>
      parseDynamicStep(await _client._request(_RequestSpec(
        'POST',
        'dynamic/operation/step',
        json: {
          'operationId': operationId,
          if (currentStepKey != null) 'currentStepKey': currentStepKey,
          'parameters': params,
        },
      )));

  /// Validates the operation [operationId] with the filled [params] and
  /// returns the reference needed by [exec], with what BaridiMob says about
  /// the operation in [DynamicCheckResult.details] (for a bill: subscriber,
  /// bill, amount due). No money moves and no SMS is sent.
  ///
  /// [params] are every value of every step. The payment source goes under
  /// its field's `idKey`/`typeKey` with a [DynamicSource] type
  /// (`CLIENT_CARD_ID` for a card): BaridiMob answers result 2 to the `1` of
  /// `payments.check`.
  Future<DynamicCheckResult> check(
    String operationId, [
    Map<String, String> params = const {},
  ]) async =>
      parseDynamicCheck(await _client._request(_RequestSpec(
        'POST',
        'dynamic/operation/check',
        params: {
          'operationId': operationId,
          for (final entry in params.entries) 'param.${entry.key}': entry.value,
        },
      )));

  /// Sends the SMS code of the checked operation [transRef].
  Future<void> requestOtp(String transRef) async {
    await _client._request(_RequestSpec(
      'GET',
      'getOTPbySMS',
      params: {'transRef': transRef},
      safe: false,
    ));
  }

  /// Executes the operation prepared by [check] with the SMS [otp].
  /// Never retried automatically.
  Future<DynamicExecResult> exec({
    required String operationId,
    required String transRef,
    required String otp,
    Map<String, String> params = const {},
  }) async =>
      parseDynamicExec(await _client._request(_RequestSpec(
        'POST',
        'dynamic/operation/execute',
        safe: false,
        params: {
          'operationId': operationId,
          'transRef': transRef,
          'confirmVal': otp,
          for (final entry in params.entries) 'param.${entry.key}': entry.value,
        },
      )));

  /// Completes an operation when the server asks for an extra confirmation
  /// step (such as 3D Secure) after [exec].
  Future<DynamicCompleteResult> complete({
    required String operationId,
    required String transRef,
    required String confirmVal,
  }) async =>
      parseDynamicComplete(await _client._request(_RequestSpec(
        'POST',
        'dynamic/operation/complete',
        safe: false,
        params: {
          'operationId': operationId,
          'transRef': transRef,
          'confirmVal': confirmVal,
        },
      )));
}

/// Cash withdrawals without a card. A code is created for an amount and an
/// expiry; at an Algérie Poste ATM, the code takes the cash out.
///
/// ```dart
/// final code = await bm.cardless.create(
///   amount: 2000,
///   source: CardlessSource.account(account.id),
///   expiresAt: DateTime.now().add(const Duration(days: 1)),
/// );
/// print('${code.code} (authorisation ${code.id})');
/// ```
class CardlessModule {
  CardlessModule._(this._client);

  final BaridiMob _client;

  /// The form of a new code: the kinds of withdrawal, the expiry field and
  /// the hidden data BaridiMob signs for this request.
  Future<CardlessForm> form() async => parseCardlessForm(await _client
      ._get('operations/cardless/inputs', {'locale': _client.locale.tag}));

  /// The codes not used yet.
  Future<List<CardlessCode>> list() async =>
      parseCardlessCodes(await _client._get('operations/cardless/list', {
        'locale': _client.locale.tag,
        'lang': _client.locale.name,
      }));

  /// Creates a code for [amount] dinars taken from [source], valid until
  /// [expiresAt] (BaridiMob allows less than six months).
  ///
  /// [type] is the kind of withdrawal (`ATM_CASHWITHDRAWAL` by default, the
  /// first one offered); [values] overrides any field of the [form] by id.
  /// The form is read again when not given: its hidden data is signed per
  /// request. Never retried automatically.
  Future<CardlessCode> create({
    required num amount,
    required CardlessSource source,
    required DateTime expiresAt,
    String? type,
    String currency = 'DZD',
    CardlessForm? form,
    Map<String, String> values = const {},
  }) async {
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'must be positive');
    }
    if (!expiresAt.isAfter(DateTime.now())) {
      throw ArgumentError.value(
          expiresAt, 'expiresAt', 'must be in the future');
    }
    final fields = form ?? await this.form();
    final session = await _client._loadSession();
    final params = <String, String>{
      'amount': numberToString(amount),
      'currency': currency,
      'locale': _client.locale.tag,
      if (source.isCard)
        'sourceCard': source.id
      else
        'sourceAccount': source.id,
    };
    for (final input in fields.inputs) {
      final value = values[input.id] ??
          switch (input.type) {
            'hidden' => _hiddenValue(input, session),
            'select' => (type != null &&
                    input.choices.any((choice) => choice.value == type))
                ? type
                : (input.value ??
                    (input.choices.isEmpty ? null : input.choices.first.value)),
            'datetime' => formatDatePattern(
                expiresAt, input.pattern ?? defaultCardlessDatePattern),
            _ => input.value,
          };
      if (value != null) params['param.${input.id}'] = value;
    }
    final body = await _client._request(_RequestSpec(
      'POST',
      'operations/cardless/generate',
      params: params,
      safe: false,
    ));
    return parseCardlessCode(asRecord(body['operation']));
  }

  /// Deletes the code [id] before it is used. Returns the deleted code when
  /// BaridiMob sends it back.
  Future<CardlessCode?> delete(String id) async {
    final body = await _client._request(_RequestSpec(
      'POST',
      'operations/cardless/delete',
      params: {'id': id, 'locale': _client.locale.tag},
      safe: false,
    ));
    final operation = asRecord(body['operation']);
    return operation.isEmpty ? null : parseCardlessCode(operation);
  }

  // A hidden value is sent back as BaridiMob wrote it; a blank one with a
  // device stereotype takes this device's data, as in the official app.
  static String _hiddenValue(CardlessInput input, StoredSession? session) {
    final value = input.value ?? '';
    if (value.trim().isNotEmpty || session == null) return value;
    return switch (input.stereotype) {
      'deviceId' => session.devid,
      'devicePublicKey' => session.devkey,
      'devicePublicKeyAlgorithm' => session.devkeyAlgorithm,
      _ => value,
    };
  }
}

/// Transfers to other accounts.
class TransfersModule {
  TransfersModule._(this._client);

  final BaridiMob _client;

  /// Confirmation methods available for a transfer, usually `['otp']`.
  Future<List<String>> strategies({
    num amount = 100,
    String currency = 'DZD',
    int actionType = 1,
    int sourceType = 2,
    int targetType = 2,
    int operationSubtype = 0,
  }) async {
    final body = await _client._get('getConfirmationStrategies', {
      'amount': numberToString(amount),
      'currency': currency,
      'actionType': '$actionType',
      'sourceType': '$sourceType',
      'targetType': '$targetType',
      'operationSubtype': '$operationSubtype',
    });
    return [
      for (final value in asArray(body['confirmationStrategies']))
        if (asString(value) case final strategy?) strategy,
    ];
  }

  /// Prepares a transfer of [amount] from [sourceId] to [targetId] (RIP).
  /// Then call [requestOtp] and [exec] with the returned `transRef`.
  Future<TransferArmResult> arm({
    required num amount,
    required String sourceId,
    required String targetId,
    String currency = 'DZD',
    int sourceType = 2,
    int targetType = 2,
  }) async {
    final body =
        await _client._request(_RequestSpec('POST', 'transferCheck', params: {
      'amount': numberToString(amount),
      'currency': currency,
      'sourceType': '$sourceType',
      'sourceId': sourceId,
      'targetType': '$targetType',
      'targetId': targetId,
    }));
    return TransferArmResult(
      transRef: asString(body['transRef']) ?? '',
      confirmationType: asString(asRecord(body['confirmReq'])['type']),
      raw: body,
    );
  }

  /// Sends the SMS code for the transfer [transRef].
  Future<void> requestOtp(String transRef) async {
    await _client._request(
      _RequestSpec('GET', 'getOTPbySMS',
          params: {'transRef': transRef}, safe: false),
    );
  }

  /// Executes the transfer prepared by [arm] with the SMS [otp].
  /// Never retried automatically.
  Future<TransferExecResult> exec({
    required num amount,
    required String sourceId,
    required String targetId,
    required String transRef,
    required String otp,
    String currency = 'DZD',
    int sourceType = 2,
    int targetType = 2,
    int operationSubtype = 0,
  }) async {
    final body = await _client._request(_RequestSpec(
      'POST',
      'transferExec',
      params: {
        'amount': numberToString(amount),
        'currency': currency,
        'sourceType': '$sourceType',
        'sourceId': sourceId,
        'targetType': '$targetType',
        'targetId': targetId,
        'transRef': transRef,
        'flags': '0',
        'confirmVal': otp,
        'operationSubtype': '$operationSubtype',
      },
      safe: false,
    ));
    return TransferExecResult(raw: body);
  }

  /// Prepares a transfer and sends its SMS code in one call. Call
  /// [TransferPending.confirm] with the code to execute it.
  Future<TransferPending> send({
    required num amount,
    required String sourceId,
    required String targetId,
    String currency = 'DZD',
    int sourceType = 2,
    int targetType = 2,
  }) async {
    final armed = await arm(
      amount: amount,
      sourceId: sourceId,
      targetId: targetId,
      currency: currency,
      sourceType: sourceType,
      targetType: targetType,
    );
    await requestOtp(armed.transRef);
    return TransferPending(
      transRef: armed.transRef,
      amount: amount,
      sourceId: sourceId,
      targetId: targetId,
      confirmationType: armed.confirmationType,
      confirm: (otp) => exec(
        amount: amount,
        sourceId: sourceId,
        targetId: targetId,
        transRef: armed.transRef,
        otp: otp,
        currency: currency,
        sourceType: sourceType,
        targetType: targetType,
      ),
    );
  }
}

/// Recent operations and PDF receipts.
class ReceiptsModule {
  ReceiptsModule._(this._client);

  final BaridiMob _client;

  /// Recent operations, each with the `uid` needed by [download].
  Future<List<RecentOperation>> list() async =>
      parseRecentOperations(await _client._get('recentOperations'));

  /// The PDF receipt of the operation [uid].
  Future<Uint8List> download(String uid) => _client._requestBinary(
        _RequestSpec('GET', 'download/receipt',
            params: {'uid': uid}, binary: true),
      );

  /// The recent operation behind [transaction], from the account history.
  ///
  /// Matched by reference number, or by time and amount when the movement
  /// has none. `null` when BaridiMob no longer keeps the operation: receipts
  /// exist only for the last few operations.
  Future<RecentOperation?> find(Transaction transaction) async {
    final operations = await list();
    final reference = transaction.refNum;
    if (reference != null) {
      for (final operation in operations) {
        if (operation.operationId == reference) return operation;
      }
    }
    for (final operation in operations) {
      if (operation.timestamp.isNotEmpty &&
          operation.timestamp == transaction.timestamp &&
          (operation.amount.abs() - transaction.amount.abs()).abs() < 0.01) {
        return operation;
      }
    }
    return null;
  }

  /// The PDF receipt of [transaction], or `null` when BaridiMob no longer
  /// keeps it (see [find]).
  Future<Uint8List?> downloadFor(Transaction transaction) async {
    final operation = await find(transaction);
    if (operation == null || operation.uid.isEmpty) return null;
    return download(operation.uid);
  }
}

/// Holder information.
class ProfileModule {
  ProfileModule._(this._client);

  final BaridiMob _client;

  /// The account holder profile.
  Future<Profile> get() async => parseProfile(await _client._get('profile'));
}
