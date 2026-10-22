from __future__ import annotations

import re
from datetime import date, datetime, time, timedelta, timezone
from typing import Any

from .result import as_list, as_number, as_record, as_string
from .types import (
    Account,
    Card,
    CardLimit,
    CardlessCode,
    CardlessForm,
    CardlessInput,
    DynamicAmount,
    DynamicAmountChoice,
    DynamicCheckResult,
    DynamicChoice,
    DynamicCompleteResult,
    DynamicDetail,
    DynamicExecResult,
    DynamicGroup,
    DynamicOperationInfo,
    DynamicOperationRef,
    DynamicStep,
    DynamicStepInput,
    PaymentCategory,
    PaymentProvider,
    Profile,
    ProviderParam,
    RecentOperation,
    Transaction,
)

ALGIERS = timezone(timedelta(hours=1))


def parse_account(raw: dict[str, Any]) -> Account:
    number = as_string(raw.get("number")) or as_string(raw.get("id")) or ""
    identifier = as_string(raw.get("id")) or number
    return Account(
        id=identifier,
        number=number,
        balance=as_number(raw.get("balance")) or as_number(raw.get("amount")) or 0.0,
        currency=as_string(raw.get("currency")) or "DZD",
        raw=raw,
    )


def parse_accounts(body: dict[str, Any]) -> list[Account]:
    return [parse_account(as_record(item)) for item in as_list(body.get("accounts"))]


def parse_account_response(body: dict[str, Any]) -> Account:
    direct = as_record(body.get("account"))
    return parse_account(direct if direct else body)


def parse_timestamp(value: str) -> datetime | None:
    match = re.fullmatch(r"(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})", value)
    if not match:
        return None
    year, month, day, hour, minute, second = (int(part) for part in match.groups())
    try:
        return datetime(year, month, day, hour, minute, second, tzinfo=ALGIERS)
    except ValueError:
        return None


def detail_value(details: Any, detail_id: str) -> str | None:
    for entry in as_list(details):
        item = as_record(entry)
        if as_string(item.get("id")) == detail_id:
            return as_string(item.get("value"))
    return None


def parse_transaction(raw: dict[str, Any]) -> Transaction:
    timestamp = as_string(raw.get("timestamp")) or ""
    return Transaction(
        amount=as_number(raw.get("amount")) or 0.0,
        currency=as_string(raw.get("currency")) or "DZD",
        description=as_string(raw.get("description")) or "",
        type=as_string(raw.get("type")) or "",
        tid=as_string(raw.get("tid")) or "",
        timestamp=timestamp,
        date=parse_timestamp(timestamp),
        fee=as_number(raw.get("feeAmount")),
        ref_num=detail_value(raw.get("details"), "refNum"),
        raw=raw,
    )


def parse_history(body: dict[str, Any]) -> list[Transaction]:
    return [parse_transaction(as_record(item)) for item in as_list(body.get("history"))]


def _flag(value: Any, fallback: bool = False) -> bool:
    if isinstance(value, bool):
        return value
    number = as_number(value)
    return fallback if number is None else number != 0


def parse_card(raw: dict[str, Any]) -> Card:
    return Card(
        id=as_string(raw.get("id")) or "",
        number=as_string(raw.get("number")) or "",
        name=as_string(raw.get("name")) or "",
        brand=as_string(raw.get("brand")) or "",
        status=(
            -1
            if as_number(raw.get("status")) is None
            else int(as_number(raw.get("status")) or 0)
        ),
        exp_date=as_string(raw.get("expDate")) or "",
        type=(
            0
            if as_number(raw.get("type")) is None
            else int(as_number(raw.get("type")) or 0)
        ),
        category=as_string(raw.get("category")),
        balance=as_number(raw.get("balance")),
        currency=as_string(raw.get("currency")),
        embossed_name=as_string(raw.get("embossedName")),
        active=_flag(raw.get("active"), True),
        pin_not_set=_flag(raw.get("pinNotSet")),
        linked_accounts=[
            value
            for value in (as_string(item) for item in as_list(raw.get("linkedAccounts")))
            if value is not None
        ],
        is_debit_allowed=_flag(raw.get("isDebitAllowed"), True),
        raw=raw,
    )


