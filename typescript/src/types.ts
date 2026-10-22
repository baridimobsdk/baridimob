export type Locale = 'ar' | 'fr' | 'en';

export interface StoredSession {
  version: 1;
  devid: string;
  privateKeyPem: string;
  devkey: string;
  devkeyAlgorithm: string;
  cookies: Record<string, string>;
  locale: Locale;
  account?: string;
}

export interface SessionStorage {
  load(): Promise<StoredSession | null>;
  save(session: StoredSession): Promise<void>;
  clear(): Promise<void>;
}

export interface BaridiMobConfig {
  baseUrl?: string;
  allowInsecure?: boolean;
  hashPassword?: (login: string, password: string) => string | Promise<string>;
  specRevision?: string;
  locale?: Locale;
  timeZone?: string;
  deviceName?: string;
  timeoutMs?: number;
  retries?: number;
  storage?: SessionStorage;
  fetchImpl?: typeof fetch;
  userAgent?: string;
}

export interface Credentials {
  login: string;
  password: string;
}

export type LoginResult =
  | { state: 'authenticated' }
  | { state: 'otp_required'; devid: string };

export interface Detail {
  id: string;
  label: string;
  value: string;
}

export interface Account {
  id: string;
  number: string;
  balance: number;
  currency: string;
  raw: Record<string, unknown>;
}

export interface Transaction {
  amount: number;
  currency: string;
  description: string;
  type: string;
  tid: string;
  timestamp: string;
  date: Date | null;
  fee: number | null;
  refNum: string | null;
  raw: Record<string, unknown>;
}

export interface HistoryQuery {
  account: string;
  from?: Date | string;
  to?: Date | string;
  page?: number;
}

export interface HistoryPage {
  page: number;
  transactions: Transaction[];
}

export interface Card {
  id: string;
  number: string;
  name: string;
  brand: string;
  status: number;
  expDate: string;
  type: number;
  category: string | null;
  balance: number | null;
  currency: string | null;
  embossedName: string | null;
  active: boolean;
  pinNotSet: boolean;
  linkedAccounts: string[];
  isDebitAllowed: boolean;
  raw: Record<string, unknown>;
}

export interface CardLimit {
  uid: string;
  name: string;
  description: string | null;
  type: number;
  amount: number | null;
  usedAmount: number | null;
  opCount: number | null;
  usedOpCount: number | null;
  currency: string | null;
  active: boolean;
  changeable: boolean;
  permanent: boolean;
  perTransaction: boolean;
  endTime: string | null;
  raw: Record<string, unknown>;
}

export type CardTransactionState = 'all' | 'hold' | 'processed';

export interface CardHistoryQuery {
  card: string;
  from?: Date | string;
  to?: Date | string;
  page?: number;
  state?: CardTransactionState;
}

export interface CardsModule {
  list(): Promise<Card[]>;
  get(id: string): Promise<Card>;
  limits(cardId: string): Promise<CardLimit[]>;
  history(query: CardHistoryQuery): Promise<HistoryPage>;
  allHistory(query: Omit<CardHistoryQuery, 'page'>): Promise<Transaction[]>;
  iterHistory(query: Omit<CardHistoryQuery, 'page'>): AsyncGenerator<Transaction, void, void>;
}

export interface TransactionQuery {
  account: string;
  from?: Date | string;
  to?: Date | string;
}

export interface FindTransactionParams extends TransactionQuery {
  refNum: string;
}

export interface VerifyPaymentParams {
  refNum: string;
  amount?: number;
  account?: string;
  from?: Date | string;
  to?: Date | string;
}

export type VerifyPaymentReason =
  | 'ok'
  | 'not_found'
  | 'amount_mismatch'
  | 'not_incoming'
  | 'duplicate';

export interface VerifyPaymentResult {
  verified: boolean;
  reason: VerifyPaymentReason;
  transaction: Transaction | null;
  matches: Transaction[];
}

export interface AuthModule {
  login(credentials: Credentials): Promise<LoginResult>;
  requestDeviceOtp(): Promise<void>;
  confirmDevice(otp: string): Promise<LoginResult>;
  logout(): Promise<void>;
  currentDeviceId(): string | null;
}

export interface AccountsModule {
  list(): Promise<Account[]>;
  get(id: string): Promise<Account>;
  balance(): Promise<number>;
  transactions(query: HistoryQuery): Promise<HistoryPage>;
  allTransactions(query: TransactionQuery): Promise<Transaction[]>;
  iterTransactions(query: TransactionQuery): AsyncGenerator<Transaction, void, void>;
  findTransaction(params: FindTransactionParams): Promise<Transaction | null>;
}

export interface PaymentsModule {
  verifyPayment(params: VerifyPaymentParams): Promise<VerifyPaymentResult>;
  categories(): Promise<PaymentCategory[]>;
  providers(cid: string | number): Promise<PaymentProvider[]>;
  check(params: PaymentCheckParams): Promise<PaymentCheckResult>;
  requestOtp(transRef: string): Promise<void>;
  exec(params: PaymentExecParams): Promise<PaymentExecResult>;
  dynamic: DynamicPaymentsModule;
}

export interface Profile {
  actorId: string;
  clientName: string | null;
  lastLogin: string | null;
  financialOperationsDisabled: boolean;
  raw: Record<string, unknown>;
}

export interface ProfileModule {
  get(): Promise<Profile>;
}

