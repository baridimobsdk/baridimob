from __future__ import annotations

from typing import Any

from .result import result_code_of, result_name


class BaridiMobError(Exception):
    pass


def _describe(raw: dict[str, Any]) -> str | None:
    """What BaridiMob said about a refusal, in the session's language."""
    value = raw.get("description")
    if not isinstance(value, str):
        return None
    text = value.strip()
    return text or None


class ApiResultError(BaridiMobError):
    def __init__(self, result_code: int, raw: dict[str, Any], message: str | None = None):
        super().__init__(
            message
            or _describe(raw)
            or f"BaridiMob result {result_code} ({result_name(result_code)})"
        )
        self.result_code = result_code
        self.result_name = result_name(result_code)
        self.raw = raw
        self.description = _describe(raw)


class DeviceConfirmationRequiredError(ApiResultError):
    def __init__(self, result_code: int, raw: dict[str, Any], devid: str | None):
        super().__init__(
            result_code,
            raw,
            "Device is not trusted: request an OTP and confirm the device",
        )
        self.devid = devid


class InvalidOtpError(ApiResultError):
    def __init__(self, result_code: int, raw: dict[str, Any]):
        super().__init__(result_code, raw, "Invalid confirmation code")


class ExpiredOtpError(ApiResultError):
    def __init__(self, result_code: int, raw: dict[str, Any]):
        super().__init__(result_code, raw, "Confirmation code expired")


class TooManyAttemptsError(ApiResultError):
    def __init__(self, result_code: int, raw: dict[str, Any]):
        super().__init__(result_code, raw, "Too many attempts")


class SessionExpiredError(BaridiMobError):
    def __init__(self, message: str = "Session expired and could not be restored: call login() again"):
        super().__init__(message)


class InvalidCredentialsError(ApiResultError):
    def __init__(self, result_code: int, raw: dict[str, Any]):
        super().__init__(result_code, raw, "Invalid login or password")


class AccountLockedError(ApiResultError):
    def __init__(self, result_code: int, raw: dict[str, Any]):
        super().__init__(result_code, raw, "Account is locked or blocked")


class PasswordExpiredError(ApiResultError):
    def __init__(self, result_code: int, raw: dict[str, Any]):
        super().__init__(result_code, raw, "Password expired")


class RegistrationRequiredError(ApiResultError):
    def __init__(self, result_code: int, raw: dict[str, Any]):
        super().__init__(result_code, raw, "Registration update required")


class TermsRequiredError(ApiResultError):
    def __init__(self, result_code: int, raw: dict[str, Any]):
        super().__init__(result_code, raw, "Terms of use must be accepted")


class HashedRetryError(ApiResultError):
    def __init__(self, result_code: int, raw: dict[str, Any]):
        super().__init__(result_code, raw, "Server requested a hashed login retry")


class InvalidSignatureError(ApiResultError):
    def __init__(self, result_code: int, raw: dict[str, Any]):
        super().__init__(result_code, raw, "Request signature rejected by the server")


class DeviceFlowError(BaridiMobError):
    pass


class ServerError(ApiResultError):
    def __init__(self, result_code: int, raw: dict[str, Any], message: str | None = None):
        super().__init__(result_code, raw, message or _describe(raw) or "BaridiMob server error")


class NetworkError(BaridiMobError):
    pass


class TimeoutError(BaridiMobError):
    pass


def error_for_result(result_code: int, raw: dict[str, Any], devid: str | None) -> BaridiMobError:
    if result_code in (101, 102):
        return SessionExpiredError()
    if result_code in (103, 104, 128, 136):
        return AccountLockedError(result_code, raw)
    if result_code == 105:
        return DeviceFlowError("Device ID is missing")
    if result_code in (106, 107):
        return DeviceConfirmationRequiredError(result_code, raw, devid)
    if result_code == 109:
        return InvalidOtpError(result_code, raw)
    if result_code == 110:
        return ExpiredOtpError(result_code, raw)
    if result_code in (111, 119, 131):
        return TooManyAttemptsError(result_code, raw)
    if result_code in (120, 121, 122):
        return InvalidCredentialsError(result_code, raw)
    if result_code == 125:
        return PasswordExpiredError(result_code, raw)
    if result_code == 134:
        return RegistrationRequiredError(result_code, raw)
    if result_code == 143:
        return HashedRetryError(result_code, raw)
    if result_code == 148:
        return TermsRequiredError(result_code, raw)
    if result_code in (150, 151):
        return InvalidSignatureError(result_code, raw)
    if result_code == 2:
        return ServerError(result_code, raw)
    return ApiResultError(result_code, raw)


def raise_for_result(body: dict[str, Any], devid: str | None) -> None:
    code = result_code_of(body)
    if code == 0:
        return
    if code is None:
        raise ServerError(-1, body, "Response is missing numeric result code")
    raise error_for_result(code, body, devid)
