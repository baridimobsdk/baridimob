from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any

import httpx

from .errors import BaridiMobError, NetworkError, ServerError, TimeoutError

DEFAULT_BASE_URL = "https://baridimob.poste.dz/mobilebank/service"
DEFAULT_SPEC_REVISION = "29200428"
DEFAULT_USER_AGENT = (
    "Dalvik/2.1.0 (Linux; U; Android 9; V2229A Build/PQ3B.190801.12191611)"
)

ACCEPT_LANGUAGE = {"ar": "ar-DZ", "fr": "fr-FR", "en": "en"}


@dataclass
class SendResult:
    status: int
    data: dict[str, Any] | None = None
    content: bytes | None = None


class _Retryable(Exception):
    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status


class Transport:
    def __init__(
        self,
        base_url: str,
        spec_revision: str,
        locale: str,
        timeout: float,
        retries: int,
        user_agent: str,
        client: httpx.Client,
    ):
        self.base_url = base_url.rstrip("/")
        self.spec_revision = spec_revision
        self.locale = locale
        self.timeout = timeout
        self.retries = retries
        self.user_agent = user_agent
        self.client = client
        self.cookies: dict[str, str] = {}

    def cookie_header(self) -> str:
        return "; ".join(f"{name}={value}" for name, value in self.cookies.items())

    def snapshot(self) -> dict[str, str]:
        return dict(self.cookies)

    def restore(self, cookies: dict[str, str]) -> None:
        self.cookies = {name: value for name, value in cookies.items() if name}

    def clear(self) -> None:
        self.cookies.clear()

    def send(
        self,
        method: str,
        endpoint: str,
        *,
        query: str | None = None,
        body: str | None = None,
        content_type: str | None = None,
        safe: bool = True,
        binary: bool = False,
    ) -> SendResult:
        attempts = max(0, self.retries) + 1 if safe else 1
        last_error: Exception | None = None
        for attempt in range(attempts):
            try:
                return self._attempt(
                    method, endpoint, query, body, content_type, binary
                )
            except (NetworkError, TimeoutError, _Retryable) as error:
                last_error = error
                if attempt == attempts - 1:
                    raise self._to_public(error) from error
        raise self._to_public(last_error)

    def _to_public(self, error: Exception | None) -> Exception:
        if isinstance(error, _Retryable):
            return ServerError(error.status, {"httpStatus": error.status}, str(error))
        if isinstance(error, (NetworkError, TimeoutError, BaridiMobError)):
            return error
        return NetworkError("Request failed")

    def _attempt(
        self,
        method: str,
        endpoint: str,
        query: str | None,
        body: str | None,
        content_type: str | None,
        binary: bool,
    ) -> SendResult:
        url = f"{self.base_url}/{endpoint}"
        if query:
            url = f"{url}?{query}"

        headers = {
            "accept": "application/json, application/*+json",
            "platform": "android",
            "spec-revision": self.spec_revision,
            "accept-language": ACCEPT_LANGUAGE.get(self.locale, "ar-DZ"),
            "user-agent": self.user_agent,
        }
        if body is not None:
            headers["content-type"] = content_type or "application/x-www-form-urlencoded"
        cookie = self.cookie_header()
        if cookie:
            headers["cookie"] = cookie

        try:
            response = self.client.request(
                method,
                url,
                content=body,
                headers=headers,
                timeout=self.timeout,
                follow_redirects=False,
            )
        except httpx.TimeoutException as error:
            raise TimeoutError(f"Request timed out after {self.timeout}s") from error
        except httpx.HTTPError as error:
            raise NetworkError("Network request failed") from error

        self._absorb(response)

        if response.status_code >= 500 or response.status_code == 429:
            raise _Retryable(response.status_code, f"Server responded {response.status_code}")

        content_type_header = response.headers.get("content-type", "")
        if binary and "json" not in content_type_header:
            return SendResult(status=response.status_code, content=response.content)

        text = response.text
        if text.strip() == "":
            return SendResult(status=response.status_code, data={})
        try:
            parsed = json.loads(text)
        except json.JSONDecodeError as error:
            raise ServerError(
                -1, {"body": text[:500]}, "Response is not valid JSON"
            ) from error
        return SendResult(
            status=response.status_code,
            data=parsed if isinstance(parsed, dict) else {},
        )

    def _absorb(self, response: httpx.Response) -> None:
        for entry in response.headers.get_list("set-cookie"):
            pair = entry.split(";", 1)[0]
            if "=" not in pair:
                continue
            name, value = pair.split("=", 1)
            name = name.strip()
            if name:
                self.cookies[name] = value.strip()