def parse_cards(body: dict[str, Any]) -> list[Card]:
    return [parse_card(as_record(item)) for item in as_list(body.get("cards"))]


def parse_card_response(body: dict[str, Any]) -> Card:
    direct = as_record(body.get("card"))
    return parse_card(direct if direct else body)


def parse_card_limit(raw: dict[str, Any]) -> CardLimit:
    def integer(key: str) -> int | None:
        number = as_number(raw.get(key))
        return None if number is None else int(number)

    return CardLimit(
        uid=as_string(raw.get("uid")) or "",
        name=as_string(raw.get("name")) or "",
        description=as_string(raw.get("description")),
        type=integer("type") or 0,
        amount=as_number(raw.get("amount")),
        used_amount=as_number(raw.get("usedAmount")),
        op_count=integer("opCount"),
        used_op_count=integer("usedOpCount"),
        currency=as_string(raw.get("currency")),
        active=_flag(raw.get("active"), True),
        changeable=_flag(raw.get("changeable")),
        permanent=_flag(raw.get("permanent")),
        per_transaction=_flag(raw.get("perTransaction")),
        end_time=as_string(raw.get("endTime")),
        raw=raw,
    )


def parse_card_limits(body: dict[str, Any]) -> list[CardLimit]:
    return [
        parse_card_limit(as_record(item)) for item in as_list(body.get("limits"))
    ]


def to_date_param(value: date | datetime | str) -> str:
    if isinstance(value, str) and re.fullmatch(r"\d{8}", value):
        return value
    if isinstance(value, datetime):
        moment = value
    elif isinstance(value, date):
        moment = datetime(value.year, value.month, value.day)
    else:
        try:
            moment = datetime.fromisoformat(str(value))
        except ValueError as error:
            raise TypeError(f"Invalid date: {value}") from error
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=ALGIERS)
    return moment.astimezone(ALGIERS).strftime("%Y%m%d")


def day_bounds(
    from_value: date | datetime | str | None,
    to_value: date | datetime | str | None,
) -> tuple[datetime | None, datetime | None]:
    start = None
    end = None
    if from_value is not None:
        param = to_date_param(from_value)
        start = datetime(
            int(param[0:4]), int(param[4:6]), int(param[6:8]), tzinfo=ALGIERS
        )
    if to_value is not None:
        param = to_date_param(to_value)
        end = datetime(
            int(param[0:4]),
            int(param[4:6]),
            int(param[6:8]),
            23,
            59,
            59,
            999999,
            tzinfo=ALGIERS,
        )
    return start, end


def is_within_bounds(transaction: Transaction, start: datetime | None, end: datetime | None) -> bool:
    if transaction.date is None:
        return False
    if start is not None and transaction.date < start:
        return False
    if end is not None and transaction.date > end:
        return False
    return True


def parse_profile(body: dict[str, Any]) -> Profile:
    return Profile(
        actor_id=as_string(body.get("actorId")) or "",
        client_name=as_string(body.get("clientName")),
        last_login=as_string(body.get("lastLoginDatetime")),
        financial_operations_disabled=as_number(body.get("financialOperationsDisabled")) == 1,
        raw=body,
    )


def parse_recent_operations(body: dict[str, Any]) -> list[RecentOperation]:
    operations: list[RecentOperation] = []
    for item in as_list(body.get("operations")):
        raw = as_record(item)
        timestamp = as_string(raw.get("timestamp")) or ""
        operations.append(
            RecentOperation(
                uid=as_string(raw.get("uid")) or "",
                type=as_string(raw.get("type")) or "",
                pid=as_string(raw.get("pid")) or "",
                amount=as_number(raw.get("amount")) or 0.0,
                currency=as_string(raw.get("currency")) or "DZD",
                timestamp=timestamp,
                date=parse_timestamp(timestamp),
                provider_name=as_string(raw.get("providerName")),
                source_type=(
                    None
                    if as_number(raw.get("sourceType")) is None
                    else int(as_number(raw.get("sourceType")) or 0)
                ),
                source_id=as_string(raw.get("sourceId")),
                status=(
                    None
                    if as_number(raw.get("status")) is None
                    else int(as_number(raw.get("status")) or 0)
                ),
                operation_id=detail_value(raw.get("details"), "operationId"),
                raw=raw,
            )
        )
    return operations


