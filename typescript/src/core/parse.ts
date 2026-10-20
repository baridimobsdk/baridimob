import type {
  Account,
  DynamicGroup,
  DynamicOperationInfo,
  DynamicOperationRef,
  DynamicStep,
  DynamicStepInput,
  PaymentCategory,
  PaymentProvider,
  Profile,
  ProviderParam,
  RecentOperation,
  Transaction,
} from '../types.js';
import { asArray, asNumber, asRecord, asString } from './result.js';

export function parseAccount(raw: Record<string, unknown>): Account {
  const number = asString(raw['number']) ?? asString(raw['id']) ?? '';
  const id = asString(raw['id']) ?? number;
  return {
    id,
    number,
    balance: asNumber(raw['balance']) ?? asNumber(raw['amount']) ?? 0,
    currency: asString(raw['currency']) ?? 'DZD',
    raw,
  };
}

export function parseAccounts(body: Record<string, unknown>): Account[] {
  return asArray(body['accounts']).map((item) => parseAccount(asRecord(item)));
}

export function parseAccountResponse(body: Record<string, unknown>): Account {
  const direct = asRecord(body['account']);
  return parseAccount(Object.keys(direct).length > 0 ? direct : body);
}

export function parseTimestamp(value: string): Date | null {
  const match = /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})$/.exec(value);
  if (!match) return null;
  const [, year, month, day, hour, minute, second] = match;
  if (!year || !month || !day || !hour || !minute || !second) return null;
  const date = new Date(`${year}-${month}-${day}T${hour}:${minute}:${second}+01:00`);
  return Number.isNaN(date.getTime()) ? null : date;
}

function detailValue(details: unknown, id: string): string | null {
  for (const entry of asArray(details)) {
    const item = asRecord(entry);
    if (asString(item['id']) === id) return asString(item['value']);
  }
  return null;
}

export function parseTransaction(raw: Record<string, unknown>): Transaction {
  const timestamp = asString(raw['timestamp']) ?? '';
  return {
    amount: asNumber(raw['amount']) ?? 0,
    currency: asString(raw['currency']) ?? 'DZD',
    description: asString(raw['description']) ?? '',
    type: asString(raw['type']) ?? '',
    tid: asString(raw['tid']) ?? '',
    timestamp,
    date: parseTimestamp(timestamp),
    fee: asNumber(raw['feeAmount']),
    refNum: detailValue(raw['details'], 'refNum'),
    raw,
  };
}

export function parseHistory(body: Record<string, unknown>): Transaction[] {
  return asArray(body['history']).map((item) => parseTransaction(asRecord(item)));
}

export function toDateParam(value: Date | string): string {
  if (typeof value === 'string' && /^\d{8}$/.test(value)) return value;
  const date = typeof value === 'string' ? new Date(value) : value;
  if (Number.isNaN(date.getTime())) {
    throw new TypeError(`Invalid date: ${String(value)}`);
  }
  const shifted = new Date(date.getTime() + 3_600_000);
  const year = shifted.getUTCFullYear();
  const month = String(shifted.getUTCMonth() + 1).padStart(2, '0');
  const day = String(shifted.getUTCDate()).padStart(2, '0');
  return `${year}${month}${day}`;
}

export function dayBounds(
  from: Date | string | undefined,
  to: Date | string | undefined,
): { start: number; end: number } {
  const start = from === undefined ? Number.NEGATIVE_INFINITY : dayStart(from);
  const end = to === undefined ? Number.POSITIVE_INFINITY : dayEnd(to);
  return { start, end };
}

function dayStart(value: Date | string): number {
  const param = toDateParam(value);
  return Date.parse(
    `${param.slice(0, 4)}-${param.slice(4, 6)}-${param.slice(6, 8)}T00:00:00+01:00`,
  );
}

function dayEnd(value: Date | string): number {
  const param = toDateParam(value);
  return Date.parse(
    `${param.slice(0, 4)}-${param.slice(4, 6)}-${param.slice(6, 8)}T23:59:59.999+01:00`,
  );
}

export function isWithinBounds(tx: Transaction, start: number, end: number): boolean {
  if (!tx.date) return false;
  const time = tx.date.getTime();
  return time >= start && time <= end;
}

