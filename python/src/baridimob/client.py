from __future__ import annotations

import threading
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
from typing import Any, Callable, Iterator
from urllib.parse import urlparse

import httpx

from .errors import (
    BaridiMobError,
    DeviceConfirmationRequiredError,
    DeviceFlowError,
    HashedRetryError,
    ServerError,
    SessionExpiredError,
    error_for_result,
    raise_for_result,
)
from .http import (
    DEFAULT_BASE_URL,
    DEFAULT_SPEC_REVISION,
    DEFAULT_USER_AGENT,
    SendResult,
    Transport,
)
from .keys import algorithm_hash, generate_device_keys, sha256_hex
from .parse import (
    day_bounds,
    is_within_bounds,
    parse_account_response,
    parse_accounts,
    parse_card_limits,
    parse_card_response,
    parse_cards,
    parse_dynamic_check,
    parse_dynamic_complete,
    parse_dynamic_exec,
    parse_dynamic_groups,
    parse_dynamic_operation,
    parse_dynamic_step,
    parse_history,
    parse_payment_categories,
    parse_payment_providers,
    parse_profile,
    parse_recent_operations,
    to_date_param,
)
from .result import as_record, result_code_of
from .sign import sign_json_body, sign_params
from .storage import MemoryStorage
from .types import (
    Account,
    Card,
    CardLimit,
    DynamicCheckResult,
    DynamicCompleteResult,
    DynamicExecResult,
    DynamicGroup,
    DynamicOperationInfo,
    DynamicStep,
    HistoryPage,
    LoginResult,
    PaymentCategory,
    PaymentCheckResult,
    PaymentExecResult,
    PaymentProvider,
    Profile,
    RecentOperation,
    SessionStorage,
    StoredSession,
    Transaction,
    TransferArmResult,
    TransferExecResult,
    TransferPending,
    VerifyPaymentResult,
)

FORM_CONTENT_TYPE = "application/x-www-form-urlencoded"
MAX_HISTORY_PAGES = 100
LOCALE_TAG = {"ar": "ar_DZ", "fr": "fr_FR", "en": "en"}
LOCAL_HOSTS = {"localhost", "127.0.0.1", "::1"}


@dataclass
class Config:
    base_url: str = DEFAULT_BASE_URL
    allow_insecure: bool = False
    hash_password: Callable[[str, str], str] | None = None
    spec_revision: str = DEFAULT_SPEC_REVISION
    locale: str = "ar"
    time_zone: str = "GMT+01:00"
    device_name: str = "BaridiMob SDK"
    timeout: float = 30.0
    retries: int = 2
    storage: SessionStorage | None = None
    http_client: httpx.Client | None = None
    user_agent: str = DEFAULT_USER_AGENT


@dataclass
class _RequestSpec:
    method: str
    endpoint: str
    params: dict[str, str] | None = None
    json_body: dict[str, Any] | None = None
    safe: bool = True
    binary: bool = False


def _resolve_base_url(config: Config) -> str:
    parsed = urlparse(config.base_url)
    if parsed.scheme not in ("http", "https") or not parsed.hostname:
        raise BaridiMobError(f"Invalid baseUrl: {config.base_url}")
    normalized = config.base_url.rstrip("/")
    if parsed.scheme == "https":
        return normalized
    if parsed.scheme == "http" and (
        parsed.hostname in LOCAL_HOSTS or config.allow_insecure
    ):
        return normalized
    raise BaridiMobError(
        "baseUrl must use https (http is allowed only for localhost or with allow_insecure=True)"
    )


