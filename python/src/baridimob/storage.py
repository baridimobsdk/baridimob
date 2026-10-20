from __future__ import annotations

import json
import os
from pathlib import Path

from .types import SessionStorage, StoredSession


class MemoryStorage(SessionStorage):
    def __init__(self, initial: StoredSession | None = None):
        self._session = _clone(initial) if initial else None

    def load(self) -> StoredSession | None:
        return _clone(self._session) if self._session else None

    def save(self, session: StoredSession) -> None:
        self._session = _clone(session)

    def clear(self) -> None:
        self._session = None


class FileStorage(SessionStorage):
    def __init__(self, path: str | Path):
        self.path = Path(path)

    def load(self) -> StoredSession | None:
        if not self.path.exists():
            return None
        try:
            raw = json.loads(self.path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise ValueError(f"Corrupted session file: {self.path}") from error
        return StoredSession(
            version=raw.get("version", 1),
            devid=raw["devid"],
            private_key_pem=raw.get("privateKeyPem") or raw["private_key_pem"],
            devkey=raw["devkey"],
            devkey_algorithm=raw.get("devkeyAlgorithm") or raw["devkey_algorithm"],
            cookies=dict(raw.get("cookies") or {}),
            locale=raw.get("locale", "ar"),
            account=raw.get("account"),
        )

    def save(self, session: StoredSession) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        payload = {
            "version": session.version,
            "devid": session.devid,
            "privateKeyPem": session.private_key_pem,
            "devkey": session.devkey,
            "devkeyAlgorithm": session.devkey_algorithm,
            "cookies": session.cookies,
            "locale": session.locale,
            "account": session.account,
        }
        text = json.dumps(payload, ensure_ascii=False, indent=2)
        descriptor = os.open(
            self.path,
            os.O_WRONLY | os.O_CREAT | os.O_TRUNC,
            0o600,
        )
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(text)

    def clear(self) -> None:
        try:
            self.path.unlink()
        except FileNotFoundError:
            return


def _clone(session: StoredSession | None) -> StoredSession | None:
    if session is None:
        return None
    return StoredSession(
        version=session.version,
        devid=session.devid,
        private_key_pem=session.private_key_pem,
        devkey=session.devkey,
        devkey_algorithm=session.devkey_algorithm,
        cookies=dict(session.cookies),
        locale=session.locale,
        account=session.account,
    )
