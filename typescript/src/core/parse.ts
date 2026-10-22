import type {
  Account,
  Card,
  CardLimit,
  CardlessCode,
  CardlessForm,
  CardlessInput,
  DynamicAmount,
  DynamicAmountChoice,
  DynamicCheckResult,
  DynamicChoice,
  DynamicCompleteResult,
  DynamicDetail,
  DynamicExecResult,
  DynamicGroup,
  DynamicInputValuesOptions,
  DynamicOperationInfo,
  DynamicOperationRef,
  DynamicStep,
  DynamicStepInput,
  DynamicValuesOptions,
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

function flag(value: unknown, fallback = false): boolean {
  if (typeof value === 'boolean') return value;
  const number = asNumber(value);
  return number === null ? fallback : number !== 0;
}

export function parseCard(raw: Record<string, unknown>): Card {
  return {
    id: asString(raw['id']) ?? '',
    number: asString(raw['number']) ?? '',
    name: asString(raw['name']) ?? '',
    brand: asString(raw['brand']) ?? '',
    status: asNumber(raw['status']) ?? -1,
    expDate: asString(raw['expDate']) ?? '',
    type: asNumber(raw['type']) ?? 0,
    category: asString(raw['category']),
    balance: asNumber(raw['balance']),
    currency: asString(raw['currency']),
    embossedName: asString(raw['embossedName']),
    active: flag(raw['active'], true),
    pinNotSet: flag(raw['pinNotSet']),
    linkedAccounts: asArray(raw['linkedAccounts'])
      .map((item) => asString(item))
      .filter((value): value is string => value !== null),
    isDebitAllowed: flag(raw['isDebitAllowed'], true),
    raw,
  };
}

export function parseCards(body: Record<string, unknown>): Card[] {
  return asArray(body['cards']).map((item) => parseCard(asRecord(item)));
}

export function parseCardResponse(body: Record<string, unknown>): Card {
  const direct = asRecord(body['card']);
  return parseCard(Object.keys(direct).length > 0 ? direct : body);
}

export function parseCardLimit(raw: Record<string, unknown>): CardLimit {
  return {
    uid: asString(raw['uid']) ?? '',
    name: asString(raw['name']) ?? '',
    description: asString(raw['description']),
    type: asNumber(raw['type']) ?? 0,
    amount: asNumber(raw['amount']),
    usedAmount: asNumber(raw['usedAmount']),
    opCount: asNumber(raw['opCount']),
    usedOpCount: asNumber(raw['usedOpCount']),
    currency: asString(raw['currency']),
    active: flag(raw['active'], true),
    changeable: flag(raw['changeable']),
    permanent: flag(raw['permanent']),
    perTransaction: flag(raw['perTransaction']),
    endTime: asString(raw['endTime']),
    raw,
  };
}

export function parseCardLimits(body: Record<string, unknown>): CardLimit[] {
  return asArray(body['limits']).map((item) => parseCardLimit(asRecord(item)));
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
      operationId: detailValue(raw['details'], 'operationId'),
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

// A setting sent as true/false, "true"/"false" or 0/1.
function settingFlag(value: unknown): boolean {
  if (value === true || value === 'true') return true;
  const number = asNumber(value);
  return number !== null && number !== 0;
}

function amountOf(text: string, currency: string | null): DynamicAmount {
  const trimmed = text.trim();
  const value = trimmed === '' ? Number.NaN : Number(trimmed.replace(/,/g, '.'));
  return { text: trimmed, currency, value: Number.isFinite(value) ? value : null };
}

function parseAmount(value: unknown, currency: string | null = null): DynamicAmount | null {
  if (typeof value === 'object' && value !== null && !Array.isArray(value)) {
    const raw = asRecord(value);
    const text = asString(raw['amount'] ?? raw['sum'] ?? raw['value']);
    if (text === null || text.trim() === '') return null;
    return amountOf(text, asString(raw['currency']) ?? currency);
  }
  const text = asString(value);
  if (text === null || text.trim() === '') return null;
  return amountOf(text, currency);
}

function valueKey(input: DynamicStepInput, name: string, fallback: string): string {
  const key = input.setting(name);
  return key === null || key === '' ? fallback : key;
}

function inputValues(
  input: DynamicStepInput,
  options: DynamicInputValuesOptions,
): Record<string, string> {
  switch (input.type) {
    case 'hidden':
      return { [input.id]: input.value ?? '' };
    case 'source_storage': {
      const source = options.source;
      if (!source) return {};
      return {
        [valueKey(input, 'idKey', 'sourceId')]: source.id,
        [valueKey(input, 'typeKey', 'sourceType')]: source.type,
      };
    }
    case 'money': {
      const typed = options.entered?.trim();
      const chosen = input.readonly
        ? input.amount
        : (options.amount ??
          (typed !== undefined && typed !== '' ? amountOf(typed, null) : input.amount));
      if (!chosen || chosen.text.trim() === '') return {};
      return {
        [valueKey(input, 'amountKey', 'amount')]: chosen.text.trim(),
        [valueKey(input, 'currencyKey', 'currency')]:
          chosen.currency ?? input.amount?.currency ?? input.setting('defaultCurrency') ?? 'DZD',
      };
    }
    case 'string':
    case 'phone':
    case 'text':
    case 'email':
    case 'select':
    case 'datetime':
    case 'monthyear': {
      const text = input.readonly ? input.value : (options.entered ?? input.value);
      if (text === null || text === '') return {};
      return { [input.id]: text };
    }
    default:
      return {};
  }
}

function parseStepInput(value: unknown): DynamicStepInput {
  const raw = asRecord(value);
  const settings = asRecord(raw['settings']);
  const type = asString(raw['type']) ?? '';
  const money = type === 'money';
  let prefilled: string | null = null;
  if (!money) {
    prefilled = asString(raw['value']);
    if (prefilled === null || prefilled === '') {
      if (type === 'hidden') prefilled = asString(settings['value']) ?? prefilled;
      else if (type === 'string' || type === 'phone') {
        prefilled = asString(settings['defaultValue']) ?? prefilled;
      }
    }
  }
  const setting = (key: string): string | null => {
    const item = settings[key];
    if (typeof item === 'string') return item;
    if (typeof item === 'number' || typeof item === 'boolean') return String(item);
    return null;
  };
  const amountChoices: DynamicAmountChoice[] = [];
  const choices: DynamicChoice[] = [];
  for (const item of asArray(raw['selectionList'])) {
    const entry = asRecord(item);
    if (money) {
      const amount = parseAmount(entry['value']);
      if (amount) amountChoices.push({ label: asString(entry['label']) ?? amount.text, amount });
    } else {
      choices.push({
        value: asString(entry['value']) ?? '',
        label: asString(entry['label']) ?? '',
      });
    }
  }
  const ordinal = asNumber(raw['ordinalNumber']);
  const input: DynamicStepInput = {
    id: asString(raw['id']) ?? '',
    label: asString(raw['label']) ?? '',
    type,
    required: settingFlag(raw['required']) || settingFlag(settings['required']),
    settings: raw['settings'] ?? null,
    choices,
    accessAttributes: asArray(raw['accessAttributes'])
      .map((item) => asString(item))
      .filter((item): item is string => item !== null),
    value: prefilled,
    amount: money ? parseAmount(raw['value']) : null,
    amountMode:
      money && String(settings['mode'] ?? '').toUpperCase() === 'SELECT' ? 'select' : 'input',
    amountChoices,
    readonly: settingFlag(settings['readonly']) || settingFlag(raw['readOnly']),
    ordinalNumber: ordinal === null ? null : Math.trunc(ordinal),
    description: asString(raw['description']),
    isHidden: type === 'hidden',
    isSource: type === 'source_storage',
    isMoney: money,
    isSelect: type === 'select',
    setting,
    valuesFor: (options = {}) => inputValues(input, options),
    raw,
  };
  return input;
}

function stepValues(
  inputs: DynamicStepInput[],
  options: DynamicValuesOptions,
): Record<string, string> {
  const values: Record<string, string> = {};
  for (const input of inputs) {
    const entered = options.entered?.[input.id];
    Object.assign(
      values,
      input.valuesFor({
        ...(entered === undefined ? {} : { entered }),
        ...(options.source === undefined ? {} : { source: options.source }),
        ...(options.amount === undefined ? {} : { amount: options.amount }),
      }),
    );
  }
  return values;
}

export function parseDynamicStep(body: Record<string, unknown>): DynamicStep {
  const current = body['currentStep'];
  if (typeof current !== 'object' || current === null || Array.isArray(current)) {
    return { id: '', label: '', inputs: [], done: true, values: () => ({}), raw: body };
  }
  const raw = asRecord(current);
  // A stable sort, as the official app's comparator (no number counts as 0).
  const inputs = asArray(raw['inputs'])
    .map(parseStepInput)
    .sort((a, b) => (a.ordinalNumber ?? 0) - (b.ordinalNumber ?? 0));
  return {
    id: asString(raw['id']) ?? '',
    label: asString(raw['label']) ?? '',
    inputs,
    done: false,
    values: (options = {}) => stepValues(inputs, options),
    raw,
  };
}

export function parseDynamicDetails(value: unknown): DynamicDetail[] {
  const details: DynamicDetail[] = [];
  for (const item of asArray(value)) {
    const raw = asRecord(item);
    if (Object.keys(raw).length === 0) continue;
    const type = asString(raw['type']) ?? '';
    const money = type === 'money';
    const content = raw['value'];
    details.push({
      id: asString(raw['id']) ?? '',
      label: asString(raw['label']) ?? '',
      type,
      text: money ? null : typeof content === 'boolean' ? String(content) : asString(content),
      amount: money ? parseAmount(content) : null,
      raw,
    });
  }
  return details;
}

export function parseDynamicCheck(body: Record<string, unknown>): DynamicCheckResult {
  const details = parseDynamicDetails(body['details']);
  return {
    transRef: asString(body['transRef']) ?? '',
    confirmationType: asString(asRecord(body['confirmReq'])['type']),
    fee: asNumber(body['fee']),
    currency: asString(body['currency']),
    planDate: asString(body['planDate']),
    details,
    amount: details.find((detail) => detail.amount !== null)?.amount ?? null,
    raw: body,
  };
}

export function parseDynamicExec(body: Record<string, unknown>): DynamicExecResult {
  return {
    transRef: asString(body['transRef']),
    recentOpId: asString(body['recentOpId']),
    recentOpType: asString(body['recentOpType']),
    authid: asString(body['authid']),
    confirmationType: asString(asRecord(body['confirmReq'])['type']),
    status: asString(asRecord(body['operationStatus'])['type']),
    fee: asNumber(body['fee']),
    currency: asString(body['currency']),
    details: parseDynamicDetails(body['details']),
    raw: body,
  };
}

export function parseDynamicComplete(body: Record<string, unknown>): DynamicCompleteResult {
  return {
    recentOpId: asString(body['recentOpId']),
    recentOpType: asString(body['recentOpType']),
    authid: asString(body['authid']),
    raw: body,
  };
}

function parseCardlessInput(value: unknown): CardlessInput {
  const raw = asRecord(value);
  const settings = asRecord(raw['settings']);
  return {
    id: asString(raw['id']) ?? '',
    label: asString(raw['label']) ?? '',
    type: asString(raw['type']) ?? '',
    description: asString(raw['description']),
    required: settingFlag(raw['required']) || settingFlag(settings['required']),
    readonly: settingFlag(raw['readOnly']) || settingFlag(settings['readonly']),
    value: asString(raw['value']) ?? asString(settings['value']),
    stereotype: asString(raw['stereotype']),
    pattern: asString(raw['pattern']),
    future: settingFlag(raw['future']),
    choices: asArray(raw['selectionList']).map((item) => {
      const entry = asRecord(item);
      return { value: asString(entry['value']) ?? '', label: asString(entry['label']) ?? '' };
    }),
    raw,
  };
}

export function parseCardlessForm(body: Record<string, unknown>): CardlessForm {
  const inputs = asArray(body['inputs']).map(parseCardlessInput);
  const select = inputs.find((input) => input.type === 'select' && input.choices.length > 0);
  return { inputs, types: select?.choices ?? [], raw: body };
}

export function parseCardlessCode(raw: Record<string, unknown>): CardlessCode {
  return {
    id: asString(raw['id']) ?? '',
    code: asString(raw['code']),
    amount: asNumber(raw['amount']),
    currency: asString(raw['currency']),
    status: asString(raw['status']),
    details: parseDynamicDetails(raw['additionalData']),
    raw,
  };
}

export function parseCardlessCodes(body: Record<string, unknown>): CardlessCode[] {
  return asArray(body['operations'])
    .map((item) => asRecord(item))
    .filter((raw) => Object.keys(raw).length > 0)
    .map(parseCardlessCode);
}

export const DEFAULT_CARDLESS_DATE_PATTERN = "yyyy-MM-dd'T'HH:mm:ss.SSSXXX";

const ALGERIA_OFFSET_MS = 60 * 60 * 1000;

export function formatDatePattern(date: Date, pattern: string): string {
  const local = new Date(date.getTime() + ALGERIA_OFFSET_MS);
  const pad = (value: number, width: number) => String(value).padStart(width, '0');
  let out = '';
  let i = 0;
  while (i < pattern.length) {
    const letter = pattern.charAt(i);
    if (letter === "'") {
      const end = pattern.indexOf("'", i + 1);
      if (end < 0) {
        out += pattern.slice(i + 1);
        break;
      }
      out += end === i + 1 ? "'" : pattern.slice(i + 1, end);
      i = end + 1;
      continue;
    }
    let j = i;
    while (j < pattern.length && pattern.charAt(j) === letter) j += 1;
    const width = j - i;
    switch (letter) {
      case 'y':
        out +=
          width === 2 ? pad(local.getUTCFullYear() % 100, 2) : pad(local.getUTCFullYear(), width);
        break;
      case 'M':
        out += pad(local.getUTCMonth() + 1, width);
        break;
      case 'd':
        out += pad(local.getUTCDate(), width);
        break;
      case 'H':
        out += pad(local.getUTCHours(), width);
        break;
      case 'm':
        out += pad(local.getUTCMinutes(), width);
        break;
      case 's':
        out += pad(local.getUTCSeconds(), width);
        break;
      case 'S':
        out += pad(local.getUTCMilliseconds(), width);
        break;
      case 'X':
        out += width === 1 ? '+01' : width === 2 ? '+0100' : '+01:00';
        break;
      case 'Z':
        out += width >= 5 ? '+01:00' : '+0100';
        break;
      default:
        out += pattern.slice(i, j);
    }
    i = j;
  }
  return out;
}
