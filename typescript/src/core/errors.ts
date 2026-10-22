import { resultCodeOf, resultNameFor } from './result.js';

export class BaridiMobError extends Error {
  constructor(message: string, options?: ErrorOptions) {
    super(message, options);
    this.name = new.target.name;
  }
}

// What BaridiMob said about a refusal, in the session's language.
function describe(raw: Record<string, unknown>): string | null {
  const value = raw['description'];
  if (typeof value !== 'string') return null;
  const text = value.trim();
  return text === '' ? null : text;
}

export class ApiResultError extends BaridiMobError {
  readonly resultCode: number;
  readonly resultName: string;
  readonly raw: Record<string, unknown>;
  readonly description: string | null;

  constructor(resultCode: number, raw: Record<string, unknown>, message?: string) {
    super(
      message ?? describe(raw) ?? `BaridiMob result ${resultCode} (${resultNameFor(resultCode)})`,
    );
    this.resultCode = resultCode;
    this.resultName = resultNameFor(resultCode);
    this.raw = raw;
    this.description = describe(raw);
  }
}

export class DeviceConfirmationRequiredError extends ApiResultError {
  readonly devid: string | null;

  constructor(resultCode: number, raw: Record<string, unknown>, devid: string | null) {
    super(resultCode, raw, 'Device is not trusted: request an OTP and confirm the device');
    this.devid = devid;
  }
}

export class InvalidOtpError extends ApiResultError {
  constructor(resultCode: number, raw: Record<string, unknown>) {
    super(resultCode, raw, 'Invalid confirmation code');
  }
}

export class ExpiredOtpError extends ApiResultError {
  constructor(resultCode: number, raw: Record<string, unknown>) {
    super(resultCode, raw, 'Confirmation code expired');
  }
}

export class TooManyAttemptsError extends ApiResultError {
  constructor(resultCode: number, raw: Record<string, unknown>) {
    super(resultCode, raw, 'Too many attempts');
  }
}

export class SessionExpiredError extends BaridiMobError {
  constructor(message = 'Session expired and could not be restored: call login() again') {
    super(message);
  }
}

export class InvalidCredentialsError extends ApiResultError {
  constructor(resultCode: number, raw: Record<string, unknown>) {
    super(resultCode, raw, 'Invalid login or password');
  }
}

export class AccountLockedError extends ApiResultError {
  constructor(resultCode: number, raw: Record<string, unknown>) {
    super(resultCode, raw, 'Account is locked or blocked');
  }
}

export class PasswordExpiredError extends ApiResultError {
  constructor(resultCode: number, raw: Record<string, unknown>) {
    super(resultCode, raw, 'Password expired');
  }
}

export class RegistrationRequiredError extends ApiResultError {
  constructor(resultCode: number, raw: Record<string, unknown>) {
    super(resultCode, raw, 'Registration update required');
  }
}

export class TermsRequiredError extends ApiResultError {
  constructor(resultCode: number, raw: Record<string, unknown>) {
    super(resultCode, raw, 'Terms of use must be accepted');
  }
}

export class HashedRetryError extends ApiResultError {
  constructor(resultCode: number, raw: Record<string, unknown>) {
    super(resultCode, raw, 'Server requested a hashed login retry');
  }
}

export class InvalidSignatureError extends ApiResultError {
  constructor(resultCode: number, raw: Record<string, unknown>) {
    super(resultCode, raw, 'Request signature rejected by the server');
  }
}

export class DeviceFlowError extends BaridiMobError {}

export class ServerError extends ApiResultError {
  constructor(resultCode: number, raw: Record<string, unknown>, message?: string) {
    super(resultCode, raw, message ?? describe(raw) ?? 'BaridiMob server error');
  }
}

export class NetworkError extends BaridiMobError {}

export class TimeoutError extends BaridiMobError {}

export interface RequestContext {
  endpoint: string;
  devid?: string | null;
}

export function errorForResult(
  code: number,
  raw: Record<string, unknown>,
  context: RequestContext,
): BaridiMobError {
  switch (code) {
    case 101:
    case 102:
      return new SessionExpiredError();
    case 103:
    case 104:
    case 128:
    case 136:
      return new AccountLockedError(code, raw);
    case 105:
      return new DeviceFlowError('Device ID is missing');
    case 106:
    case 107:
      return new DeviceConfirmationRequiredError(code, raw, context.devid ?? null);
    case 109:
      return new InvalidOtpError(code, raw);
    case 110:
      return new ExpiredOtpError(code, raw);
    case 111:
    case 119:
    case 131:
      return new TooManyAttemptsError(code, raw);
    case 120:
    case 121:
    case 122:
      return new InvalidCredentialsError(code, raw);
    case 125:
      return new PasswordExpiredError(code, raw);
    case 134:
      return new RegistrationRequiredError(code, raw);
    case 143:
      return new HashedRetryError(code, raw);
    case 148:
      return new TermsRequiredError(code, raw);
    case 150:
    case 151:
      return new InvalidSignatureError(code, raw);
    case 2:
      return new ServerError(code, raw);
    default:
      return new ApiResultError(code, raw);
  }
}

export function raiseForResult(body: Record<string, unknown>, context: RequestContext): void {
  const code = resultCodeOf(body);
  if (code === 0) return;
  if (code === null) {
    throw new ServerError(-1, body, 'Response is missing numeric result code');
  }
  throw errorForResult(code, body, context);
}