def parse_payment_categories(body: dict[str, Any]) -> list[PaymentCategory]:
    categories: list[PaymentCategory] = []
    for item in as_list(body.get("categories")):
        raw = as_record(item)
        categories.append(
            PaymentCategory(
                cid=as_string(raw.get("cid")) or "",
                name=as_string(raw.get("name")) or "",
                image=as_string(raw.get("image")),
                raw=raw,
            )
        )
    return categories


def parse_provider_param(value: Any) -> ProviderParam:
    raw = as_record(value)
    return ProviderParam(
        id=as_string(raw.get("id")) or "",
        name=as_string(raw.get("name")) or "",
        type=as_string(raw.get("type")) or "",
        pattern=as_string(raw.get("pattern")),
        min=as_number(raw.get("min")),
        max=as_number(raw.get("max")),
        value=as_string(raw.get("value")),
        description=as_string(raw.get("description")),
        has_external_handler=raw.get("hasExternalHandler") is True,
    )


def parse_payment_providers(body: dict[str, Any]) -> list[PaymentProvider]:
    providers: list[PaymentProvider] = []
    for item in as_list(body.get("providers")):
        raw = as_record(item)
        providers.append(
            PaymentProvider(
                pid=as_string(raw.get("pid")) or "",
                name=as_string(raw.get("name")) or "",
                mapped_id=as_string(raw.get("mappedId")),
                cid=as_string(raw.get("cid")),
                scenario=as_string(raw.get("scenario")),
                category_name=as_string(raw.get("categoryName")),
                params=[parse_provider_param(param) for param in as_list(raw.get("params"))],
                raw=raw,
            )
        )
    return providers


def parse_operation_ref(value: Any) -> DynamicOperationRef:
    raw = as_record(value)
    return DynamicOperationRef(
        id=as_string(raw.get("id")) or "",
        label=as_string(raw.get("label")) or "",
    )


def parse_dynamic_groups(body: dict[str, Any]) -> list[DynamicGroup]:
    groups: list[DynamicGroup] = []
    for item in as_list(body.get("groups")):
        raw = as_record(item)
        groups.append(
            DynamicGroup(
                id=as_string(raw.get("id")) or "",
                label=as_string(raw.get("label")) or "",
                type=as_string(raw.get("type")),
                image=as_string(raw.get("image")),
                operations=[parse_operation_ref(op) for op in as_list(raw.get("operations"))],
                raw=raw,
            )
        )
    return groups


def parse_dynamic_operation(body: dict[str, Any]) -> DynamicOperationInfo:
    raw = as_record(body.get("operationInfo"))
    first_step = raw.get("firstStep")
    return DynamicOperationInfo(
        id=as_string(raw.get("id")) or "",
        label=as_string(raw.get("label")) or "",
        first_step=parse_operation_ref(first_step) if first_step else None,
        save_template_enabled=raw.get("saveTemplateEnabled") is True,
        raw=raw,
    )


def _setting_flag(value: Any) -> bool:
    """A setting sent as true/false, "true"/"false" or 0/1."""
    if value is True or value == "true":
        return True
    number = as_number(value)
    return number is not None and number != 0


def _parse_amount(value: Any, currency: str | None = None) -> DynamicAmount | None:
    if isinstance(value, dict):
        raw = as_record(value)
        inner = raw.get("amount")
        if inner is None:
            inner = raw.get("sum")
        if inner is None:
            inner = raw.get("value")
        text = as_string(inner)
        if text is None or text.strip() == "":
            return None
        return DynamicAmount(text.strip(), as_string(raw.get("currency")) or currency)
    text = as_string(value)
    if text is None or text.strip() == "":
        return None
    return DynamicAmount(text.strip(), currency)