export function parseProfile(body: Record<string, unknown>): Profile {
  return {
    actorId: asString(body['actorId']) ?? '',
    clientName: asString(body['clientName']),
    lastLogin: asString(body['lastLoginDatetime']),
    financialOperationsDisabled: asNumber(body['financialOperationsDisabled']) === 1,
    raw: body,
  };
}

export function parseRecentOperations(body: Record<string, unknown>): RecentOperation[] {
  return asArray(body['operations']).map((item) => {
    const raw = asRecord(item);
    const timestamp = asString(raw['timestamp']) ?? '';
    return {
      uid: asString(raw['uid']) ?? '',
      type: asString(raw['type']) ?? '',
      pid: asString(raw['pid']) ?? '',
      amount: asNumber(raw['amount']) ?? 0,
      currency: asString(raw['currency']) ?? 'DZD',
      timestamp,
      date: parseTimestamp(timestamp),
      providerName: asString(raw['providerName']),
      sourceType: asNumber(raw['sourceType']),
      sourceId: asString(raw['sourceId']),
      status: asNumber(raw['status']),
      raw,
    };
  });
}

export function parsePaymentCategories(body: Record<string, unknown>): PaymentCategory[] {
  return asArray(body['categories']).map((item) => {
    const raw = asRecord(item);
    return {
      cid: asString(raw['cid']) ?? '',
      name: asString(raw['name']) ?? '',
      image: asString(raw['image']),
      raw,
    };
  });
}

function parseProviderParam(value: unknown): ProviderParam {
  const raw = asRecord(value);
  return {
    id: asString(raw['id']) ?? '',
    name: asString(raw['name']) ?? '',
    type: asString(raw['type']) ?? '',
    pattern: asString(raw['pattern']),
    min: asNumber(raw['min']),
    max: asNumber(raw['max']),
    value: asString(raw['value']),
    description: asString(raw['description']),
    hasExternalHandler: raw['hasExternalHandler'] === true,
  };
}

export function parsePaymentProviders(body: Record<string, unknown>): PaymentProvider[] {
  return asArray(body['providers']).map((item) => {
    const raw = asRecord(item);
    return {
      pid: asString(raw['pid']) ?? '',
      name: asString(raw['name']) ?? '',
      mappedId: asString(raw['mappedId']),
      cid: asString(raw['cid']),
      scenario: asString(raw['scenario']),
      categoryName: asString(raw['categoryName']),
      params: asArray(raw['params']).map(parseProviderParam),
      raw,
    };
  });
}

function parseOperationRef(value: unknown): DynamicOperationRef {
  const raw = asRecord(value);
  return { id: asString(raw['id']) ?? '', label: asString(raw['label']) ?? '' };
}

export function parseDynamicGroups(body: Record<string, unknown>): DynamicGroup[] {
  return asArray(body['groups']).map((item) => {
    const raw = asRecord(item);
    return {
      id: asString(raw['id']) ?? '',
      label: asString(raw['label']) ?? '',
      type: asString(raw['type']),
      image: asString(raw['image']),
      operations: asArray(raw['operations']).map(parseOperationRef),
      raw,
    };
  });
}

export function parseDynamicOperation(body: Record<string, unknown>): DynamicOperationInfo {
  const raw = asRecord(body['operationInfo']);
  return {
    id: asString(raw['id']) ?? '',
    label: asString(raw['label']) ?? '',
    firstStep: raw['firstStep'] ? parseOperationRef(raw['firstStep']) : null,
    saveTemplateEnabled: raw['saveTemplateEnabled'] === true,
    raw,
  };
}

function parseStepInput(value: unknown): DynamicStepInput {
  const raw = asRecord(value);
  const settings = asRecord(raw['settings']);
  const required =
    raw['required'] === true || settings['required'] === true || settings['required'] === 'true';
  return {
    id: asString(raw['id']) ?? '',
    label: asString(raw['label']) ?? '',
    type: asString(raw['type']) ?? '',
    required,
    settings: raw['settings'] ?? null,
    raw,
  };
}

export function parseDynamicStep(body: Record<string, unknown>): DynamicStep {
  const raw = asRecord(body['currentStep']);
  return {
    id: asString(raw['id']) ?? '',
    label: asString(raw['label']) ?? '',
    inputs: asArray(raw['inputs']).map(parseStepInput),
    raw,
  };
}