class BaridiMob:
    def __init__(self, config: Config | None = None):
        self.config = config or Config()
        self.storage: SessionStorage = self.config.storage or MemoryStorage()
        http_client = self.config.http_client or httpx.Client()
        self.transport = Transport(
            base_url=_resolve_base_url(self.config),
            spec_revision=self.config.spec_revision,
            locale=self.config.locale,
            timeout=self.config.timeout,
            retries=self.config.retries,
            user_agent=self.config.user_agent,
            client=http_client,
        )
        self.session: StoredSession | None = None
        self._loaded = False
        self._credentials: tuple[str, str] | None = None
        self._relogin_lock = threading.Lock()
        self.auth = _Auth(self)
        self.accounts = _Accounts(self)
        self.cards = _Cards(self)
        self.payments = _Payments(self)
        self.transfers = _Transfers(self)
        self.receipts = _Receipts(self)
        self.profile = _Profile(self)

    def _load_session(self) -> StoredSession | None:
        if not self._loaded:
            self.session = self.storage.load()
            if self.session:
                self.transport.restore(self.session.cookies)
            self._loaded = True
        return self.session

    def _require_session(self) -> StoredSession:
        if not self.session:
            raise DeviceFlowError("No device session: call login() first")
        return self.session

    def _persist(self) -> None:
        if not self.session:
            return
        self.session.cookies = self.transport.snapshot()
        self.storage.save(self.session)

    def _ensure_device(self) -> StoredSession:
        existing = self._load_session()
        if existing:
            return existing
        keys = generate_device_keys()
        self.session = StoredSession(
            version=1,
            devid=keys.devid,
            private_key_pem=keys.private_key_pem,
            devkey=keys.devkey,
            devkey_algorithm=keys.devkey_algorithm,
            cookies={},
            locale=self.config.locale,
        )
        return self.session

    def _perform_login(self, login: str, password: str) -> LoginResult:
        current = self._ensure_device()
        previous_cookies = self.transport.snapshot()
        self.transport.clear()

        def attempt(endpoint: str, pwd: str) -> dict[str, Any]:
            params = {
                "devid": current.devid,
                "devkeyAlgorithmHash": algorithm_hash(current.devkey_algorithm),
                "name": login,
                "pwd": pwd,
                "lang": self.config.locale,
                "locale": LOCALE_TAG.get(self.config.locale, "ar_DZ"),
                "timeZone": self.config.time_zone,
            }
            try:
                response = self.transport.send(
                    "POST",
                    endpoint,
                    body=sign_params(params, current.private_key_pem),
                    content_type=FORM_CONTENT_TYPE,
                )
            except Exception:
                self.transport.restore(previous_cookies)
                raise
            return as_record(response.data)

        body = attempt("login", password)
        code = result_code_of(body)

        if code == 143:
            hashed = (
                self.config.hash_password(login, password)
                if self.config.hash_password
                else sha256_hex(f"{login}{password}")
            )
            body = attempt("login/hash", hashed)
            code = result_code_of(body)
            if code == 143:
                self.transport.restore(previous_cookies)
                raise HashedRetryError(code, body)

        if code == 0:
            current.account = login
            self._persist()
            return LoginResult(state="authenticated")
        if code in (106, 107):
            current.account = login
            self._persist()
            return LoginResult(state="otp_required", devid=current.devid)

        self.transport.restore(previous_cookies)
        if code is None:
            raise ServerError(-1, body, "Response is missing numeric result code")
        raise error_for_result(code, body, current.devid)

    def _send_once(self, spec: _RequestSpec) -> SendResult:
        current = self._require_session()
        if spec.method == "GET":
            return self.transport.send(
                "GET",
                spec.endpoint,
                query=sign_params(spec.params or {}, current.private_key_pem),
                safe=spec.safe,
                binary=spec.binary,
            )
        if spec.json_body is not None:
            return self.transport.send(
                "POST",
                spec.endpoint,
                body=sign_json_body(spec.json_body, current.private_key_pem),
                content_type="application/json",
                safe=spec.safe,
            )
        return self.transport.send(
            "POST",
            spec.endpoint,
            body=sign_params(spec.params or {}, current.private_key_pem),
            content_type=FORM_CONTENT_TYPE,
            safe=spec.safe,
        )

    def _send_with_relogin(self, spec: _RequestSpec) -> SendResult:
        self._load_session()
        current = self._require_session()
        response = self._send_once(spec)
        code = None if response.content is not None else result_code_of(response.data or {})
        if code in (101, 102):
            if not self._credentials:
                raise SessionExpiredError()
            with self._relogin_lock:
                relogin = self._perform_login(*self._credentials)
            if relogin.state != "authenticated":
                raise DeviceConfirmationRequiredError(
                    106, response.data or {}, current.devid
                )
            response = self._send_once(spec)
        return response

    def _request(self, spec: _RequestSpec) -> dict[str, Any]:
        response = self._send_with_relogin(spec)
        body = response.data or {}
        raise_for_result(body, self.session.devid if self.session else None)
        self._persist()
        return body

    def _request_binary(self, spec: _RequestSpec) -> bytes:
        response = self._send_with_relogin(spec)
        if response.content is not None:
            self._persist()
            return response.content
        body = response.data or {}
        raise_for_result(body, self.session.devid if self.session else None)
        raise ServerError(-1, body, "Expected a binary response")

    def _get(self, endpoint: str, params: dict[str, str] | None = None) -> dict[str, Any]:
        return self._request(_RequestSpec(method="GET", endpoint=endpoint, params=params))

    def _fetch_history_page(
        self,
        account: str,
        from_value: date | datetime | str | None,
        to_value: date | datetime | str | None,
        page: int,
    ) -> list[Transaction]:
        params = {"account": account, "page": str(page)}
        if from_value is not None:
            params["startDate"] = to_date_param(from_value)
        if to_value is not None:
            params["endDate"] = to_date_param(to_value)
        return parse_history(self._get("accountHistory", params))

    def _iterate_transactions(
        self,
        account: str,
        from_value: date | datetime | str | None,
        to_value: date | datetime | str | None,
    ) -> Iterator[Transaction]:
        for page in range(1, MAX_HISTORY_PAGES + 1):
            items = self._fetch_history_page(account, from_value, to_value, page)
            if not items:
                return
            yield from items

    def _fetch_card_history_page(
        self,
        card: str,
        from_value: date | datetime | str | None,
        to_value: date | datetime | str | None,
        page: int,
        state: str | None,
    ) -> list[Transaction]:
        params = {"card": card, "page": str(page)}
        if from_value is not None:
            params["startDate"] = to_date_param(from_value)
        if to_value is not None:
            params["endDate"] = to_date_param(to_value)
        if state is not None:
            params["transactionState"] = state
        return parse_history(self._get("cardHistory", params))

    def _iterate_card_transactions(
        self,
        card: str,
        from_value: date | datetime | str | None,
        to_value: date | datetime | str | None,
        state: str | None,
    ) -> Iterator[Transaction]:
        for page in range(1, MAX_HISTORY_PAGES + 1):
            items = self._fetch_card_history_page(
                card, from_value, to_value, page, state
            )
            if not items:
                return
            yield from items

    def export_session(self) -> StoredSession | None:
        self._load_session()
        if not self.session:
            return None
        self.session.cookies = self.transport.snapshot()
        return StoredSession(
            version=self.session.version,
            devid=self.session.devid,
            private_key_pem=self.session.private_key_pem,
            devkey=self.session.devkey,
            devkey_algorithm=self.session.devkey_algorithm,
            cookies=dict(self.session.cookies),
            locale=self.session.locale,
            account=self.session.account,
        )

    def import_session(self, stored: StoredSession | dict[str, Any]) -> None:
        if isinstance(stored, dict):
            required = {
                "version",
                "devid",
                "private_key_pem",
                "devkey",
                "devkey_algorithm",
                "cookies",
            }
            if not required.issubset(stored):
                raise BaridiMobError("Invalid stored session")
            stored = StoredSession(**stored)
        if stored.version != 1:
            raise BaridiMobError("Invalid stored session")
        self.session = stored
        self._loaded = True
        self._credentials = None
        self.transport.restore(stored.cookies)
        self.storage.save(stored)


