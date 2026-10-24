from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, ClassVar, Protocol, runtime_checkable


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


@runtime_checkable
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
class Card:
    id: str
    number: str = field(repr=False)
    name: str
    brand: str
    status: int
    exp_date: str
    type: int = 0
    category: str | None = None
    balance: float | None = None
    currency: str | None = None
    embossed_name: str | None = None
    active: bool = True
    pin_not_set: bool = False
    linked_accounts: list[str] = field(default_factory=list)
    is_debit_allowed: bool = True
    raw: dict[str, Any] = field(repr=False, default_factory=dict)

    @property
    def is_valid(self) -> bool:
        return self.status == 0

    @property
    def is_temporarily_blocked(self) -> bool:
        return self.status == 20

    @property
    def is_permanently_blocked(self) -> bool:
        return self.status == 21

    @property
    def is_expired(self) -> bool:
        return self.status == 99


@dataclass
class CardLimit:
    uid: str
    name: str
    description: str | None = None
    type: int = 0
    amount: float | None = None
    used_amount: float | None = None
    op_count: int | None = None
    used_op_count: int | None = None
    currency: str | None = None
    active: bool = True
    changeable: bool = False
    permanent: bool = False
    per_transaction: bool = False
    end_time: str | None = None
    raw: dict[str, Any] = field(repr=False, default_factory=dict)

    @property
    def is_count(self) -> bool:
        return self.type == 1


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
class DynamicChoice:
    value: str
    label: str


@dataclass
class DynamicAmount:
    """An amount as BaridiMob writes it; ``text`` is sent back unchanged."""

    text: str
    currency: str | None = None

    @property
    def value(self) -> float | None:
        try:
            return float(self.text.strip().replace(",", "."))
        except ValueError:
            return None


@dataclass
class DynamicAmountChoice:
    label: str
    amount: DynamicAmount


@dataclass(frozen=True)
class DynamicSource:
    """Where a dynamic payment takes the money from.

    Dynamic operations name the source by type (``CLIENT_CARD_ID`` for a card,
    ``ACCOUNT_NUMBER`` for an account); BaridiMob answers result 2 to the
    ``1``/``2`` of ``payments.check``.
    """

    id: str
    type: str

    CARD_TYPE: ClassVar[str] = "CLIENT_CARD_ID"
    ACCOUNT_TYPE: ClassVar[str] = "ACCOUNT_NUMBER"

    @classmethod
    def card(cls, card_id: str) -> DynamicSource:
        return cls(card_id, cls.CARD_TYPE)

    @classmethod
    def account(cls, number: str) -> DynamicSource:
        return cls(number, cls.ACCOUNT_TYPE)


_TEXT_TYPES = ("string", "phone", "text", "email", "select", "datetime", "monthyear")


@dataclass
class DynamicStepInput:
    id: str
    label: str
    type: str
    required: bool
    settings: Any
    choices: list[DynamicChoice] = field(default_factory=list)
    access_attributes: list[str] = field(default_factory=list)
    value: str | None = None
    amount: DynamicAmount | None = None
    amount_mode: str = "input"
    amount_choices: list[DynamicAmountChoice] = field(default_factory=list)
    readonly: bool = False
    ordinal_number: int | None = None
    description: str | None = None
    raw: dict[str, Any] = field(repr=False, default_factory=dict)

    @property
    def is_hidden(self) -> bool:
        return self.type == "hidden"

    @property
    def is_source(self) -> bool:
        return self.type == "source_storage"

    @property
    def is_money(self) -> bool:
        return self.type == "money"

    @property
    def is_select(self) -> bool:
        return self.type == "select"

    def setting(self, key: str) -> str | None:
        settings = self.settings
        if not isinstance(settings, dict):
            return None
        value = settings.get(key)
        if isinstance(value, bool):
            return "true" if value else "false"
        if isinstance(value, str):
            return value
        if isinstance(value, (int, float)):
            return str(value)
        return None

    def _key(self, name: str, fallback: str) -> str:
        key = self.setting(name)
        return key if key else fallback

    def values_for(
        self,
        entered: str | None = None,
        source: DynamicSource | None = None,
        amount: DynamicAmount | None = None,
    ) -> dict[str, str]:
        """The values this field sends, built like the official app."""
        if self.type == "hidden":
            return {self.id: self.value or ""}
        if self.type == "source_storage":
            if source is None:
                return {}
            return {
                self._key("idKey", "sourceId"): source.id,
                self._key("typeKey", "sourceType"): source.type,
            }
        if self.type == "money":
            typed = entered.strip() if entered is not None else None
            if self.readonly:
                chosen = self.amount
            elif amount is not None:
                chosen = amount
            elif typed:
                chosen = DynamicAmount(typed)
            else:
                chosen = self.amount
            if chosen is None or chosen.text.strip() == "":
                return {}
            currency = (
                chosen.currency
                or (self.amount.currency if self.amount else None)
                or self.setting("defaultCurrency")
                or "DZD"
            )
            return {
                self._key("amountKey", "amount"): chosen.text.strip(),
                self._key("currencyKey", "currency"): currency,
            }
        if self.type in _TEXT_TYPES:
            text = self.value if self.readonly else (entered if entered is not None else self.value)
            return {self.id: text} if text else {}
        return {}