export interface RecentOperation {
  uid: string;
  type: string;
  pid: string;
  amount: number;
  currency: string;
  timestamp: string;
  date: Date | null;
  providerName: string | null;
  sourceType: number | null;
  sourceId: string | null;
  status: number | null;
  raw: Record<string, unknown>;
}

export interface ReceiptsModule {
  list(): Promise<RecentOperation[]>;
  download(uid: string): Promise<Uint8Array>;
}

export interface ProviderParam {
  id: string;
  name: string;
  type: string;
  pattern: string | null;
  min: number | null;
  max: number | null;
  value: string | null;
  description: string | null;
  hasExternalHandler: boolean;
}

export interface PaymentCategory {
  cid: string;
  name: string;
  image: string | null;
  raw: Record<string, unknown>;
}

export interface PaymentProvider {
  pid: string;
  name: string;
  mappedId: string | null;
  cid: string | null;
  scenario: string | null;
  categoryName: string | null;
  params: ProviderParam[];
  raw: Record<string, unknown>;
}

export interface PaymentSource {
  type: 'card' | 'account';
  id: string;
}

export interface PaymentCheckParams {
  pid: string;
  amount: number;
  currency?: string;
  source: PaymentSource;
  params?: Record<string, string>;
}

export interface PaymentCheckResult {
  transRef: string;
  confirmationType: string | null;
  raw: Record<string, unknown>;
}

export interface PaymentExecParams extends PaymentCheckParams {
  transRef: string;
  otp: string;
}

export interface PaymentExecResult {
  raw: Record<string, unknown>;
}

export interface DynamicOperationRef {
  id: string;
  label: string;
}

export interface DynamicGroup {
  id: string;
  label: string;
  type: string | null;
  image: string | null;
  operations: DynamicOperationRef[];
  raw: Record<string, unknown>;
}

export interface DynamicOperationInfo {
  id: string;
  label: string;
  firstStep: DynamicOperationRef | null;
  saveTemplateEnabled: boolean;
  raw: Record<string, unknown>;
}

export interface DynamicChoice {
  value: string;
  label: string;
}

export interface DynamicStepInput {
  id: string;
  label: string;
  type: string;
  required: boolean;
  settings: unknown;
  choices: DynamicChoice[];
  accessAttributes: string[];
  raw: Record<string, unknown>;
}

export interface DynamicStep {
  id: string;
  label: string;
  inputs: DynamicStepInput[];
  raw: Record<string, unknown>;
}

export interface DynamicCheckResult {
  transRef: string;
  confirmationType: string | null;
  fee: number | null;
  currency: string | null;
  planDate: string | null;
  raw: Record<string, unknown>;
}

export interface DynamicExecResult {
  transRef: string | null;
  recentOpId: string | null;
  recentOpType: string | null;
  authid: string | null;
  confirmationType: string | null;
  raw: Record<string, unknown>;
}

export interface DynamicCompleteResult {
  recentOpId: string | null;
  recentOpType: string | null;
  authid: string | null;
  raw: Record<string, unknown>;
}

export interface DynamicPaymentsModule {
  groups(): Promise<DynamicGroup[]>;
  operation(id: string | number): Promise<DynamicOperationInfo>;
  step(
    operationId: string | number,
    params?: Record<string, unknown>,
    currentStepKey?: string,
  ): Promise<DynamicStep>;
  check(
    operationId: string | number,
    params?: Record<string, string>,
  ): Promise<DynamicCheckResult>;
  requestOtp(transRef: string): Promise<void>;
  exec(params: DynamicExecParams): Promise<DynamicExecResult>;
  complete(params: DynamicCompleteParams): Promise<DynamicCompleteResult>;
}

export interface DynamicExecParams {
  operationId: string | number;
  transRef: string;
  otp: string;
  params?: Record<string, string>;
}

export interface DynamicCompleteParams {
  operationId: string | number;
  transRef: string;
  confirmVal: string;
}

export interface TransferStrategiesParams {
  amount?: number;
  currency?: string;
  actionType?: number;
  sourceType?: number;
  targetType?: number;
  operationSubtype?: number;
}

export interface TransferArmParams {
  amount: number;
  currency?: string;
  sourceId: string;
  targetId: string;
  targetType?: number;
  sourceType?: number;
}

export interface TransferArmResult {
  transRef: string;
  confirmationType: string | null;
  raw: Record<string, unknown>;
}

export interface TransferExecParams {
  amount: number;
  sourceId: string;
  targetId: string;
  transRef: string;
  otp: string;
  currency?: string;
  targetType?: number;
  sourceType?: number;
  operationSubtype?: number;
}

export interface TransferExecResult {
  raw: Record<string, unknown>;
}

export interface TransferPending {
  transRef: string;
  amount: number;
  sourceId: string;
  targetId: string;
  confirmationType: string | null;
  confirm(otp: string): Promise<TransferExecResult>;
}

export interface TransfersModule {
  strategies(params?: TransferStrategiesParams): Promise<string[]>;
  arm(params: TransferArmParams): Promise<TransferArmResult>;
  requestOtp(transRef: string): Promise<void>;
  exec(params: TransferExecParams): Promise<TransferExecResult>;
  send(params: TransferArmParams): Promise<TransferPending>;
}

export interface BaridiMobClient {
  auth: AuthModule;
  accounts: AccountsModule;
  cards: CardsModule;
  payments: PaymentsModule;
  transfers: TransfersModule;
  receipts: ReceiptsModule;
  profile: ProfileModule;
  exportSession(): Promise<StoredSession | null>;
  importSession(session: StoredSession): Promise<void>;
}
