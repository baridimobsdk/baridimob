import 'result.dart';
import 'types.dart';

/// Algeria is UTC+1 all year round.
const Duration _algeriaOffset = Duration(hours: 1);

/// Parses one account entry.
Account parseAccount(Map<String, Object?> raw) {
  final number = asString(raw['number']) ?? asString(raw['id']) ?? '';
  return Account(
    id: asString(raw['id']) ?? number,
    number: number,
    balance:
        (asNumber(raw['balance']) ?? asNumber(raw['amount']) ?? 0).toDouble(),
    currency: asString(raw['currency']) ?? 'DZD',
    raw: raw,
  );
}

/// Parses the `accounts` response.
List<Account> parseAccounts(Map<String, Object?> body) => [
      for (final item in asArray(body['accounts'])) parseAccount(asRecord(item))
    ];

/// Parses the `account` response, which may or may not wrap the account.
Account parseAccountResponse(Map<String, Object?> body) {
  final direct = asRecord(body['account']);
  return parseAccount(direct.isNotEmpty ? direct : body);
}

/// Parses a `yyyyMMddHHmmss` server timestamp (Algeria time) to a UTC
/// [DateTime]. Returns `null` for malformed values.
DateTime? parseTimestamp(String value) {
  final match =
      RegExp(r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})$').firstMatch(value);
  if (match == null) return null;
  final parts = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
  final local =
      DateTime.utc(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]);
  final valid = local.year == parts[0] &&
      local.month == parts[1] &&
      local.day == parts[2] &&
      local.hour == parts[3] &&
      local.minute == parts[4] &&
      local.second == parts[5];
  return valid ? local.subtract(_algeriaOffset) : null;
}

String? _detailValue(Object? details, String id) {
  for (final entry in asArray(details)) {
    final item = asRecord(entry);
    if (asString(item['id']) == id) return asString(item['value']);
  }
  return null;
}

/// Parses one history entry.
Transaction parseTransaction(Map<String, Object?> raw) {
  final timestamp = asString(raw['timestamp']) ?? '';
  return Transaction(
    amount: (asNumber(raw['amount']) ?? 0).toDouble(),
    currency: asString(raw['currency']) ?? 'DZD',
    description: asString(raw['description']) ?? '',
    type: asString(raw['type']) ?? '',
    tid: asString(raw['tid']) ?? '',
    timestamp: timestamp,
    date: parseTimestamp(timestamp),
    fee: asNumber(raw['feeAmount'])?.toDouble(),
    refNum: _detailValue(raw['details'], 'refNum'),
    raw: raw,
  );
}

/// Parses the `accountHistory` response.
List<Transaction> parseHistory(Map<String, Object?> body) => [
      for (final item in asArray(body['history']))
        parseTransaction(asRecord(item))
    ];

/// A server flag, sent as `0`/`1`, `true`/`false` or a numeric string.
bool _flag(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  final number = asNumber(value);
  return number == null ? fallback : number != 0;
}

/// Parses one card.
BaridiMobCard parseCard(Map<String, Object?> raw) {
  final linked = <String>[];
  for (final item in asArray(raw['linkedAccounts'])) {
    final value = asString(item);
    if (value != null) linked.add(value);
  }
  return BaridiMobCard(
    id: asString(raw['id']) ?? '',
    number: asString(raw['number']) ?? '',
    name: asString(raw['name']) ?? '',
    brand: asString(raw['brand']) ?? '',
    status: asNumber(raw['status'])?.toInt() ?? -1,
    expDate: asString(raw['expDate']) ?? '',
    type: asNumber(raw['type'])?.toInt() ?? 0,
    category: asString(raw['category']),
    balance: asNumber(raw['balance'])?.toDouble(),
    currency: asString(raw['currency']),
    embossedName: asString(raw['embossedName']),
    active: _flag(raw['active'], fallback: true),
    pinNotSet: _flag(raw['pinNotSet']),
    linkedAccounts: linked,
    isDebitAllowed: _flag(raw['isDebitAllowed'], fallback: true),
    raw: raw,
  );
}

/// Parses the `cards` response.
List<BaridiMobCard> parseCards(Map<String, Object?> body) =>
    [for (final item in asArray(body['cards'])) parseCard(asRecord(item))];

