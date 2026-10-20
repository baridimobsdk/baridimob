from __future__ import annotations

import re
from datetime import date, datetime, time, timedelta, timezone
from typing import Any

from .result import as_list, as_number, as_record, as_string
from .types import (
    Account,
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


def parse_step_input(value: Any) -> DynamicStepInput:
    raw = as_record(value)
    settings = as_record(raw.get("settings"))
    required = (
        raw.get("required") is True
        or settings.get("required") is True
        or settings.get("required") == "true"
    )
    return DynamicStepInput(
        id=as_string(raw.get("id")) or "",
        label=as_string(raw.get("label")) or "",
        type=as_string(raw.get("type")) or "",
        required=required,
        settings=raw.get("settings"),
        raw=raw,
    )


def parse_dynamic_step(body: dict[str, Any]) -> DynamicStep:
    raw = as_record(body.get("currentStep"))
    return DynamicStep(
        id=as_string(raw.get("id")) or "",
        label=as_string(raw.get("label")) or "",
        inputs=[parse_step_input(item) for item in as_list(raw.get("inputs"))],
        raw=raw,
    )
