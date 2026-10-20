const RESULT_NAMES: Record<number, string> = {
  0: 'SUCCESS',
  1: 'BAD_REQUEST',
  2: 'INTERNAL_SERVER_ERROR',
  3: 'UNSUPPORTED_OPERATION',
  4: 'INVALID_FLOW_STATE',
  5: 'INCOMPATIBLE_REVISION',
  404: 'RESOURCE_NOT_FOUND',
  1404: 'REQUEST_CANCELED',
  101: 'INVALID_ACCESS_TOKEN',
  102: 'SESSION_CLOSED',
  103: 'INVALID_LOGIN_PASS',
  104: 'ACCOUNT_LOCKED',
  105: 'DEVICE_ID_REQUIRED',
  106: 'ILLEGAL_DEVICE',
  107: 'DEVICE_CONFIRM_REQUIRED',
  108: 'TRANSACTION_CONFIRM_REQUIRED',
  109: 'INVALID_CONFIRMATION_CODE',
  110: 'EXPIRED_CONFIRMATION_CODE',
  111: 'TOO_MANY_CONFIRMATION_ATTEMPTS',
  112: 'PARAMETERS_COMPARISON_FAILED',
  113: 'USER_ALREADY_JOINED',
  114: 'PASSWORD_POLICY_VIOLATION',
  115: 'TRANSACTION_DECLINED',
  116: 'OPERATION_ISNOT_ALLOWED',
  118: 'INCORRECT_SECURE_CODE',
  119: 'TOO_MANY_CVV_ATTEMPTS',
  120: 'INVALID_LOGIN',
  121: 'INVALID_PASSWORD',
  122: 'LOGIN_POLICY_VIOLATION',
  123: 'INVALID_PARAMETERS',
  124: 'FLOW_BREAKING_BY_SERVER',
  125: 'EXPIRED_PASSWORD',
  126: 'CUSTOM_PAYMENT_EXCEPTION',
  127: 'FINANCIAL_OPERATIONS_DISABLED',
  128: 'MAX_PASSWORD_ATTEMPT',
  129: 'SECURE3D_AUTHENTICATION_REQUIRED',
  131: 'TOO_MANY_ACTIVATION_ATTEMPTS',
  133: 'LOGIN_DENIED_RESTRICTIONS',
  134: 'REGISTRATION_UPDATE_REQUIRED',
  135: 'CLIENT_IS_DELETED',
  136: 'MAX_PIN_ATTEMPT_COUNT_EXCEEDED',
  137: 'PASSWORD_MUST_BE_INVALIDATE_BY_OPERATOR',
  138: 'BIOMETRIC_UNKNOWN_USER',
  142: 'AUTOMATIC_PASSWORD_RESTORE_ERROR',
  143: 'HASHED_PASSWORD_ERROR',
  145: 'REQUIRE_UPDATE_AUTHENTICATION_DATA',
  146: 'LOGIN_COUNTRY_RESTRICTION',
  148: 'CLIENT_NOT_ACCEPTED_TERMS_OF_USE',
  150: 'MESSAGE_SIGNATURE_REQUIRED',
  151: 'INVALID_MESSAGE_SIGNATURE',
  201: 'INCORRECT_ACCOUNT',
  202: 'CARD_ALREADY_ADDED',
  203: 'INCORRECT_TEMPLATE',
  204: 'INCORRECT_LIMIT',
  205: 'INCORRECT_TRANSACTION_REFERENCE',
  209: 'INVALID_CARD',
  212: 'QR_PAYMENT_PROVIDER_NOT_FOUND',
  301: 'UNKNOWN_PAYMENT_CATEGORY',
  302: 'UNKNOWN_PAYMENT_PROVIDER',
  303: 'INVALID_PARAMETERS',
  307: 'INVALID_TIMEZONE',
  309: 'ERROR_CANCEL_OPERATION',
  [-101]: 'CANNOT_CHECK_SESSION',
};

export function resultNameFor(code: number): string {
  return RESULT_NAMES[code] ?? `RESULT_${code}`;
}

export function asRecord(value: unknown): Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}

export function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

export function asString(value: unknown): string | null {
  if (typeof value === 'string') return value;
  if (typeof value === 'number') return String(value);
  return null;
}

export function asNumber(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string' && value.trim() !== '') {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

export function resultCodeOf(body: Record<string, unknown>): number | null {
  return asNumber(body['result']);
}