/// Parses the `card` response, which may or may not wrap the card.
BaridiMobCard parseCardResponse(Map<String, Object?> body) {
  final direct = asRecord(body['card']);
  return parseCard(direct.isNotEmpty ? direct : body);
}

/// Parses one card limit.
CardLimit _parseCardLimit(Map<String, Object?> raw) => CardLimit(
      uid: asString(raw['uid']) ?? '',
      name: asString(raw['name']) ?? '',
      description: asString(raw['description']),
      type: asNumber(raw['type'])?.toInt() ?? 0,
      amount: asNumber(raw['amount'])?.toDouble(),
      usedAmount: asNumber(raw['usedAmount'])?.toDouble(),
      opCount: asNumber(raw['opCount'])?.toInt(),
      usedOpCount: asNumber(raw['usedOpCount'])?.toInt(),
      currency: asString(raw['currency']),
      active: _flag(raw['active'], fallback: true),
      changeable: _flag(raw['changeable']),
      permanent: _flag(raw['permanent']),
      perTransaction: _flag(raw['perTransaction']),
      endTime: asString(raw['endTime']),
      raw: raw,
    );

/// Parses the `cardLimits` response.
List<CardLimit> parseCardLimits(Map<String, Object?> body) => [
      for (final item in asArray(body['limits']))
        _parseCardLimit(asRecord(item))
    ];

/// Formats [value] as the `yyyyMMdd` date expected by the server.
///
/// A UTC [DateTime] is converted to Algeria time first; a local one is used
/// as a calendar date, so `DateTime(2026, 1, 31)` always means January 31.
String toDateParam(DateTime value) {
  final date = value.isUtc ? value.add(_algeriaOffset) : value;
  return '${date.year.toString().padLeft(4, '0')}'
      '${date.month.toString().padLeft(2, '0')}'
      '${date.day.toString().padLeft(2, '0')}';
}

/// First and last instant (UTC) of the days covered by [from] and [to],
/// in Algeria time. A `null` bound is open.
({DateTime? start, DateTime? end}) dayBounds(DateTime? from, DateTime? to) {
  DateTime? edge(DateTime? value, {required bool end}) {
    if (value == null) return null;
    final day = toDateParam(value);
    final year = int.parse(day.substring(0, 4));
    final month = int.parse(day.substring(4, 6));
    final date = int.parse(day.substring(6, 8));
    final local = end
        ? DateTime.utc(year, month, date, 23, 59, 59, 999)
        : DateTime.utc(year, month, date);
    return local.subtract(_algeriaOffset);
  }

  return (start: edge(from, end: false), end: edge(to, end: true));
}

/// Whether [transaction] happened between [start] and [end] (inclusive).
bool isWithinBounds(Transaction transaction, DateTime? start, DateTime? end) {
  final date = transaction.date;
  if (date == null) return false;
  if (start != null && date.isBefore(start)) return false;
  if (end != null && date.isAfter(end)) return false;
  return true;
}

/// Parses the `profile` response.
Profile parseProfile(Map<String, Object?> body) => Profile(
      actorId: asString(body['actorId']) ?? '',
      clientName: asString(body['clientName']),
      lastLogin: asString(body['lastLoginDatetime']),
      financialOperationsDisabled:
          asNumber(body['financialOperationsDisabled']) == 1,
      raw: body,
    );

RecentOperation _parseRecentOperation(Object? item) {
  final raw = asRecord(item);
  final timestamp = asString(raw['timestamp']) ?? '';
  return RecentOperation(
    uid: asString(raw['uid']) ?? '',
    type: asString(raw['type']) ?? '',
    pid: asString(raw['pid']) ?? '',
    amount: (asNumber(raw['amount']) ?? 0).toDouble(),
    currency: asString(raw['currency']) ?? 'DZD',
    timestamp: timestamp,
    date: parseTimestamp(timestamp),
    providerName: asString(raw['providerName']),
    sourceType: asNumber(raw['sourceType'])?.toInt(),
    sourceId: asString(raw['sourceId']),
    status: asNumber(raw['status'])?.toInt(),
    operationId: _detailValue(raw['details'], 'operationId'),
    raw: raw,
  );
}

/// Parses the `recentOperations` response.
List<RecentOperation> parseRecentOperations(Map<String, Object?> body) => [
      for (final item in asArray(body['operations']))
        _parseRecentOperation(item)
    ];

