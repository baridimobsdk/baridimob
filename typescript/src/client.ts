import {
  BaridiMobError,
  DeviceConfirmationRequiredError,
  DeviceFlowError,
  HashedRetryError,
  ServerError,
  SessionExpiredError,
  errorForResult,
  raiseForResult,
} from './core/errors.js';
import {
  DEFAULT_BASE_URL,
  DEFAULT_SPEC_REVISION,
  DEFAULT_USER_AGENT,
  HttpTransport,
} from './core/http.js';
import type { SendResult } from './core/http.js';
import { algorithmHash, generateDeviceKeys, sha256Hex } from './core/keys.js';
import {
  dayBounds,
  isWithinBounds,
  parseAccountResponse,
  parseAccounts,
  parseCardLimits,
  parseCardResponse,
  parseCards,
  parseDynamicCheck,
  parseDynamicComplete,
  parseDynamicExec,
  parseDynamicGroups,
  parseDynamicOperation,
  parseDynamicStep,
  parseHistory,
  parsePaymentCategories,
  parsePaymentProviders,
  parseProfile,
  parseRecentOperations,
  toDateParam,
} from './core/parse.js';
import { asArray, asRecord, asString, resultCodeOf } from './core/result.js';
import { signJsonBody, signParams } from './core/sign.js';
import { memoryStorage } from './storage/memory.js';
import type {
  Account,
  AccountsModule,
  AuthModule,
  BaridiMobClient,
  BaridiMobConfig,
  Card,
  CardHistoryQuery,
  CardLimit,
  CardsModule,
  Credentials,
  DynamicCompleteParams,
  DynamicExecParams,
  FindTransactionParams,
  HistoryQuery,
  Locale,
  LoginResult,
  PaymentCheckParams,
  PaymentExecParams,
  PaymentsModule,
  ProfileModule,
  ReceiptsModule,
  SessionStorage,
  StoredSession,
  Transaction,
  TransactionQuery,
  TransferArmParams,
  TransferExecParams,
  TransferPending,
  TransfersModule,
  VerifyPaymentParams,
  VerifyPaymentResult,
} from './types.js';

const FORM_CONTENT_TYPE = 'application/x-www-form-urlencoded';
const MAX_HISTORY_PAGES = 100;

const LOCALE_TAG: Record<Locale, string> = {
  ar: 'ar_DZ',
  fr: 'fr_FR',
  en: 'en',
};

const LOCAL_HOSTS = new Set(['localhost', '127.0.0.1', '[::1]']);

function resolveBaseUrl(config: BaridiMobConfig): string {
  const raw = config.baseUrl ?? DEFAULT_BASE_URL;
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    throw new BaridiMobError(`Invalid baseUrl: ${raw}`);
  }
  const normalized = `${url.origin}${url.pathname}`.replace(/\/+$/, '');
  if (url.protocol === 'https:') return normalized;
  if (url.protocol === 'http:' && (LOCAL_HOSTS.has(url.hostname) || config.allowInsecure === true)) {
    return normalized;
  }
  throw new BaridiMobError(
    'baseUrl must use https (http is allowed only for localhost or with allowInsecure: true)',
  );
}

