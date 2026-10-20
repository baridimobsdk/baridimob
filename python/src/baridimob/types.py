from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Protocol


@dataclass
class StoredSession:
    version: int
    devid: str
    private_key_pem: str
    devkey: str
    devkey_algorithm: str
    cookies: dict[str, str]
    locale: str
    account: str | None = None


class SessionStorage(Protocol):
    def load(self) -> StoredSession | None: ...

    def save(self, session: StoredSession) -> None: ...

    def clear(self) -> None: ...


@dataclass
class Account:
    id: str
    number: str
    balance: float
    currency: str
    raw: dict[str, Any] = field(repr=False, default_factory=dict)


@dataclass
class Transaction:
    amount: float
    currency: str
    description: str
    type: str
    tid: str
    timestamp: str
    date: Any
    fee: float | None
    ref_num: str | None
    raw: dict[str, Any] = field(repr=False, default_factory=dict)


@dataclass
class HistoryPage:
    page: int
    transactions: list[Transaction]


@dataclass
class LoginResult:
    state: str
    devid: str | None = None


@dataclass
class PaymentCategory:
    cid: str
    name: str
    image: str | None
    raw: dict[str, Any] = field(repr=False, default_factory=dict)


@dataclass
class ProviderParam:
    id: str
    name: str
    type: str
    pattern: str | None
    min: float | None
    max: float | None
    value: str | None
    description: str | None
    has_external_handler: bool


@dataclass
class PaymentProvider:
    pid: str
    name: str
    mapped_id: str | None
    cid: str | None
    scenario: str | None
    category_name: str | None
    params: list[ProviderParam]
    raw: dict[str, Any] = field(repr=False, default_factory=dict)


@dataclass
class PaymentCheckResult:
    trans_ref: str
    confirmation_type: str | None
    raw: dict[str, Any] = field(repr=False, default_factory=dict)


@dataclass
class PaymentExecResult:
    raw: dict[str, Any] = field(repr=False, default_factory=dict)


@dataclass
class DynamicOperationRef:
    id: str
    label: str


@dataclass
class DynamicGroup:
    id: str
    label: str
    type: str | None
    image: str | None
    operations: list[DynamicOperationRef]
    raw: dict[str, Any] = field(repr=False, default_factory=dict)


@dataclass
class DynamicOperationInfo:
    id: str
    label: str
    first_step: DynamicOperationRef | None
    save_template_enabled: bool
    raw: dict[str, Any] = field(repr=False, default_factory=dict)


@dataclass
class DynamicStepInput:
    id: str
    label: str
    type: str
    required: bool
    settings: Any
    raw: dict[str, Any] = field(repr=False, default_factory=dict)


@dataclass
class DynamicStep:
    id: str
    label: str
    inputs: list[DynamicStepInput]
    raw: dict[str, Any] = field(repr=False, default_factory=dict)


@dataclass
class TransferArmResult:
    trans_ref: str
    confirmation_type: str | None
    raw: dict[str, Any] = field(repr=False, default_factory=dict)


@dataclass
class TransferExecResult:
    raw: dict[str, Any] = field(repr=False, default_factory=dict)


@dataclass
class TransferPending:
    trans_ref: str
    amount: float
    source_id: str
    target_id: str
    confirmation_type: str | None
    confirm: Any


@dataclass
class RecentOperation:
    uid: str
    type: str
    pid: str
    amount: float
    currency: str
    timestamp: str
    date: Any
    provider_name: str | None
    source_type: int | None
    source_id: str | None
    status: int | None
    raw: dict[str, Any] = field(repr=False, default_factory=dict)


@dataclass
class Profile:
    actor_id: str
    client_name: str | None
    last_login: str | None
    financial_operations_disabled: bool
    raw: dict[str, Any] = field(repr=False, default_factory=dict)


@dataclass
class VerifyPaymentResult:
    verified: bool
    reason: str
    transaction: Transaction | None
    matches: list[Transaction]