PaymentCategory _parsePaymentCategory(Object? item) {
  final raw = asRecord(item);
  return PaymentCategory(
    cid: asString(raw['cid']) ?? '',
    name: asString(raw['name']) ?? '',
    image: asString(raw['image']),
    raw: raw,
  );
}

/// Parses the `paymentCategories` response.
List<PaymentCategory> parsePaymentCategories(Map<String, Object?> body) => [
      for (final item in asArray(body['categories']))
        _parsePaymentCategory(item)
    ];

ProviderParam _parseProviderParam(Object? value) {
  final raw = asRecord(value);
  return ProviderParam(
    id: asString(raw['id']) ?? '',
    name: asString(raw['name']) ?? '',
    type: asString(raw['type']) ?? '',
    pattern: asString(raw['pattern']),
    min: asNumber(raw['min']),
    max: asNumber(raw['max']),
    value: asString(raw['value']),
    description: asString(raw['description']),
    hasExternalHandler: raw['hasExternalHandler'] == true,
  );
}

PaymentProvider _parsePaymentProvider(Object? item) {
  final raw = asRecord(item);
  return PaymentProvider(
    pid: asString(raw['pid']) ?? '',
    name: asString(raw['name']) ?? '',
    mappedId: asString(raw['mappedId']),
    cid: asString(raw['cid']),
    scenario: asString(raw['scenario']),
    categoryName: asString(raw['categoryName']),
    params: [
      for (final param in asArray(raw['params'])) _parseProviderParam(param)
    ],
    raw: raw,
  );
}

/// Parses the `paymentProviders` response.
List<PaymentProvider> parsePaymentProviders(Map<String, Object?> body) => [
      for (final item in asArray(body['providers'])) _parsePaymentProvider(item)
    ];

DynamicOperationRef _parseOperationRef(Object? value) {
  final raw = asRecord(value);
  return DynamicOperationRef(
      id: asString(raw['id']) ?? '', label: asString(raw['label']) ?? '');
}

DynamicGroup _parseDynamicGroup(Object? item) {
  final raw = asRecord(item);
  return DynamicGroup(
    id: asString(raw['id']) ?? '',
    label: asString(raw['label']) ?? '',
    type: asString(raw['type']),
    image: asString(raw['image']),
    operations: [
      for (final op in asArray(raw['operations'])) _parseOperationRef(op)
    ],
    raw: raw,
  );
}

/// Parses the `dynamic/groups` response.
List<DynamicGroup> parseDynamicGroups(Map<String, Object?> body) =>
    [for (final item in asArray(body['groups'])) _parseDynamicGroup(item)];

/// Parses the `dynamic/operation` response.
DynamicOperationInfo parseDynamicOperation(Map<String, Object?> body) {
  final raw = asRecord(body['operationInfo']);
  return DynamicOperationInfo(
    id: asString(raw['id']) ?? '',
    label: asString(raw['label']) ?? '',
    firstStep:
        raw['firstStep'] is Map ? _parseOperationRef(raw['firstStep']) : null,
    saveTemplateEnabled: raw['saveTemplateEnabled'] == true,
    raw: raw,
  );
}

/// A setting or flag sent as `true`/`false`, `"true"`/`"false"` or `0`/`1`.
bool _setting(Object? value) =>
    value == true || value == 'true' || (asNumber(value) ?? 0) != 0;

/// An amount sent as `{amount, currency}`, a number or a numeric string.
DynamicAmount? _parseAmount(Object? value, {String? currency}) {
  if (value is Map) {
    final raw = asRecord(value);
    final text = asString(raw['amount'] ?? raw['sum'] ?? raw['value']);
    if (text == null || text.trim().isEmpty) return null;
    return DynamicAmount(
        text: text.trim(), currency: asString(raw['currency']) ?? currency);
  }
  final text = asString(value);
  if (text == null || text.trim().isEmpty) return null;
  return DynamicAmount(text: text.trim(), currency: currency);
}