def parse_step_input(value: Any) -> DynamicStepInput:
    raw = as_record(value)
    settings = as_record(raw.get("settings"))
    kind = as_string(raw.get("type")) or ""
    money = kind == "money"
    prefilled: str | None = None
    if not money:
        prefilled = as_string(raw.get("value"))
        if not prefilled:
            if kind == "hidden":
                prefilled = as_string(settings.get("value")) or prefilled
            elif kind in ("string", "phone"):
                prefilled = as_string(settings.get("defaultValue")) or prefilled
    choices: list[DynamicChoice] = []
    amount_choices: list[DynamicAmountChoice] = []
    for item in as_list(raw.get("selectionList")):
        entry = as_record(item)
        if money:
            amount = _parse_amount(entry.get("value"))
            if amount is not None:
                amount_choices.append(
                    DynamicAmountChoice(as_string(entry.get("label")) or amount.text, amount)
                )
        else:
            choices.append(
                DynamicChoice(
                    value=as_string(entry.get("value")) or "",
                    label=as_string(entry.get("label")) or "",
                )
            )
    access_attributes = [
        text
        for text in (as_string(item) for item in as_list(raw.get("accessAttributes")))
        if text is not None
    ]
    ordinal = as_number(raw.get("ordinalNumber"))
    mode = str(settings.get("mode") or "").upper()
    return DynamicStepInput(
        id=as_string(raw.get("id")) or "",
        label=as_string(raw.get("label")) or "",
        type=kind,
        required=_setting_flag(raw.get("required")) or _setting_flag(settings.get("required")),
        settings=raw.get("settings"),
        choices=choices,
        access_attributes=access_attributes,
        value=prefilled,
        amount=_parse_amount(raw.get("value")) if money else None,
        amount_mode="select" if money and mode == "SELECT" else "input",
        amount_choices=amount_choices,
        readonly=_setting_flag(settings.get("readonly")) or _setting_flag(raw.get("readOnly")),
        ordinal_number=None if ordinal is None else int(ordinal),
        description=as_string(raw.get("description")),
        raw=raw,
    )


def parse_dynamic_step(body: dict[str, Any]) -> DynamicStep:
    """Parses a step; its fields come in the order of their ``ordinalNumber``,
    and a response without a step is ``done``."""
    current = body.get("currentStep")
    if not isinstance(current, dict):
        return DynamicStep(id="", label="", inputs=[], done=True, raw=body)
    raw = as_record(current)
    inputs = [parse_step_input(item) for item in as_list(raw.get("inputs"))]
    # A stable sort, as the official app's comparator (no number counts as 0).
    inputs.sort(key=lambda item: item.ordinal_number or 0)
    return DynamicStep(
        id=as_string(raw.get("id")) or "",
        label=as_string(raw.get("label")) or "",
        inputs=inputs,
        raw=raw,
    )


def parse_dynamic_details(value: Any) -> list[DynamicDetail]:
    details: list[DynamicDetail] = []
    for item in as_list(value):
        raw = as_record(item)
        if not raw:
            continue
        kind = as_string(raw.get("type")) or ""
        content = raw.get("value")
        money = kind == "money"
        if money:
            text = None
        elif isinstance(content, bool):
            text = "true" if content else "false"
        else:
            text = as_string(content)
        details.append(
            DynamicDetail(
                id=as_string(raw.get("id")) or "",
                label=as_string(raw.get("label")) or "",
                type=kind,
                text=text,
                amount=_parse_amount(content) if money else None,
                raw=raw,
            )
        )
    return details


def parse_dynamic_check(body: dict[str, Any]) -> DynamicCheckResult:
    return DynamicCheckResult(
        trans_ref=as_string(body.get("transRef")) or "",
        confirmation_type=as_string(as_record(body.get("confirmReq")).get("type")),
        fee=as_number(body.get("fee")),
        currency=as_string(body.get("currency")),
        plan_date=as_string(body.get("planDate")),
        details=parse_dynamic_details(body.get("details")),
        raw=body,
    )


def parse_dynamic_exec(body: dict[str, Any]) -> DynamicExecResult:
    return DynamicExecResult(
        trans_ref=as_string(body.get("transRef")),
        recent_op_id=as_string(body.get("recentOpId")),
        recent_op_type=as_string(body.get("recentOpType")),
        authid=as_string(body.get("authid")),
        confirmation_type=as_string(as_record(body.get("confirmReq")).get("type")),
        status=as_string(as_record(body.get("operationStatus")).get("type")),
        fee=as_number(body.get("fee")),
        currency=as_string(body.get("currency")),
        details=parse_dynamic_details(body.get("details")),
        raw=body,
    )


