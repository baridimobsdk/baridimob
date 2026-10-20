import { BaridiMobError, NetworkError, ServerError, TimeoutError } from './errors.js';

export const DEFAULT_BASE_URL = 'https://baridimob.poste.dz/mobilebank/service';
export const DEFAULT_SPEC_REVISION = '29200428';
export const DEFAULT_USER_AGENT =
  'Dalvik/2.1.0 (Linux; U; Android 9; V2229A Build/PQ3B.190801.12191611)';

const ACCEPT_LANGUAGE: Record<string, string> = {
  ar: 'ar-DZ',
  fr: 'fr-FR',
  en: 'en',
};

export interface TransportConfig {
  baseUrl: string;
  specRevision: string;
  locale: string;
  timeoutMs: number;
  retries: number;
  userAgent: string;
  fetchImpl: typeof fetch;
}

export interface SendOptions {
  method: 'GET' | 'POST';
  endpoint: string;
  query?: string;
  body?: string;
  contentType?: string;
  safe?: boolean;
  timeoutMs?: number;
  binary?: boolean;
}

export interface SendResult {
  status: number;
  data: unknown;
  bytes?: Uint8Array;
}

class RetryableHttpError extends Error {
  constructor(
    message: string,
    readonly status: number,
  ) {
    super(message);
    this.name = 'RetryableHttpError';
  }
}

function isAbortError(error: unknown): boolean {
  return error instanceof Error && error.name === 'AbortError';
}

export class HttpTransport {
  private readonly config: TransportConfig;
  private readonly cookies: Record<string, string> = {};

  constructor(config: TransportConfig) {
    this.config = config;
  }

  cookieHeader(): string {
    return Object.entries(this.cookies)
      .map(([name, value]) => `${name}=${value}`)
      .join('; ');
  }

  cookieSnapshot(): Record<string, string> {
    return { ...this.cookies };
  }

  restoreCookies(cookies: Record<string, string>): void {
    this.clearCookies();
    for (const [name, value] of Object.entries(cookies)) {
      if (name && typeof value === 'string') this.cookies[name] = value;
    }
  }

  clearCookies(): void {
    for (const name of Object.keys(this.cookies)) delete this.cookies[name];
  }

  async send(options: SendOptions): Promise<SendResult> {
    const safe = options.safe !== false;
    const attempts = safe ? Math.max(0, this.config.retries) + 1 : 1;
    let lastError: unknown;

    for (let attempt = 0; attempt < attempts; attempt += 1) {
      try {
        return await this.attempt(options);
      } catch (error) {
        lastError = error;
        if (!this.isRetryable(error) || attempt === attempts - 1) {
          throw this.toPublicError(error);
        }
      }
    }

    throw this.toPublicError(lastError);
  }

  private isRetryable(error: unknown): boolean {
    return (
      error instanceof RetryableHttpError ||
      error instanceof NetworkError ||
      error instanceof TimeoutError
    );
  }

  private toPublicError(error: unknown): Error {
    if (error instanceof BaridiMobError) return error;
    if (error instanceof RetryableHttpError) {
      return new ServerError(error.status, { httpStatus: error.status }, error.message);
    }
    return error instanceof Error ? error : new NetworkError('Request failed');
  }

  private async attempt(options: SendOptions): Promise<SendResult> {
    const url = `${this.config.baseUrl}/${options.endpoint}${options.query ? `?${options.query}` : ''}`;
    const headers: Record<string, string> = {
      accept: 'application/json, application/*+json',
      platform: 'android',
      'spec-revision': this.config.specRevision,
      'accept-language': ACCEPT_LANGUAGE[this.config.locale] ?? 'ar-DZ',
      'user-agent': this.config.userAgent,
    };
    if (options.body !== undefined) {
      headers['content-type'] = options.contentType ?? 'application/x-www-form-urlencoded';
    }
    const cookie = this.cookieHeader();
    if (cookie) headers['cookie'] = cookie;

    const controller = new AbortController();
    const timeoutMs = options.timeoutMs ?? this.config.timeoutMs;
    const timer = setTimeout(() => controller.abort(), timeoutMs);

    const init: RequestInit = {
      method: options.method,
      headers,
      signal: controller.signal,
      redirect: 'manual',
    };
    if (options.body !== undefined) init.body = options.body;

    let response: Response;
    try {
      response = await this.config.fetchImpl(url, init);
    } catch (error) {
      if (isAbortError(error)) throw new TimeoutError(`Request timed out after ${timeoutMs}ms`);
      throw new NetworkError('Network request failed', { cause: error });
    } finally {
      clearTimeout(timer);
    }

    this.absorbCookies(response);

    if (response.status >= 500 || response.status === 429) {
      throw new RetryableHttpError(`Server responded ${response.status}`, response.status);
    }

    const contentType = response.headers.get('content-type') ?? '';
    const buffer = new Uint8Array(await response.arrayBuffer());
    if (buffer.length === 0) return { status: response.status, data: {} };
    if (options.binary === true && !contentType.includes('json')) {
      return { status: response.status, data: null, bytes: buffer };
    }

    const text = new TextDecoder().decode(buffer);
    if (text.trim() === '') return { status: response.status, data: {} };

    try {
      return { status: response.status, data: JSON.parse(text) as unknown };
    } catch {
      throw new ServerError(-1, { body: text.slice(0, 500) }, 'Response is not valid JSON');
    }
  }

  private absorbCookies(response: Response): void {
    const withSetCookie = response.headers as Headers & { getSetCookie?: () => string[] };
    const raw =
      typeof withSetCookie.getSetCookie === 'function'
        ? withSetCookie.getSetCookie()
        : splitSetCookie(response.headers.get('set-cookie'));
    for (const entry of raw) {
      const pair = entry.split(';', 1)[0] ?? '';
      const index = pair.indexOf('=');
      if (index <= 0) continue;
      const name = pair.slice(0, index).trim();
      const value = pair.slice(index + 1).trim();
      if (name) this.cookies[name] = value;
    }
  }
}

function splitSetCookie(header: string | null): string[] {
  if (!header) return [];
  return header.split(/,(?=\s*[^;,=]+=)/g);
}