class _Auth:
    def __init__(self, client: BaridiMob):
        self._client = client

    def login(self, login: str, password: str) -> LoginResult:
        client = self._client
        client._load_session()
        if client.session and client.session.account and client.session.account != login:
            raise BaridiMobError(
                "Stored session belongs to a different account: call logout() or use a separate storage"
            )
        client._credentials = None
        result = client._perform_login(login, password)
        client._credentials = (login, password)
        return result

    def request_device_otp(self) -> None:
        client = self._client
        client._load_session()
        current = client._require_session()
        params = {
            "devkey": current.devkey,
            "devid": current.devid,
            "devkeyAlgorithm": current.devkey_algorithm,
        }
        client._request(
            _RequestSpec(
                method="POST",
                endpoint="deviceAttach",
                params=params,
                safe=False,
            )
        )

    def confirm_device(self, otp: str) -> LoginResult:
        client = self._client
        client._load_session()
        current = client._require_session()
        params = {
            "devcode": otp,
            "devid": current.devid,
            "devkeyAlgorithm": current.devkey_algorithm,
            "devname": client.config.device_name,
        }
        client._request(
            _RequestSpec(
                method="POST",
                endpoint="deviceConfirm",
                params=params,
                safe=False,
            )
        )
        if not client._credentials:
            raise DeviceFlowError(
                "Credentials are not in memory: call login() again after confirming"
            )
        return client._perform_login(*client._credentials)

    def logout(self) -> None:
        client = self._client
        client._load_session()
        if client.session:
            try:
                client._request(_RequestSpec(method="GET", endpoint="logout"))
            except BaridiMobError:
                pass
        client.storage.clear()
        client.transport.clear()
        client.session = None
        client._loaded = True
        client._credentials = None

    def current_device_id(self) -> str | None:
        session = self._client.session
        return session.devid if session else None