DynamicStepInput _parseStepInput(Object? value) {
  final raw = asRecord(value);
  final settings = asRecord(raw['settings']);
  final type = asString(raw['type']) ?? '';
  final accessAttributes = <String>[];
  for (final item in asArray(raw['accessAttributes'])) {
    final text = asString(item);
    if (text != null) accessAttributes.add(text);
  }
  final money = type == 'money';
  String? prefilled;
  if (!money) {
    prefilled = asString(raw['value']);
    if (prefilled == null || prefilled.isEmpty) {
      if (type == 'hidden') {
        prefilled = asString(settings['value']) ?? prefilled;
      } else if (type == 'string' || type == 'phone') {
        prefilled = asString(settings['defaultValue']) ?? prefilled;
      }
    }
  }
  return DynamicStepInput(
    id: asString(raw['id']) ?? '',
    label: asString(raw['label']) ?? '',
    type: type,
    required: _setting(raw['required']) || _setting(settings['required']),
    settings: raw['settings'],
    choices: money
        ? const []
        : [
            for (final item in asArray(raw['selectionList']))
              DynamicChoice(
                value: asString(asRecord(item)['value']) ?? '',
                label: asString(asRecord(item)['label']) ?? '',
              )
          ],
    accessAttributes: accessAttributes,
    value: prefilled,
    amount: money ? _parseAmount(raw['value']) : null,
    amountMode: money && '${settings['mode'] ?? ''}'.toUpperCase() == 'SELECT'
        ? DynamicAmountMode.select
        : DynamicAmountMode.input,
    amountChoices: money
        ? [
            for (final item in asArray(raw['selectionList']))
              if (_parseAmount(asRecord(item)['value']) case final amount?)
                DynamicAmountChoice(
                  label: asString(asRecord(item)['label']) ?? amount.text,
                  amount: amount,
                )
          ]
        : const [],
    readonly: _setting(settings['readonly']) || _setting(raw['readOnly']),
    ordinalNumber: asNumber(raw['ordinalNumber'])?.toInt(),
    description: asString(raw['description']),
    raw: raw,
  );
}

/// Parses the `dynamic/operation/step` response. Fields come in the order
/// of their `ordinalNumber`; a response without a step is [DynamicStep.done].
DynamicStep parseDynamicStep(Map<String, Object?> body) {
  final value = body['currentStep'];
  if (value is! Map) {
    return DynamicStep(id: '', label: '', done: true, raw: body);
  }
  final raw = asRecord(value);
  final inputs = [
    for (final input in asArray(raw['inputs'])) _parseStepInput(input)
  ];
  // A stable sort, as the official app's comparator (no number counts as 0).
  final order = {for (var i = 0; i < inputs.length; i++) inputs[i]: i};
  inputs.sort((a, b) {
    final byNumber = (a.ordinalNumber ?? 0).compareTo(b.ordinalNumber ?? 0);
    return byNumber != 0 ? byNumber : order[a]!.compareTo(order[b]!);
  });
  return DynamicStep(
    id: asString(raw['id']) ?? '',
    label: asString(raw['label']) ?? '',
    inputs: inputs,
    raw: raw,
  );
}

/// Parses the `details` of a dynamic check or execution (and the
/// `additionalData` of a cardless code).
List<DynamicDetail> parseDynamicDetails(Object? value) => [
      for (final item in asArray(value))
        if (asRecord(item) case final raw when raw.isNotEmpty)
          DynamicDetail(
            id: asString(raw['id']) ?? '',
            label: asString(raw['label']) ?? '',
            type: asString(raw['type']) ?? '',
            text: asString(raw['type']) == 'money'
                ? null
                : (raw['value'] is bool
                    ? '${raw['value']}'
                    : asString(raw['value'])),
            amount: asString(raw['type']) == 'money'
                ? _parseAmount(raw['value'])
                : null,
            raw: raw,
          )
    ];

/// Parses the `dynamic/operation/check` response.
DynamicCheckResult parseDynamicCheck(Map<String, Object?> body) =>
    DynamicCheckResult(
      transRef: asString(body['transRef']) ?? '',
      confirmationType: asString(asRecord(body['confirmReq'])['type']),
      fee: asNumber(body['fee'])?.toDouble(),
      currency: asString(body['currency']),
      planDate: asString(body['planDate']),
      details: parseDynamicDetails(body['details']),
      raw: body,
    );

/// Parses the `dynamic/operation/execute` response.
DynamicExecResult parseDynamicExec(Map<String, Object?> body) =>
    DynamicExecResult(
      transRef: asString(body['transRef']),
      recentOpId: asString(body['recentOpId']),
      recentOpType: asString(body['recentOpType']),
      authid: asString(body['authid']),
      confirmationType: asString(asRecord(body['confirmReq'])['type']),
      status: asString(asRecord(body['operationStatus'])['type']),
      fee: asNumber(body['fee'])?.toDouble(),
      currency: asString(body['currency']),
      details: parseDynamicDetails(body['details']),
      raw: body,
    );

