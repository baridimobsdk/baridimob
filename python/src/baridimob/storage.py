from __future__ import annotations

import json
import os
import sys
from datetime import timedelta
from pathlib import Path
from typing import TYPE_CHECKING, Any

if sys.version_info >= (3, 11):
    from typing import Self
else:
    from typing_extensions import Self

from .types import SessionStorage, StoredSession

if TYPE_CHECKING:
    import redis

__all__ = ["FileStorage", "MemoryStorage", "RedisStorage"]


def _session_to_dict(session: StoredSession) -> dict[str, Any]:
    return {
        "version": session.version,
        "devid": session.devid,
        "privateKeyPem": session.private_key_pem,
        "devkey": session.devkey,
        "devkeyAlgorithm": session.devkey_algorithm,
        "cookies": dict(session.cookies),
        "locale": session.locale,
        "account": session.account,
    }


def _session_from_dict(raw: Any) -> StoredSession:
    if not isinstance(raw, dict):
        raise TypeError("Session payload must be a JSON object")
    if "devid" not in raw or "devkey" not in raw:
        raise KeyError("Missing required session fields ('devid' or 'devkey')")

    pem = raw.get("privateKeyPem") or raw.get("private_key_pem")
    if not pem:
        raise KeyError("Missing required 'privateKeyPem' field")

    algorithm = raw.get("devkeyAlgorithm") or raw.get("devkey_algorithm")
    if not algorithm:
        raise KeyError("Missing required 'devkeyAlgorithm' field")

    return StoredSession(
        version=int(raw.get("version", 1)),
        devid=str(raw["devid"]),
        private_key_pem=str(pem),
        devkey=str(raw["devkey"]),
        devkey_algorithm=str(algorithm),
        cookies=dict(raw.get("cookies") or {}),
        locale=str(raw.get("locale", "ar")),
        account=str(raw["account"]) if raw.get("account") is not None else None,
    )


class MemoryStorage(SessionStorage):
    """In-memory session storage for tests and short-lived processes."""

    def __init__(self, initial: StoredSession | None = None):
        self._session = _clone(initial) if initial else None

    def load(self) -> StoredSession | None:
        return _clone(self._session) if self._session else None

    def save(self, session: StoredSession) -> None:
        self._session = _clone(session)

    def clear(self) -> None:
        self._session = None


class FileStorage(SessionStorage):
    """File-backed session storage saved as a secure JSON file."""

    def __init__(self, path: str | Path):
        self.path = Path(path)

    def load(self) -> StoredSession | None:
        if not self.path.exists():
            return None
        try:
            raw = json.loads(self.path.read_text(encoding="utf-8"))
            return _session_from_dict(raw)
        except (OSError, json.JSONDecodeError, KeyError, TypeError, ValueError) as error:
            raise ValueError(f"Corrupted session file: {self.path}") from error

    def save(self, session: StoredSession) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        payload = _session_to_dict(session)
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


