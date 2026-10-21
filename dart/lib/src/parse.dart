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

DynamicStepInput _parseStepInput(Object? value) {
  final raw = asRecord(value);
  final settings = asRecord(raw['settings']);
  return DynamicStepInput(
    id: asString(raw['id']) ?? '',
    label: asString(raw['label']) ?? '',
    type: asString(raw['type']) ?? '',
    required: raw['required'] == true ||
        settings['required'] == true ||
        settings['required'] == 'true',
    settings: raw['settings'],
    raw: raw,
  );
}

/// Parses the `dynamic/operation/step` response.
DynamicStep parseDynamicStep(Map<String, Object?> body) {
  final raw = asRecord(body['currentStep']);
  return DynamicStep(
    id: asString(raw['id']) ?? '',
    label: asString(raw['label']) ?? '',
    inputs: [
      for (final input in asArray(raw['inputs'])) _parseStepInput(input)
    ],
    raw: raw,
  );
}