class _Accounts:
    def __init__(self, client: BaridiMob):
        self._client = client

    def list(self) -> list[Account]:
        return parse_accounts(self._client._get("accounts"))

    def get(self, account_id: str) -> Account:
        return parse_account_response(self._client._get("account", {"id": account_id}))

    def balance(self) -> float:
        accounts = self.list()
        if not accounts:
            raise DeviceFlowError("No account available")
        return accounts[0].balance

    def transactions(
        self,
        account: str,
        from_value: date | datetime | str | None = None,
        to_value: date | datetime | str | None = None,
        page: int = 1,
    ) -> HistoryPage:
        return HistoryPage(
            page=page,
            transactions=self._client._fetch_history_page(
                account, from_value, to_value, page
            ),
        )

    def all_transactions(
        self,
        account: str,
        from_value: date | datetime | str | None = None,
        to_value: date | datetime | str | None = None,
    ) -> list[Transaction]:
        return list(
            self._client._iterate_transactions(account, from_value, to_value)
        )

    def iter_transactions(
        self,
        account: str,
        from_value: date | datetime | str | None = None,
        to_value: date | datetime | str | None = None,
    ) -> Iterator[Transaction]:
        return self._client._iterate_transactions(account, from_value, to_value)

    def find_transaction(
        self,
        account: str,
        ref_num: str,
        from_value: date | datetime | str | None = None,
        to_value: date | datetime | str | None = None,
    ) -> Transaction | None:
        start, end = day_bounds(from_value, to_value)
        for transaction in self._client._iterate_transactions(
            account, from_value, to_value
        ):
            if transaction.ref_num != ref_num:
                continue
            if not is_within_bounds(transaction, start, end):
                continue
            return transaction
        return None