def parse_dynamic_complete(body: dict[str, Any]) -> DynamicCompleteResult:
    return DynamicCompleteResult(
        recent_op_id=as_string(body.get("recentOpId")),
        recent_op_type=as_string(body.get("recentOpType")),
        authid=as_string(body.get("authid")),
        raw=body,
    )


def _parse_cardless_input(value: Any) -> CardlessInput:
    raw = as_record(value)
    settings = as_record(raw.get("settings"))
    return CardlessInput(
        id=as_string(raw.get("id")) or "",
        label=as_string(raw.get("label")) or "",
        type=as_string(raw.get("type")) or "",
        description=as_string(raw.get("description")),
        required=_setting_flag(raw.get("required")) or _setting_flag(settings.get("required")),
        readonly=_setting_flag(raw.get("readOnly")) or _setting_flag(settings.get("readonly")),
        value=as_string(raw.get("value")) or as_string(settings.get("value")),
        stereotype=as_string(raw.get("stereotype")),
        pattern=as_string(raw.get("pattern")),
        future=_setting_flag(raw.get("future")),
        choices=[
            DynamicChoice(
                value=as_string(as_record(item).get("value")) or "",
                label=as_string(as_record(item).get("label")) or "",
            )
            for item in as_list(raw.get("selectionList"))
        ],
        raw=raw,
    )


def parse_cardless_form(body: dict[str, Any]) -> CardlessForm:
    return CardlessForm(
        inputs=[_parse_cardless_input(item) for item in as_list(body.get("inputs"))],
        raw=body,
    )


def parse_cardless_code(raw: dict[str, Any]) -> CardlessCode:
    return CardlessCode(
        id=as_string(raw.get("id")) or "",
        code=as_string(raw.get("code")),
        amount=as_number(raw.get("amount")),
        currency=as_string(raw.get("currency")),
        status=as_string(raw.get("status")),
        details=parse_dynamic_details(raw.get("additionalData")),
        raw=raw,
    )


def parse_cardless_codes(body: dict[str, Any]) -> list[CardlessCode]:
    return [
        parse_cardless_code(as_record(item))
        for item in as_list(body.get("operations"))
        if as_record(item)
    ]


DEFAULT_CARDLESS_DATE_PATTERN = "yyyy-MM-dd'T'HH:mm:ss.SSSXXX"


def format_date_pattern(value: datetime, pattern: str) -> str:
    """Formats ``value`` in Algeria time (UTC+1) with a Java date pattern:
    ``yyyy MM dd HH mm ss SSS``, an offset (``XXX``, ``Z``) and quoted
    literals. A naive datetime is read as Algeria time."""
    moment = value if value.tzinfo is not None else value.replace(tzinfo=ALGIERS)
    local = moment.astimezone(ALGIERS)
    out: list[str] = []
    i = 0
    while i < len(pattern):
        letter = pattern[i]
        if letter == "'":
            end = pattern.find("'", i + 1)
            if end < 0:
                out.append(pattern[i + 1 :])
                break
            out.append("'" if end == i + 1 else pattern[i + 1 : end])
            i = end + 1
            continue
        j = i
        while j < len(pattern) and pattern[j] == letter:
            j += 1
        width = j - i
        if letter == "y":
            out.append(
                str(local.year % 100).zfill(2) if width == 2 else str(local.year).zfill(width)
            )
        elif letter == "M":
            out.append(str(local.month).zfill(width))
        elif letter == "d":
            out.append(str(local.day).zfill(width))
        elif letter == "H":
            out.append(str(local.hour).zfill(width))
        elif letter == "m":
            out.append(str(local.minute).zfill(width))
        elif letter == "s":
            out.append(str(local.second).zfill(width))
        elif letter == "S":
            out.append(str(local.microsecond // 1000).zfill(width))
        elif letter == "X":
            out.append("+01" if width == 1 else ("+0100" if width == 2 else "+01:00"))
        elif letter == "Z":
            out.append("+01:00" if width >= 5 else "+0100")
        else:
            out.append(pattern[i:j])
        i = j
    return "".join(out)