class RedisStorage(SessionStorage):
    """Production-ready Redis-backed session storage for BaridiMob.

    Stores session device keys, cookies, and tokens in a Redis key with
    optional expiration (TTL). Conforms to the `SessionStorage` protocol.

    Args:
        url_or_client: Redis URL string (e.g. "redis://localhost:6379/0") or an
            existing Redis client instance.
        url: Explicit Redis URL string. Mutually exclusive with `redis_client`.
        redis_client: An existing Redis client instance (e.g. redis.Redis or fakeredis).
        prefix: Key prefix for Redis keys. Defaults to "baridimob:session:".
        key_prefix: Alias for `prefix`.
        key: Key identifier appended to prefix. Defaults to "default".
        session_id: Alias for `key`.
        ttl: Expiration duration as seconds (int/float) or datetime.timedelta.
        expiration: Alias for `ttl`.

    Raises:
        ImportError: If `redis` is not installed and no `redis_client` was provided.
        ValueError: If conflicting arguments or invalid TTL values are passed.
        TypeError: If `redis_client` does not implement standard Redis operations.
    """

    def __init__(
        self,
        url_or_client: str | redis.Redis | Any | None = None,
        *,
        url: str | None = None,
        redis_client: redis.Redis | Any | None = None,
        prefix: str = "baridimob:session:",
        key_prefix: str | None = None,
        key: str = "default",
        session_id: str | None = None,
        ttl: float | timedelta | None = None,
        expiration: float | timedelta | None = None,
    ) -> None:
        # Resolve url_or_client positional argument
        if isinstance(url_or_client, str):
            if url is not None and url != url_or_client:
                raise ValueError("Conflicting 'url' and positional argument provided")
            url = url_or_client
        elif url_or_client is not None:
            if redis_client is not None and redis_client != url_or_client:
                raise ValueError("Conflicting 'redis_client' and positional argument provided")
            redis_client = url_or_client

        if url is not None and redis_client is not None:
            raise ValueError("Specify either 'redis_client' or 'url', not both.")

        # Key prefix resolution
        if key_prefix is not None:
            prefix = key_prefix
        self._prefix = prefix

        # Key / session ID resolution
        if session_id is not None:
            key = session_id
        self._key = key

        # TTL / Expiration resolution
        if expiration is not None:
            if ttl is not None and ttl != expiration:
                raise ValueError("Conflicting 'ttl' and 'expiration' provided")
            ttl = expiration

        self._ttl = ttl
        if ttl is not None:
            if isinstance(ttl, timedelta):
                seconds = int(ttl.total_seconds())
            elif isinstance(ttl, (int, float)):
                seconds = int(ttl)
            else:
                raise TypeError("TTL must be an int, float, timedelta, or None")
            if seconds <= 0:
                raise ValueError("TTL must be greater than zero")
            self._ttl_seconds: int | None = seconds
        else:
            self._ttl_seconds = None

        # Client resolution
        if redis_client is not None:
            if not (
                callable(getattr(redis_client, "get", None))
                and callable(getattr(redis_client, "set", None))
                and callable(getattr(redis_client, "delete", None))
            ):
                raise TypeError("redis_client must implement 'get', 'set', and 'delete' methods")
            self._client = redis_client
        else:
            try:
                import redis
            except ImportError as error:
                raise ImportError(
                    "The 'redis' package is required to use RedisStorage. "
                    "Please install 'redis' or install via 'baridimob[redis]'."
                ) from error
            target_url = url or "redis://localhost:6379/0"
            self._client = redis.Redis.from_url(target_url)

    @property
    def key(self) -> str:
        """The full Redis key used to store the session."""
        if self._key:
            return f"{self._prefix}{self._key}"
        return self._prefix

    @property
    def prefix(self) -> str:
        """The key prefix configured for this storage."""
        return self._prefix

    @property
    def ttl(self) -> float | timedelta | None:
        """The configured TTL / expiration duration."""
        return self._ttl

    @property
    def client(self) -> Any:
        """The underlying Redis client."""
        return self._client

    def load(self) -> StoredSession | None:
        """Load and deserialize stored session from Redis.

        Returns:
            The StoredSession if present in Redis, or None if the key does not exist.

        Raises:
            ValueError: If the data in Redis is corrupted or invalid.
        """
        raw_data = self._client.get(self.key)
        if raw_data is None:
            return None
        try:
            raw = json.loads(raw_data)
            return _session_from_dict(raw)
        except (json.JSONDecodeError, KeyError, TypeError, ValueError) as error:
            raise ValueError(f"Corrupted session in Redis key: {self.key}") from error

    def save(self, session: StoredSession) -> None:
        """Serialize and save the session to Redis with configured TTL."""
        payload = _session_to_dict(session)
        text = json.dumps(payload, ensure_ascii=False)
        if self._ttl_seconds is not None:
            self._client.set(self.key, text, ex=self._ttl_seconds)
        else:
            self._client.set(self.key, text)

    def clear(self) -> None:
        """Delete the session key from Redis."""
        self._client.delete(self.key)

    def close(self) -> None:
        """Close the Redis client connection if supported."""
        if hasattr(self._client, "close") and callable(self._client.close):
            self._client.close()

    def __enter__(self) -> Self:
        return self

    def __exit__(self, *args: object) -> None:
        self.close()

    def __repr__(self) -> str:
        return f"RedisStorage(key={self.key!r}, ttl={self._ttl!r})"


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