class _Cards:
    def __init__(self, client: BaridiMob):
        self._client = client

    def list(self) -> list[Card]:
        return parse_cards(self._client._get("cards", {"category": "REGULAR"}))

    def get(self, card_id: str) -> Card:
        return parse_card_response(self._client._get("card", {"id": card_id}))

    def limits(self, card_id: str) -> list[CardLimit]:
        locale = self._client.config.locale
        return parse_card_limits(
            self._client._get(
                "cardLimits",
                {
                    "card": card_id,
                    "language": locale,
                    "locale": LOCALE_TAG.get(locale, "ar_DZ"),
                },
            )
        )

    def history(
        self,
        card: str,
        from_value: date | datetime | str | None = None,
        to_value: date | datetime | str | None = None,
        page: int = 1,
        state: str | None = None,
    ) -> HistoryPage:
        return HistoryPage(
            page=page,
            transactions=self._client._fetch_card_history_page(
                card, from_value, to_value, page, state
            ),
        )

    def all_history(
        self,
        card: str,
        from_value: date | datetime | str | None = None,
        to_value: date | datetime | str | None = None,
        state: str | None = None,
    ) -> list[Transaction]:
        return list(
            self._client._iterate_card_transactions(
                card, from_value, to_value, state
            )
        )

    def iter_history(
        self,
        card: str,
        from_value: date | datetime | str | None = None,
        to_value: date | datetime | str | None = None,
        state: str | None = None,
    ) -> Iterator[Transaction]:
        return self._client._iterate_card_transactions(
            card, from_value, to_value, state
        )


class _Dynamic:
    def __init__(self, client: BaridiMob):
        self._client = client

    def groups(self) -> list[DynamicGroup]:
        return parse_dynamic_groups(self._client._get("dynamic/groups"))

    def operation(self, operation_id: str | int) -> DynamicOperationInfo:
        return parse_dynamic_operation(
            self._client._get(
                "dynamic/operation", {"operationId": str(operation_id)}
            )
        )

    def step(
        self,
        operation_id: str | int,
        params: dict[str, Any] | None = None,
        current_step_key: str | None = None,
    ) -> DynamicStep:
        return parse_dynamic_step(
            self._client._request(
                _RequestSpec(
                    method="POST",
                    endpoint="dynamic/operation/step",
                    json_body={
                        "operationId": str(operation_id),
                        **(
                            {"currentStepKey": current_step_key}
                            if current_step_key is not None
                            else {}
                        ),
                        "parameters": params or {},
                    },
                )
            )
        )

    def check(
        self,
        operation_id: str | int,
        params: dict[str, str] | None = None,
    ) -> DynamicCheckResult:
        form = {"operationId": str(operation_id)}
        for key, value in (params or {}).items():
            form[f"param.{key}"] = value
        return parse_dynamic_check(
            self._client._request(
                _RequestSpec(
                    method="POST",
                    endpoint="dynamic/operation/check",
                    params=form,
                )
            )
        )

    def request_otp(self, trans_ref: str) -> None:
        self._client._request(
            _RequestSpec(
                method="GET",
                endpoint="getOTPbySMS",
                params={"transRef": trans_ref},
                safe=False,
            )
        )

    def exec(
        self,
        operation_id: str | int,
        trans_ref: str,
        otp: str,
        params: dict[str, str] | None = None,
    ) -> DynamicExecResult:
        form = {
            "operationId": str(operation_id),
            "transRef": trans_ref,
            "confirmVal": otp,
        }
        for key, value in (params or {}).items():
            form[f"param.{key}"] = value
        return parse_dynamic_exec(
            self._client._request(
                _RequestSpec(
                    method="POST",
                    endpoint="dynamic/operation/execute",
                    params=form,
                    safe=False,
                )
            )
        )

    def complete(
        self, operation_id: str | int, trans_ref: str, confirm_val: str
    ) -> DynamicCompleteResult:
        return parse_dynamic_complete(
            self._client._request(
                _RequestSpec(
                    method="POST",
                    endpoint="dynamic/operation/complete",
                    params={
                        "operationId": str(operation_id),
                        "transRef": trans_ref,
                        "confirmVal": confirm_val,
                    },
                    safe=False,
                )
            )
        )


