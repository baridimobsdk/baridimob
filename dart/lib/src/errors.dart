import 'result.dart';

/// Base class of every error thrown by this SDK.
class BaridiMobError implements Exception {
  /// Creates an error with a human-readable [message].
  BaridiMobError(this.message, {this.cause});

  /// Human-readable description of the problem.
  final String message;

  /// The underlying error, when this one wraps another.
  final Object? cause;

  /// Name of the error type, stable across platforms and obfuscation.
  String get name => 'BaridiMobError';

  @override
  String toString() => '$name: $message';
}

/// The server answered with a non-zero result code.
class ApiResultError extends BaridiMobError {
  /// Creates an error for [resultCode] with the raw server response.
  ApiResultError(this.resultCode, this.raw, [String? message])
      : resultName = resultNameFor(resultCode),
        super(message ??
            'BaridiMob result $resultCode (${resultNameFor(resultCode)})');

  /// Numeric result code returned by the server.
  final int resultCode;

  /// Symbolic name of [resultCode], for example `INVALID_PASSWORD`.
  final String resultName;

  /// Raw server response.
  final Map<String, Object?> raw;

  @override
  String get name => 'ApiResultError';
}

/// This device is not trusted yet: request an OTP and confirm the device.
class DeviceConfirmationRequiredError extends ApiResultError {
  /// Creates the error for the device [devid].
  DeviceConfirmationRequiredError(
      int resultCode, Map<String, Object?> raw, this.devid)
      : super(resultCode, raw,
            'Device is not trusted: request an OTP and confirm the device');

  /// Id of the device that needs confirmation.
  final String? devid;

  @override
  String get name => 'DeviceConfirmationRequiredError';
}

/// The SMS code is wrong.
class InvalidOtpError extends ApiResultError {
  /// Creates the error.
  InvalidOtpError(int resultCode, Map<String, Object?> raw)
      : super(resultCode, raw, 'Invalid confirmation code');

  @override
  String get name => 'InvalidOtpError';
}

/// The SMS code has expired.
class ExpiredOtpError extends ApiResultError {
  /// Creates the error.
  ExpiredOtpError(int resultCode, Map<String, Object?> raw)
      : super(resultCode, raw, 'Confirmation code expired');

  @override
  String get name => 'ExpiredOtpError';
}

/// Too many failed attempts.
class TooManyAttemptsError extends ApiResultError {
  /// Creates the error.
  TooManyAttemptsError(int resultCode, Map<String, Object?> raw)
      : super(resultCode, raw, 'Too many attempts');

  @override
  String get name => 'TooManyAttemptsError';
}

/// The session expired and no credentials are available to log in again.
class SessionExpiredError extends BaridiMobError {
  /// Creates the error.
  SessionExpiredError([
    super.message =
        'Session expired and could not be restored: call login() again',
  ]);

  @override
  String get name => 'SessionExpiredError';
}

/// Wrong login or password.
class InvalidCredentialsError extends ApiResultError {
  /// Creates the error.
  InvalidCredentialsError(int resultCode, Map<String, Object?> raw)
      : super(resultCode, raw, 'Invalid login or password');

  @override
  String get name => 'InvalidCredentialsError';
}

/// The account is locked or blocked.
class AccountLockedError extends ApiResultError {
  /// Creates the error.
  AccountLockedError(int resultCode, Map<String, Object?> raw)
      : super(resultCode, raw, 'Account is locked or blocked');

  @override
  String get name => 'AccountLockedError';
}

/// The password expired and must be changed in the official app.
class PasswordExpiredError extends ApiResultError {
  /// Creates the error.
  PasswordExpiredError(int resultCode, Map<String, Object?> raw)
      : super(resultCode, raw, 'Password expired');

  @override
  String get name => 'PasswordExpiredError';
}

/// The account registration must be updated in the official app.
class RegistrationRequiredError extends ApiResultError {
  /// Creates the error.
  RegistrationRequiredError(int resultCode, Map<String, Object?> raw)
      : super(resultCode, raw, 'Registration update required');

  @override
  String get name => 'RegistrationRequiredError';
}

/// The terms of use must be accepted in the official app.
class TermsRequiredError extends ApiResultError {
  /// Creates the error.
  TermsRequiredError(int resultCode, Map<String, Object?> raw)
      : super(resultCode, raw, 'Terms of use must be accepted');

  @override
  String get name => 'TermsRequiredError';
}

/// The server rejected the hashed login retry.
class HashedRetryError extends ApiResultError {
  /// Creates the error.
  HashedRetryError(int resultCode, Map<String, Object?> raw)
      : super(resultCode, raw, 'Server requested a hashed login retry');

  @override
  String get name => 'HashedRetryError';
}

/// The server rejected the request signature.
class InvalidSignatureError extends ApiResultError {
  /// Creates the error.
  InvalidSignatureError(int resultCode, Map<String, Object?> raw)
      : super(resultCode, raw, 'Request signature rejected by the server');

  @override
  String get name => 'InvalidSignatureError';
}

/// A step of the login or device flow was called in the wrong order.
class DeviceFlowError extends BaridiMobError {
  /// Creates the error.
  DeviceFlowError(super.message);

  @override
  String get name => 'DeviceFlowError';
}

/// The server failed or returned an invalid response.
class ServerError extends ApiResultError {
  /// Creates the error.
  ServerError(int resultCode, Map<String, Object?> raw, [String? message])
      : super(resultCode, raw, message ?? 'BaridiMob server error');

  @override
  String get name => 'ServerError';
}

/// The request could not reach the server.
class NetworkError extends BaridiMobError {
  /// Creates the error.
  NetworkError(super.message, {super.cause});

  @override
  String get name => 'NetworkError';
}

/// The server did not answer in time.
class TimeoutError extends BaridiMobError {
  /// Creates the error.
  TimeoutError(super.message);

  @override
  String get name => 'TimeoutError';
}

/// Maps a non-zero result [code] to the matching error type.
BaridiMobError errorForResult(int code, Map<String, Object?> raw,
    {String? devid}) {
  switch (code) {
    case 101:
    case 102:
      return SessionExpiredError();
    case 103:
    case 104:
    case 128:
    case 136:
      return AccountLockedError(code, raw);
    case 105:
      return DeviceFlowError('Device ID is missing');
    case 106:
    case 107:
      return DeviceConfirmationRequiredError(code, raw, devid);
    case 109:
      return InvalidOtpError(code, raw);
    case 110:
      return ExpiredOtpError(code, raw);
    case 111:
    case 119:
    case 131:
      return TooManyAttemptsError(code, raw);
    case 120:
    case 121:
    case 122:
      return InvalidCredentialsError(code, raw);
    case 125:
      return PasswordExpiredError(code, raw);
    case 134:
      return RegistrationRequiredError(code, raw);
    case 143:
      return HashedRetryError(code, raw);
    case 148:
      return TermsRequiredError(code, raw);
    case 150:
    case 151:
      return InvalidSignatureError(code, raw);
    case 2:
      return ServerError(code, raw);
    default:
      return ApiResultError(code, raw);
  }
}

/// Throws the matching error unless [body] reports success (`result: 0`).
void raiseForResult(Map<String, Object?> body, {String? devid}) {
  final code = resultCodeOf(body);
  if (code == 0) return;
  if (code == null) {
    throw ServerError(-1, body, 'Response is missing numeric result code');
  }
  throw errorForResult(code, body, devid: devid);
}