export function createBaridiMob(config: BaridiMobConfig = {}): BaridiMobClient {
  const locale: Locale = config.locale ?? 'ar';
  const storage: SessionStorage = config.storage ?? memoryStorage();
  const devname = config.deviceName ?? 'BaridiMob SDK';
  const baseUrl = resolveBaseUrl(config);
  const transport = new HttpTransport({
    baseUrl,
    specRevision: config.specRevision ?? DEFAULT_SPEC_REVISION,
    locale,
    timeoutMs: config.timeoutMs ?? 30_000,
    retries: config.retries ?? 2,
    userAgent: config.userAgent ?? DEFAULT_USER_AGENT,
    fetchImpl: config.fetchImpl ?? fetch,
  });

  let session: StoredSession | null = null;
  let loaded = false;
  let credentials: Credentials | null = null;
  let reloginInFlight: Promise<LoginResult> | null = null;

  async function loadSession(): Promise<StoredSession | null> {
    if (!loaded) {
      session = await storage.load();
      if (session) {
        transport.restoreCookies(session.cookies);
      }
      loaded = true;
    }
    return session;
  }

  function requireSession(): StoredSession {
    if (!session) throw new DeviceFlowError('No device session: call login() first');
    return session;
  }

  async function persist(): Promise<void> {
    if (!session) return;
    session.cookies = transport.cookieSnapshot();
    await storage.save(session);
  }

  async function ensureDevice(): Promise<StoredSession> {
    const existing = await loadSession();
    if (existing) return existing;
    const keys = generateDeviceKeys();
    session = {
      version: 1,
      devid: keys.devid,
      privateKeyPem: keys.privateKeyPem,
      devkey: keys.devkey,
      devkeyAlgorithm: keys.devkeyAlgorithm,
      cookies: {},
      locale,
    };
    return session;
  }

  async function performLogin(input: Credentials): Promise<LoginResult> {
    const current = await ensureDevice();
    const previousCookies = transport.cookieSnapshot();
    transport.clearCookies();

    const base: Record<string, string> = {
      devid: current.devid,
      devkeyAlgorithmHash: algorithmHash(current.devkeyAlgorithm),
      name: input.login,
      lang: locale,
      locale: LOCALE_TAG[locale],
      timeZone: config.timeZone ?? 'GMT+01:00',
    };

    async function attempt(endpoint: string, pwd: string): Promise<Record<string, unknown>> {
      const params: Record<string, string> = {
        devid: base['devid'] ?? '',
        devkeyAlgorithmHash: base['devkeyAlgorithmHash'] ?? '',
        name: base['name'] ?? '',
        pwd,
        lang: base['lang'] ?? '',
        locale: base['locale'] ?? '',
        timeZone: base['timeZone'] ?? '',
      };
      let response: SendResult;
      try {
        response = await transport.send({
          method: 'POST',
          endpoint,
          body: signParams(params, current.privateKeyPem),
          contentType: FORM_CONTENT_TYPE,
        });
      } catch (error) {
        transport.restoreCookies(previousCookies);
        throw error;
      }
      return asRecord(response.data);
    }

    let parsed = await attempt('login', input.password);
    let code = resultCodeOf(parsed);

    if (code === 143) {
      const hashed = config.hashPassword
        ? await config.hashPassword(input.login, input.password)
        : sha256Hex(`${input.login}${input.password}`);
      parsed = await attempt('login/hash', hashed);
      code = resultCodeOf(parsed);
      if (code === 143) {
        transport.restoreCookies(previousCookies);
        throw new HashedRetryError(code, parsed);
      }
    }

    if (code === 0) {
      current.account = input.login;
      await persist();
      return { state: 'authenticated' };
    }
    if (code === 106 || code === 107) {
      current.account = input.login;
      await persist();
      return { state: 'otp_required', devid: current.devid };
    }
    transport.restoreCookies(previousCookies);
    if (code === null) {
      throw new ServerError(-1, parsed, 'Response is missing numeric result code');
    }
    throw errorForResult(code, parsed, { endpoint: 'login', devid: current.devid });
  }

  function performSharedRelogin(input: Credentials): Promise<LoginResult> {
    if (!reloginInFlight) {
      reloginInFlight = performLogin(input).finally(() => {
        reloginInFlight = null;
      });
    }
    return reloginInFlight;
  }

  async function login(input: Credentials): Promise<LoginResult> {
    await loadSession();
    if (session?.account && session.account !== input.login) {
      throw new BaridiMobError(
        'Stored session belongs to a different account: call logout() or use a separate storage',
      );
    }
    credentials = null;
    const result = await performLogin(input);
    credentials = input;
    return result;
  }

  async function requestDeviceOtp(): Promise<void> {
    await loadSession();
    const current = requireSession();
    const params = {
      devkey: current.devkey,
      devid: current.devid,
      devkeyAlgorithm: current.devkeyAlgorithm,
    };
    const response = await transport.send({
      method: 'POST',
      endpoint: 'deviceAttach',
      body: signParams(params, current.privateKeyPem),
      contentType: FORM_CONTENT_TYPE,
      safe: false,
    });
    raiseForResult(asRecord(response.data), { endpoint: 'deviceAttach', devid: current.devid });
    await persist();
  }

  async function confirmDevice(otp: string): Promise<LoginResult> {
    await loadSession();
    const current = requireSession();
    const params = {
      devcode: otp,
      devid: current.devid,
      devkeyAlgorithm: current.devkeyAlgorithm,
      devname,
    };
    const response = await transport.send({
      method: 'POST',
      endpoint: 'deviceConfirm',
      body: signParams(params, current.privateKeyPem),
      contentType: FORM_CONTENT_TYPE,
      safe: false,
    });
    raiseForResult(asRecord(response.data), { endpoint: 'deviceConfirm', devid: current.devid });
    await persist();

    if (!credentials) {
      throw new DeviceFlowError('Credentials are not in memory: call login() again after confirming');
    }
    return performLogin(credentials);
  }

  async function logout(): Promise<void> {
    await loadSession();
    if (session) {
      try {
        const query = signParams({}, session.privateKeyPem);
        await transport.send({ method: 'GET', endpoint: 'logout', query });
      } catch {}
    }
    await storage.clear();
    transport.clearCookies();
    session = null;
    loaded = true;
    credentials = null;
  }

  interface RequestSpec {
    method: 'GET' | 'POST';
    endpoint: string;
    params?: Record<string, string>;
    json?: Record<string, unknown>;
    safe?: boolean;
    binary?: boolean;
  }

  async function sendOnce(spec: RequestSpec): Promise<SendResult> {
    const current = requireSession();
    if (spec.method === 'GET') {
      return transport.send({
        method: 'GET',
        endpoint: spec.endpoint,
        query: signParams(spec.params ?? {}, current.privateKeyPem),
        safe: spec.safe ?? true,
        binary: spec.binary === true,
      });
    }
    if (spec.json) {
      return transport.send({
        method: 'POST',
        endpoint: spec.endpoint,
        body: signJsonBody(spec.json, current.privateKeyPem),
        contentType: 'application/json',
        safe: spec.safe ?? true,
      });
    }
    return transport.send({
      method: 'POST',
      endpoint: spec.endpoint,
      body: signParams(spec.params ?? {}, current.privateKeyPem),
      contentType: FORM_CONTENT_TYPE,
      safe: spec.safe ?? true,
    });
  }

  async function sendWithRelogin(spec: RequestSpec): Promise<SendResult> {
    await loadSession();
    const current = requireSession();
    let response = await sendOnce(spec);
    const code = response.bytes ? 0 : resultCodeOf(asRecord(response.data));
    if (code === 101 || code === 102) {
      if (!credentials) throw new SessionExpiredError();
      const relogin = await performSharedRelogin(credentials);
      if (relogin.state !== 'authenticated') {
        throw new DeviceConfirmationRequiredError(106, asRecord(response.data), current.devid);
      }
      response = await sendOnce(spec);
    }
    return response;
  }

  async function request(spec: RequestSpec): Promise<Record<string, unknown>> {
    const response = await sendWithRelogin(spec);
    const body = asRecord(response.data);
    raiseForResult(body, { endpoint: spec.endpoint, devid: session?.devid ?? null });
    await persist();
    return body;
  }

  async function requestBinary(spec: RequestSpec): Promise<Uint8Array> {
    const response = await sendWithRelogin(spec);
    if (response.bytes) {
      await persist();
      return response.bytes;
    }
    const body = asRecord(response.data);
    raiseForResult(body, { endpoint: spec.endpoint, devid: session?.devid ?? null });
    throw new ServerError(-1, body, 'Expected a binary response');
  }

  async function call(
    endpoint: string,
    params: Record<string, string> = {},
  ): Promise<Record<string, unknown>> {
    return request({ method: 'GET', endpoint, params });
  }

  async function fetchHistoryPage(
    account: string,
    from: Date | string | undefined,
    to: Date | string | undefined,
    page: number,
  ): Promise<Transaction[]> {
    const params: Record<string, string> = {
      account,
      page: String(page),
    };
    if (from !== undefined) params['startDate'] = toDateParam(from);
    if (to !== undefined) params['endDate'] = toDateParam(to);
    const body = await call('accountHistory', params);
    return parseHistory(body);
  }

  async function* iterateTransactions(
    query: TransactionQuery,
  ): AsyncGenerator<Transaction, void, void> {
    for (let page = 1; page <= MAX_HISTORY_PAGES; page += 1) {
      const items = await fetchHistoryPage(query.account, query.from, query.to, page);
      if (items.length === 0) return;
      for (const item of items) yield item;
    }
  }

  async function fetchCardHistoryPage(
    card: string,
    from: Date | string | undefined,
    to: Date | string | undefined,
    page: number,
    state: string | undefined,
  ): Promise<Transaction[]> {
    const params: Record<string, string> = { card, page: String(page) };
    if (from !== undefined) params['startDate'] = toDateParam(from);
    if (to !== undefined) params['endDate'] = toDateParam(to);
    if (state !== undefined) params['transactionState'] = state;
    return parseHistory(await call('cardHistory', params));
  }

  async function* iterateCardTransactions(
    query: Omit<CardHistoryQuery, 'page'>,
  ): AsyncGenerator<Transaction, void, void> {
    for (let page = 1; page <= MAX_HISTORY_PAGES; page += 1) {
      const items = await fetchCardHistoryPage(
        query.card,
        query.from,
        query.to,
        page,
        query.state,
      );
      if (items.length === 0) return;
      for (const item of items) yield item;
    }
  }

  async function collectMatches(
    query: TransactionQuery,
    refNum: string,
    bounds: { start: number; end: number },
  ): Promise<Transaction[]> {
    const matches: Transaction[] = [];
    for await (const transaction of iterateTransactions(query)) {
      if (transaction.refNum !== refNum) continue;
      if (!isWithinBounds(transaction, bounds.start, bounds.end)) continue;
      matches.push(transaction);
    }
    return matches;
  }

  const auth: AuthModule = {
    login,
    requestDeviceOtp,
    confirmDevice,
    logout,
    currentDeviceId: () => session?.devid ?? null,
  };

  const accounts: AccountsModule = {
    async list(): Promise<Account[]> {
      return parseAccounts(await call('accounts'));
    },
    async get(id: string): Promise<Account> {
      return parseAccountResponse(await call('account', { id }));
    },
    async balance(): Promise<number> {
      const [first] = await parseAccounts(await call('accounts'));
      if (!first) throw new DeviceFlowError('No account available');
      return first.balance;
    },
    async transactions(query: HistoryQuery) {
      const page = query.page ?? 1;
      const transactions = await fetchHistoryPage(query.account, query.from, query.to, page);
      return { page, transactions };
    },
    async allTransactions(query: TransactionQuery): Promise<Transaction[]> {
      const collected: Transaction[] = [];
      for await (const transaction of iterateTransactions(query)) collected.push(transaction);
      return collected;
    },
    iterTransactions: iterateTransactions,
    async findTransaction(params: FindTransactionParams): Promise<Transaction | null> {
      const bounds = dayBounds(params.from, params.to);
      for await (const transaction of iterateTransactions(params)) {
        if (transaction.refNum !== params.refNum) continue;
        if (!isWithinBounds(transaction, bounds.start, bounds.end)) continue;
        return transaction;
      }
      return null;
    },
  };

  const cards: CardsModule = {
    async list(): Promise<Card[]> {
      return parseCards(await call('cards', { category: 'REGULAR' }));
    },

    async get(id: string): Promise<Card> {
      return parseCardResponse(await call('card', { id }));
    },

    async limits(cardId: string): Promise<CardLimit[]> {
      return parseCardLimits(
        await call('cardLimits', {
          card: cardId,
          language: locale,
          locale: LOCALE_TAG[locale],
        }),
      );
    },

    async history(query: CardHistoryQuery) {
      const page = query.page ?? 1;
      return {
        page,
        transactions: await fetchCardHistoryPage(
          query.card,
          query.from,
          query.to,
          page,
          query.state,
        ),
      };
    },

    async allHistory(query: Omit<CardHistoryQuery, 'page'>): Promise<Transaction[]> {
      const collected: Transaction[] = [];
      for await (const transaction of iterateCardTransactions(query)) collected.push(transaction);
      return collected;
    },

    iterHistory: iterateCardTransactions,
  };

  const payments: PaymentsModule = {
    async verifyPayment(params: VerifyPaymentParams): Promise<VerifyPaymentResult> {
      const to = params.to ?? new Date();
      const from = params.from ?? new Date(Date.now() - 30 * 86_400_000);
      const account = params.account ?? (await accounts.list())[0]?.number;
      if (!account) throw new DeviceFlowError('No account available');
      const bounds = dayBounds(from, to);
      const matches = await collectMatches({ account, from, to }, params.refNum, bounds);
      if (matches.length === 0) {
        return { verified: false, reason: 'not_found', transaction: null, matches };
      }
      const incoming = matches.filter((transaction) => transaction.amount > 0);
      if (incoming.length === 0) {
        return { verified: false, reason: 'not_incoming', transaction: null, matches };
      }
      if (incoming.length > 1) {
        return { verified: false, reason: 'duplicate', transaction: incoming[0] ?? null, matches };
      }
      const transaction = incoming[0] as Transaction;
      if (params.amount !== undefined && Math.abs(transaction.amount - params.amount) > 0.009) {
        return { verified: false, reason: 'amount_mismatch', transaction, matches };
      }
      return { verified: true, reason: 'ok', transaction, matches };
    },

    async categories() {
      return parsePaymentCategories(await request({ method: 'GET', endpoint: 'paymentCategories' }));
    },

    async providers(cid: string | number) {
      return parsePaymentProviders(
        await request({
          method: 'GET',
          endpoint: 'paymentProviders',
          params: { cid: String(cid) },
        }),
      );
    },

    async check(params: PaymentCheckParams) {
      const form: Record<string, string> = {
        pid: params.pid,
        amount: String(params.amount),
        currency: params.currency ?? 'DZD',
        sourceType: params.source.type === 'card' ? '1' : '2',
        sourceId: params.source.id,
      };
      for (const [key, value] of Object.entries(params.params ?? {})) {
        form[`param.${key}`] = value;
      }
      const body = await request({ method: 'POST', endpoint: 'paymentCheck', params: form });
      return {
        transRef: asString(body['transRef']) ?? '',
        confirmationType: asString(asRecord(body['confirmReq'])['type']),
        raw: body,
      };
    },

    async requestOtp(transRef: string) {
      await request({
        method: 'GET',
        endpoint: 'getOTPbySMS',
        params: { transRef },
        safe: false,
      });
    },

    async exec(params: PaymentExecParams) {
      const form: Record<string, string> = {
        pid: params.pid,
        amount: String(params.amount),
        currency: params.currency ?? 'DZD',
        sourceType: params.source.type === 'card' ? '1' : '2',
        sourceId: params.source.id,
        transRef: params.transRef,
        flags: '0',
        confirmVal: params.otp,
      };
      for (const [key, value] of Object.entries(params.params ?? {})) {
        form[`param.${key}`] = value;
      }
      const body = await request({
        method: 'POST',
        endpoint: 'paymentExec',
        params: form,
        safe: false,
      });
      return { raw: body };
    },

    dynamic: {
      async groups() {
        return parseDynamicGroups(await request({ method: 'GET', endpoint: 'dynamic/groups' }));
      },
      async operation(id: string | number) {
        return parseDynamicOperation(
          await request({
            method: 'GET',
            endpoint: 'dynamic/operation',
            params: { operationId: String(id) },
          }),
        );
      },
      async step(
        operationId: string | number,
        params: Record<string, unknown> = {},
        currentStepKey?: string,
      ) {
        return parseDynamicStep(
          await request({
            method: 'POST',
            endpoint: 'dynamic/operation/step',
            json: {
              operationId: String(operationId),
              ...(currentStepKey === undefined ? {} : { currentStepKey }),
              parameters: params,
            },
          }),
        );
      },

      async check(operationId: string | number, params: Record<string, string> = {}) {
        const form: Record<string, string> = { operationId: String(operationId) };
        for (const [key, value] of Object.entries(params)) form[`param.${key}`] = value;
        return parseDynamicCheck(
          await request({
            method: 'POST',
            endpoint: 'dynamic/operation/check',
            params: form,
          }),
        );
      },

      async requestOtp(transRef: string) {
        await request({
          method: 'GET',
          endpoint: 'getOTPbySMS',
          params: { transRef },
          safe: false,
        });
      },

      async exec(params: DynamicExecParams) {
        const form: Record<string, string> = {
          operationId: String(params.operationId),
          transRef: params.transRef,
          confirmVal: params.otp,
        };
        for (const [key, value] of Object.entries(params.params ?? {})) {
          form[`param.${key}`] = value;
        }
        return parseDynamicExec(
          await request({
            method: 'POST',
            endpoint: 'dynamic/operation/execute',
            params: form,
            safe: false,
          }),
        );
      },

      async complete(params: DynamicCompleteParams) {
        return parseDynamicComplete(
          await request({
            method: 'POST',
            endpoint: 'dynamic/operation/complete',
            params: {
              operationId: String(params.operationId),
              transRef: params.transRef,
              confirmVal: params.confirmVal,
            },
            safe: false,
          }),
        );
      },
    },
  };

  const transfers: TransfersModule = {
    async strategies(params = {}) {
      const query: Record<string, string> = {
        amount: String(params.amount ?? 100),
        currency: params.currency ?? 'DZD',
        actionType: String(params.actionType ?? 1),
        sourceType: String(params.sourceType ?? 2),
        targetType: String(params.targetType ?? 2),
        operationSubtype: String(params.operationSubtype ?? 0),
      };
      const body = await request({
        method: 'GET',
        endpoint: 'getConfirmationStrategies',
        params: query,
      });
      return asArray(body['confirmationStrategies'])
        .map((value) => asString(value))
        .filter((value): value is string => value !== null);
    },

    async arm(params: TransferArmParams) {
      const form: Record<string, string> = {
        amount: String(params.amount),
        currency: params.currency ?? 'DZD',
        sourceType: String(params.sourceType ?? 2),
        sourceId: params.sourceId,
        targetType: String(params.targetType ?? 2),
        targetId: params.targetId,
      };
      const body = await request({ method: 'POST', endpoint: 'transferCheck', params: form });
      return {
        transRef: asString(body['transRef']) ?? '',
        confirmationType: asString(asRecord(body['confirmReq'])['type']),
        raw: body,
      };
    },

    async requestOtp(transRef: string) {
      await request({
        method: 'GET',
        endpoint: 'getOTPbySMS',
        params: { transRef },
        safe: false,
      });
    },

    async exec(params: TransferExecParams) {
      const form: Record<string, string> = {
        amount: String(params.amount),
        currency: params.currency ?? 'DZD',
        sourceType: String(params.sourceType ?? 2),
        sourceId: params.sourceId,
        targetType: String(params.targetType ?? 2),
        targetId: params.targetId,
        transRef: params.transRef,
        flags: '0',
        confirmVal: params.otp,
        operationSubtype: String(params.operationSubtype ?? 0),
      };
      const body = await request({
        method: 'POST',
        endpoint: 'transferExec',
        params: form,
        safe: false,
      });
      return { raw: body };
    },

    send: sendTransfer,
  };

  async function sendTransfer(params: TransferArmParams): Promise<TransferPending> {
    const armed = await transfers.arm(params);
    await transfers.requestOtp(armed.transRef);
    return {
      transRef: armed.transRef,
      amount: params.amount,
      sourceId: params.sourceId,
      targetId: params.targetId,
      confirmationType: armed.confirmationType,
      confirm: (otp: string) => transfers.exec({ ...params, transRef: armed.transRef, otp }),
    };
  }

  const receipts: ReceiptsModule = {
    async list() {
      return parseRecentOperations(await request({ method: 'GET', endpoint: 'recentOperations' }));
    },
    async download(uid: string) {
      return requestBinary({
        method: 'GET',
        endpoint: 'download/receipt',
        params: { uid },
        binary: true,
      });
    },
    async find(transaction: Transaction) {
      const operations = await receipts.list();
      const byReference =
        transaction.refNum === null
          ? undefined
          : operations.find((operation) => operation.operationId === transaction.refNum);
      return (
        byReference ??
        operations.find(
          (operation) =>
            operation.timestamp !== '' &&
            operation.timestamp === transaction.timestamp &&
            Math.abs(Math.abs(operation.amount) - Math.abs(transaction.amount)) < 0.01,
        ) ??
        null
      );
    },
    async downloadFor(transaction: Transaction) {
      const operation = await receipts.find(transaction);
      return operation && operation.uid !== '' ? receipts.download(operation.uid) : null;
    },
  };

  const profile: ProfileModule = {
    async get() {
      return parseProfile(await request({ method: 'GET', endpoint: 'profile' }));
    },
  };

  function assertStoredSession(value: StoredSession): void {
    const valid =
      value !== null &&
      typeof value === 'object' &&
      value.version === 1 &&
      typeof value.devid === 'string' &&
      typeof value.privateKeyPem === 'string' &&
      typeof value.devkey === 'string' &&
      typeof value.devkeyAlgorithm === 'string' &&
      typeof value.cookies === 'object' &&
      value.cookies !== null;
    if (!valid) throw new BaridiMobError('Invalid stored session');
  }

  async function exportSession(): Promise<StoredSession | null> {
    await loadSession();
    if (!session) return null;
    session.cookies = transport.cookieSnapshot();
    return structuredClone(session);
  }

  async function importSession(stored: StoredSession): Promise<void> {
    assertStoredSession(stored);
    session = structuredClone(stored);
    loaded = true;
    credentials = null;
    transport.restoreCookies(stored.cookies);
    await storage.save(session);
  }

  return {
    auth,
    accounts,
    cards,
    payments,
    transfers,
    receipts,
    profile,
    exportSession,
    importSession,
  };
}