class _Payments:
    def __init__(self, client: BaridiMob):
        self._client = client
        self.dynamic = _Dynamic(client)

    def verify_payment(
        self,
        ref_num: str,
        amount: float | None = None,
        account: str | None = None,
        from_value: date | datetime | str | None = None,
        to_value: date | datetime | str | None = None,
    ) -> VerifyPaymentResult:
        now = datetime.now()
        if to_value is None:
            to_value = now
        if from_value is None:
            from_value = now.replace(microsecond=0) - timedelta(days=30)
        target_account = account or self._client.accounts.list()[0].number
        start, end = day_bounds(from_value, to_value)
        matches = [
            transaction
            for transaction in self._client._iterate_transactions(
                target_account, from_value, to_value
            )
            if transaction.ref_num == ref_num
            and is_within_bounds(transaction, start, end)
        ]
        if not matches:
            return VerifyPaymentResult(False, "not_found", None, [])
        incoming = [transaction for transaction in matches if transaction.amount > 0]
        if not incoming:
            return VerifyPaymentResult(False, "not_incoming", None, matches)
        if len(incoming) > 1:
            return VerifyPaymentResult(False, "duplicate", incoming[0], matches)
        transaction = incoming[0]
        if amount is not None and abs(transaction.amount - amount) > 0.009:
            return VerifyPaymentResult(False, "amount_mismatch", transaction, matches)
        return VerifyPaymentResult(True, "ok", transaction, matches)

    def categories(self) -> list[PaymentCategory]:
        return parse_payment_categories(self._client._get("paymentCategories"))

    def providers(self, cid: str | int) -> list[PaymentProvider]:
        return parse_payment_providers(
            self._client._get("paymentProviders", {"cid": str(cid)})
        )

    def check(
        self,
        pid: str,
        amount: float,
        source_type: str,
        source_id: str,
        params: dict[str, str] | None = None,
        currency: str = "DZD",
    ) -> PaymentCheckResult:
        form = {
            "pid": pid,
            "amount": str(amount),
            "currency": currency,
            "sourceType": "1" if source_type == "card" else "2",
            "sourceId": source_id,
        }
        for key, value in (params or {}).items():
            form[f"param.{key}"] = value
        body = self._client._request(
            _RequestSpec(method="POST", endpoint="paymentCheck", params=form)
        )
        return PaymentCheckResult(
            trans_ref=str(body.get("transRef") or ""),
            confirmation_type=as_record(body.get("confirmReq")).get("type"),
            raw=body,
        )

    def request_otp(self, trans_ref: str) -> None:
        self._client._request(
            _RequestSpec(
                method="GET",
                endpoint="getOTPbySMS",
                params={"transRef": trans_ref},
                safe=False,
            )
        )

    def exec(
        self,
        pid: str,
        amount: float,
        source_type: str,
        source_id: str,
        trans_ref: str,
        otp: str,
        params: dict[str, str] | None = None,
        currency: str = "DZD",
    ) -> PaymentExecResult:
        form = {
            "pid": pid,
            "amount": str(amount),
            "currency": currency,
            "sourceType": "1" if source_type == "card" else "2",
            "sourceId": source_id,
            "transRef": trans_ref,
            "flags": "0",
            "confirmVal": otp,
        }
        for key, value in (params or {}).items():
            form[f"param.{key}"] = value
        body = self._client._request(
            _RequestSpec(
                method="POST", endpoint="paymentExec", params=form, safe=False
            )
        )
        return PaymentExecResult(raw=body)