@dataclass
class DynamicStep:
    id: str
    label: str
    inputs: list[DynamicStepInput]
    done: bool = False
    raw: dict[str, Any] = field(repr=False, default_factory=dict)

    def values(
        self,
        entered: dict[str, str] | None = None,
        source: DynamicSource | None = None,
        amount: DynamicAmount | None = None,
    ) -> dict[str, str]:
        """The values to send for this step, built like the official app."""
        out: dict[str, str] = {}
        for item in self.inputs:
            out.update(
                item.values_for(
                    entered=(entered or {}).get(item.id),
                    source=source,
                    amount=amount,
                )
            )
        return out


@dataclass
class DynamicDetail:
    id: str
    label: str
    type: str
    text: str | None = None
    amount: DynamicAmount | None = None
    raw: dict[str, Any] = field(repr=False, default_factory=dict)


@dataclass
class DynamicCheckResult:
    trans_ref: str
    confirmation_type: str | None
    fee: float | None
    currency: str | None
    plan_date: str | None
    details: list[DynamicDetail] = field(default_factory=list)
    raw: dict[str, Any] = field(repr=False, default_factory=dict)

    @property
    def amount(self) -> DynamicAmount | None:
        for detail in self.details:
            if detail.amount is not None:
                return detail.amount
        return None


@dataclass
class DynamicExecResult:
    trans_ref: str | None
    recent_op_id: str | None
    recent_op_type: str | None
    authid: str | None
    confirmation_type: str | None
    status: str | None = None
    fee: float | None = None
    currency: str | None = None
    details: list[DynamicDetail] = field(default_factory=list)
    raw: dict[str, Any] = field(repr=False, default_factory=dict)


@dataclass
class DynamicCompleteResult:
    recent_op_id: str | None
    recent_op_type: str | None
    authid: str | None
    raw: dict[str, Any] = field(repr=False, default_factory=dict)


@dataclass
class CardlessInput:
    id: str
    label: str
    type: str
    description: str | None = None
    required: bool = False
    readonly: bool = False
    value: str | None = None
    stereotype: str | None = None
    pattern: str | None = None
    future: bool = False
    choices: list[DynamicChoice] = field(default_factory=list)
    raw: dict[str, Any] = field(repr=False, default_factory=dict)


@dataclass
class CardlessForm:
    inputs: list[CardlessInput] = field(default_factory=list)
    raw: dict[str, Any] = field(repr=False, default_factory=dict)

    @property
    def types(self) -> list[DynamicChoice]:
        for item in self.inputs:
            if item.type == "select" and item.choices:
                return item.choices
        return []


@dataclass(frozen=True)
class CardlessSource:
    id: str
    is_card: bool

    @classmethod
    def account(cls, account_id: str) -> CardlessSource:
        return cls(account_id, False)

    @classmethod
    def card(cls, card_id: str) -> CardlessSource:
        return cls(card_id, True)


@dataclass
class CardlessCode:
    """A cardless withdrawal code; treat ``code`` like cash."""

    id: str
    code: str | None = None
    amount: float | None = None
    currency: str | None = None
    status: str | None = None
    details: list[DynamicDetail] = field(default_factory=list)
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
    operation_id: str | None = None
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