/// Parses the `dynamic/operation/complete` response.
DynamicCompleteResult parseDynamicComplete(Map<String, Object?> body) =>
    DynamicCompleteResult(
      recentOpId: asString(body['recentOpId']),
      recentOpType: asString(body['recentOpType']),
      authid: asString(body['authid']),
      raw: body,
    );

CardlessInput _parseCardlessInput(Object? value) {
  final raw = asRecord(value);
  final settings = asRecord(raw['settings']);
  return CardlessInput(
    id: asString(raw['id']) ?? '',
    label: asString(raw['label']) ?? '',
    type: asString(raw['type']) ?? '',
    description: asString(raw['description']),
    required: _setting(raw['required']) || _setting(settings['required']),
    readonly: _setting(raw['readOnly']) || _setting(settings['readonly']),
    value: asString(raw['value']) ?? asString(settings['value']),
    stereotype: asString(raw['stereotype']),
    pattern: asString(raw['pattern']),
    future: _setting(raw['future']),
    choices: [
      for (final item in asArray(raw['selectionList']))
        DynamicChoice(
          value: asString(asRecord(item)['value']) ?? '',
          label: asString(asRecord(item)['label']) ?? '',
        )
    ],
    raw: raw,
  );
}

/// Parses the `operations/cardless/inputs` response.
CardlessForm parseCardlessForm(Map<String, Object?> body) => CardlessForm(
      inputs: [
        for (final item in asArray(body['inputs'])) _parseCardlessInput(item)
      ],
      raw: body,
    );

/// Parses one cardless operation.
CardlessCode parseCardlessCode(Map<String, Object?> raw) => CardlessCode(
      id: asString(raw['id']) ?? '',
      code: asString(raw['code']),
      amount: asNumber(raw['amount'])?.toDouble(),
      currency: asString(raw['currency']),
      status: asString(raw['status']),
      details: parseDynamicDetails(raw['additionalData']),
      raw: raw,
    );

/// Parses the `operations/cardless/list` response.
List<CardlessCode> parseCardlessCodes(Map<String, Object?> body) => [
      for (final item in asArray(body['operations']))
        if (asRecord(item) case final raw when raw.isNotEmpty)
          parseCardlessCode(raw)
    ];

/// Date pattern of the cardless expiry field.
const String defaultCardlessDatePattern = "yyyy-MM-dd'T'HH:mm:ss.SSSXXX";

/// Formats [date] in Algeria time (UTC+1) with a Java date [pattern]:
/// `yyyy`, `MM`, `dd`, `HH`, `mm`, `ss`, `SSS`, an offset (`XXX`, `Z`) and
/// quoted literals.
String formatDatePattern(DateTime date, String pattern) {
  final local = date.toUtc().add(_algeriaOffset);
  String pad(int value, int width) => value.toString().padLeft(width, '0');
  final out = StringBuffer();
  var i = 0;
  while (i < pattern.length) {
    final letter = pattern[i];
    if (letter == "'") {
      final end = pattern.indexOf("'", i + 1);
      if (end < 0) {
        out.write(pattern.substring(i + 1));
        break;
      }
      out.write(end == i + 1 ? "'" : pattern.substring(i + 1, end));
      i = end + 1;
      continue;
    }
    var j = i;
    while (j < pattern.length && pattern[j] == letter) {
      j++;
    }
    final width = j - i;
    switch (letter) {
      case 'y':
        out.write(
            width == 2 ? pad(local.year % 100, 2) : pad(local.year, width));
      case 'M':
        out.write(pad(local.month, width));
      case 'd':
        out.write(pad(local.day, width));
      case 'H':
        out.write(pad(local.hour, width));
      case 'm':
        out.write(pad(local.minute, width));
      case 's':
        out.write(pad(local.second, width));
      case 'S':
        out.write(pad(local.millisecond, width));
      case 'X':
        out.write(width == 1 ? '+01' : (width == 2 ? '+0100' : '+01:00'));
      case 'Z':
        out.write(width >= 5 ? '+01:00' : '+0100');
      default:
        out.write(pattern.substring(i, j));
    }
    i = j;
  }
  return out.toString();
}