class _Transfers:
    def __init__(self, client: BaridiMob):
        self._client = client

    def strategies(
        self,
        amount: float = 100,
        currency: str = "DZD",
        action_type: int = 1,
        source_type: int = 2,
        target_type: int = 2,
        operation_subtype: int = 0,
    ) -> list[str]:
        body = self._client._get(
            "getConfirmationStrategies",
            {
                "amount": str(amount),
                "currency": currency,
                "actionType": str(action_type),
                "sourceType": str(source_type),
                "targetType": str(target_type),
                "operationSubtype": str(operation_subtype),
            },
        )
        values = body.get("confirmationStrategies")
        return [value for value in values if isinstance(value, str)] if isinstance(values, list) else []

    def arm(
        self,
        amount: float,
        source_id: str,
        target_id: str,
        currency: str = "DZD",
        source_type: int = 2,
        target_type: int = 2,
    ) -> TransferArmResult:
        form = {
            "amount": str(amount),
            "currency": currency,
            "sourceType": str(source_type),
            "sourceId": source_id,
            "targetType": str(target_type),
            "targetId": target_id,
        }
        body = self._client._request(
            _RequestSpec(method="POST", endpoint="transferCheck", params=form)
        )
        return TransferArmResult(
            trans_ref=str(body.get("transRef") or ""),
            confirmation_type=as_record(body.get("confirmReq")).get("type"),
            raw=body,
        )

    def request_otp(self, trans_ref: str) -> None:
        self._client._request(
            _RequestSpec(
                method="GET",
                endpoint="getOTPbySMS",
                params={"transRef": trans_ref},
                safe=False,
            )
        )

    def exec(
        self,
        amount: float,
        source_id: str,
        target_id: str,
        trans_ref: str,
        otp: str,
        currency: str = "DZD",
        source_type: int = 2,
        target_type: int = 2,
        operation_subtype: int = 0,
    ) -> TransferExecResult:
        form = {
            "amount": str(amount),
            "currency": currency,
            "sourceType": str(source_type),
            "sourceId": source_id,
            "targetType": str(target_type),
            "targetId": target_id,
            "transRef": trans_ref,
            "flags": "0",
            "confirmVal": otp,
            "operationSubtype": str(operation_subtype),
        }
        body = self._client._request(
            _RequestSpec(
                method="POST", endpoint="transferExec", params=form, safe=False
            )
        )
        return TransferExecResult(raw=body)

    def send(
        self,
        amount: float,
        source_id: str,
        target_id: str,
        currency: str = "DZD",
    ) -> TransferPending:
        armed = self.arm(amount, source_id, target_id, currency)
        self.request_otp(armed.trans_ref)
        return TransferPending(
            trans_ref=armed.trans_ref,
            amount=amount,
            source_id=source_id,
            target_id=target_id,
            confirmation_type=armed.confirmation_type,
            confirm=lambda otp: self.exec(
                amount, source_id, target_id, armed.trans_ref, otp, currency
            ),
        )


class _Receipts:
    def __init__(self, client: BaridiMob):
        self._client = client

    def list(self) -> list[RecentOperation]:
        return parse_recent_operations(self._client._get("recentOperations"))

    def download(self, uid: str) -> bytes:
        return self._client._request_binary(
            _RequestSpec(
                method="GET",
                endpoint="download/receipt",
                params={"uid": uid},
                binary=True,
            )
        )

    def find(self, transaction: Transaction) -> RecentOperation | None:
        operations = self.list()
        if transaction.ref_num is not None:
            for operation in operations:
                if operation.operation_id == transaction.ref_num:
                    return operation
        for operation in operations:
            if (
                operation.timestamp
                and operation.timestamp == transaction.timestamp
                and abs(abs(operation.amount) - abs(transaction.amount)) < 0.01
            ):
                return operation
        return None

    def download_for(self, transaction: Transaction) -> bytes | None:
        operation = self.find(transaction)
        if operation is None or not operation.uid:
            return None
        return self.download(operation.uid)


class _Profile:
    def __init__(self, client: BaridiMob):
        self._client = client

    def get(self) -> Profile:
        return parse_profile(self._client._get("profile"))


def create_client(config: Config | None = None) -> BaridiMob:
    return BaridiMob(config)
