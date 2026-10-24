from __future__ import annotations

import json
from datetime import timedelta
from unittest.mock import MagicMock, patch

import fakeredis
import pytest

from baridimob import (
    Config,
    RedisStorage,
    SessionStorage,
    StoredSession,
    create_client,
    generate_device_keys,
)


@pytest.fixture
def fake_client() -> fakeredis.FakeRedis:
    """Provide an isolated in-memory Redis client for testing."""
    return fakeredis.FakeRedis(decode_responses=True)


@pytest.fixture
def fake_binary_client() -> fakeredis.FakeRedis:
    """Provide a Redis client that returns bytes (decode_responses=False)."""
    return fakeredis.FakeRedis(decode_responses=False)


@pytest.fixture
def sample_session() -> StoredSession:
    """Provide a valid StoredSession instance with real cryptographic keys."""
    keys = generate_device_keys()
    return StoredSession(
        version=1,
        devid=keys.devid,
        private_key_pem=keys.private_key_pem,
        devkey=keys.devkey,
        devkey_algorithm=keys.devkey_algorithm,
        cookies={"SESSIONID": "xyz123", "ROUTEID": ".node1"},
        locale="ar",
        account="000123456789",
    )


class TestRedisStorageBasic:
    def test_implements_session_storage_protocol(self, fake_client: fakeredis.FakeRedis) -> None:
        storage = RedisStorage(redis_client=fake_client)
        assert isinstance(storage, SessionStorage)
        assert callable(storage.load)
        assert callable(storage.save)
        assert callable(storage.clear)

    def test_load_empty_returns_none(self, fake_client: fakeredis.FakeRedis) -> None:
        storage = RedisStorage(redis_client=fake_client)
        assert storage.load() is None

    def test_save_and_load_roundtrip(
        self,
        fake_client: fakeredis.FakeRedis,
        sample_session: StoredSession,
    ) -> None:
        storage = RedisStorage(redis_client=fake_client)
        storage.save(sample_session)

        loaded = storage.load()
        assert loaded is not None
        assert loaded.version == sample_session.version
        assert loaded.devid == sample_session.devid
        assert loaded.private_key_pem == sample_session.private_key_pem
        assert loaded.devkey == sample_session.devkey
        assert loaded.devkey_algorithm == sample_session.devkey_algorithm
        assert loaded.cookies == sample_session.cookies
        assert loaded.locale == sample_session.locale
        assert loaded.account == sample_session.account

    def test_save_and_load_with_binary_client(
        self,
        fake_binary_client: fakeredis.FakeRedis,
        sample_session: StoredSession,
    ) -> None:
        storage = RedisStorage(redis_client=fake_binary_client)
        storage.save(sample_session)

        loaded = storage.load()
        assert loaded is not None
        assert loaded.devid == sample_session.devid
        assert loaded.cookies == sample_session.cookies

    def test_clear_deletes_session(
        self,
        fake_client: fakeredis.FakeRedis,
        sample_session: StoredSession,
    ) -> None:
        storage = RedisStorage(redis_client=fake_client)
        storage.save(sample_session)
        assert storage.load() is not None

        storage.clear()
        assert storage.load() is None
        assert not fake_client.exists(storage.key)

    def test_clear_when_key_does_not_exist_is_noop(
        self,
        fake_client: fakeredis.FakeRedis,
    ) -> None:
        storage = RedisStorage(redis_client=fake_client)
        # Should execute cleanly without error
        storage.clear()
        assert storage.load() is None


class TestRedisStorageConfiguration:
    def test_default_key_and_prefix(self, fake_client: fakeredis.FakeRedis) -> None:
        storage = RedisStorage(redis_client=fake_client)
        assert storage.prefix == "baridimob:session:"
        assert storage.key == "baridimob:session:default"

    def test_custom_prefix_and_key(self, fake_client: fakeredis.FakeRedis) -> None:
        storage = RedisStorage(
            redis_client=fake_client,
            prefix="myapp:auth:",
            key="user_42",
        )
        assert storage.prefix == "myapp:auth:"
        assert storage.key == "myapp:auth:user_42"

    def test_aliases_key_prefix_and_session_id(self, fake_client: fakeredis.FakeRedis) -> None:
        storage = RedisStorage(
            redis_client=fake_client,
            key_prefix="custom:baridi:",
            session_id="account_99",
        )
        assert storage.prefix == "custom:baridi:"
        assert storage.key == "custom:baridi:account_99"

    def test_empty_key_resolves_to_prefix(self, fake_client: fakeredis.FakeRedis) -> None:
        storage = RedisStorage(
            redis_client=fake_client,
            prefix="baridimob:standalone",
            key="",
        )
        assert storage.key == "baridimob:standalone"

    def test_positional_client_argument(self, fake_client: fakeredis.FakeRedis) -> None:
        storage = RedisStorage(fake_client)
        assert storage.client is fake_client

    def test_positional_url_argument(self) -> None:
        with patch("redis.Redis.from_url") as mock_from_url:
            mock_from_url.return_value = MagicMock()
            storage = RedisStorage("redis://myhost:6380/2")
            mock_from_url.assert_called_once_with("redis://myhost:6380/2")
            assert storage.prefix == "baridimob:session:"

    def test_conflicting_url_and_client_raises_value_error(
        self,
        fake_client: fakeredis.FakeRedis,
    ) -> None:
        with pytest.raises(ValueError, match="Specify either 'redis_client' or 'url'"):
            RedisStorage("redis://localhost:6379", redis_client=fake_client)

        with pytest.raises(ValueError, match="Specify either 'redis_client' or 'url'"):
            RedisStorage(url="redis://localhost:6379", redis_client=fake_client)

    def test_conflicting_positional_and_keyword_raises_value_error(
        self,
        fake_client: fakeredis.FakeRedis,
    ) -> None:
        other_client = fakeredis.FakeRedis()
        with pytest.raises(ValueError, match="Conflicting 'redis_client'"):
            RedisStorage(fake_client, redis_client=other_client)

        with pytest.raises(ValueError, match="Conflicting 'url'"):
            RedisStorage("redis://localhost:6379/1", url="redis://localhost:6379/2")

    def test_invalid_client_type_raises_type_error(self) -> None:
        invalid_client = object()
        with pytest.raises(TypeError, match="must implement 'get', 'set', and 'delete'"):
            RedisStorage(redis_client=invalid_client)


class TestRedisStorageTTL:
    def test_ttl_int_seconds(
        self,
        fake_client: fakeredis.FakeRedis,
        sample_session: StoredSession,
    ) -> None:
        storage = RedisStorage(redis_client=fake_client, ttl=300)
        storage.save(sample_session)

        ttl = fake_client.ttl(storage.key)
        assert 0 < ttl <= 300
        assert storage.ttl == 300

    def test_ttl_float_seconds(
        self,
        fake_client: fakeredis.FakeRedis,
        sample_session: StoredSession,
    ) -> None:
        storage = RedisStorage(redis_client=fake_client, ttl=120.5)
        storage.save(sample_session)

        ttl = fake_client.ttl(storage.key)
        assert 0 < ttl <= 120

    def test_ttl_timedelta(
        self,
        fake_client: fakeredis.FakeRedis,
        sample_session: StoredSession,
    ) -> None:
        duration = timedelta(hours=2)
        storage = RedisStorage(redis_client=fake_client, ttl=duration)
        storage.save(sample_session)

        ttl = fake_client.ttl(storage.key)
        assert 0 < ttl <= 7200
        assert storage.ttl == duration

    def test_expiration_alias(
        self,
        fake_client: fakeredis.FakeRedis,
        sample_session: StoredSession,
    ) -> None:
        storage = RedisStorage(redis_client=fake_client, expiration=600)
        storage.save(sample_session)

        ttl = fake_client.ttl(storage.key)
        assert 0 < ttl <= 600

    def test_conflicting_ttl_and_expiration_raises_value_error(
        self,
        fake_client: fakeredis.FakeRedis,
    ) -> None:
        with pytest.raises(ValueError, match="Conflicting 'ttl' and 'expiration'"):
            RedisStorage(redis_client=fake_client, ttl=100, expiration=200)

    @pytest.mark.parametrize("invalid_ttl", [0, -10, -0.5, timedelta(seconds=0), timedelta(seconds=-5)])
    def test_non_positive_ttl_raises_value_error(
        self,
        fake_client: fakeredis.FakeRedis,
        invalid_ttl: float | timedelta,
    ) -> None:
        with pytest.raises(ValueError, match="TTL must be greater than zero"):
            RedisStorage(redis_client=fake_client, ttl=invalid_ttl)

    def test_invalid_ttl_type_raises_type_error(self, fake_client: fakeredis.FakeRedis) -> None:
        with pytest.raises(TypeError, match="TTL must be an int, float, timedelta, or None"):
            RedisStorage(redis_client=fake_client, ttl="3600")  # type: ignore[arg-type]


class TestRedisStorageErrorHandlingAndCorruption:
    def test_corrupted_json_raises_value_error(self, fake_client: fakeredis.FakeRedis) -> None:
        storage = RedisStorage(redis_client=fake_client)
        fake_client.set(storage.key, "not a valid {json string")

        with pytest.raises(ValueError, match=f"Corrupted session in Redis key: {storage.key}"):
            storage.load()

    def test_json_array_raises_value_error(self, fake_client: fakeredis.FakeRedis) -> None:
        storage = RedisStorage(redis_client=fake_client)
        fake_client.set(storage.key, json.dumps([1, 2, 3]))

        with pytest.raises(ValueError, match=f"Corrupted session in Redis key: {storage.key}"):
            storage.load()

    def test_missing_devid_raises_value_error(self, fake_client: fakeredis.FakeRedis) -> None:
        storage = RedisStorage(redis_client=fake_client)
        payload = {
            "version": 1,
            "devkey": "key123",
            "privateKeyPem": "pem",
            "devkeyAlgorithm": "RSA",
        }
        fake_client.set(storage.key, json.dumps(payload))

        with pytest.raises(ValueError, match=f"Corrupted session in Redis key: {storage.key}"):
            storage.load()

    def test_missing_private_key_pem_raises_value_error(self, fake_client: fakeredis.FakeRedis) -> None:
        storage = RedisStorage(redis_client=fake_client)
        payload = {
            "version": 1,
            "devid": "id123",
            "devkey": "key123",
            "devkeyAlgorithm": "RSA",
        }
        fake_client.set(storage.key, json.dumps(payload))

        with pytest.raises(ValueError, match=f"Corrupted session in Redis key: {storage.key}"):
            storage.load()

    def test_cross_compatibility_with_snake_and_camel_case(
        self,
        fake_client: fakeredis.FakeRedis,
    ) -> None:
        storage = RedisStorage(redis_client=fake_client)
        # Store using snake_case field names (e.g. from Python dictionary export)
        payload = {
            "version": 2,
            "devid": "dev-snake",
            "private_key_pem": "-----PEM-----",
            "devkey": "dkey",
            "devkey_algorithm": "RSA 2048",
            "cookies": {"foo": "bar"},
            "locale": "fr",
            "account": "987654",
        }
        fake_client.set(storage.key, json.dumps(payload))

        loaded = storage.load()
        assert loaded is not None
        assert loaded.version == 2
        assert loaded.devid == "dev-snake"
        assert loaded.private_key_pem == "-----PEM-----"
        assert loaded.devkey_algorithm == "RSA 2048"
        assert loaded.locale == "fr"
        assert loaded.account == "987654"

    def test_account_none_handled_cleanly(
        self,
        fake_client: fakeredis.FakeRedis,
        sample_session: StoredSession,
    ) -> None:
        sample_session.account = None
        storage = RedisStorage(redis_client=fake_client)
        storage.save(sample_session)

        loaded = storage.load()
        assert loaded is not None
        assert loaded.account is None


class TestRedisStorageOptionalDependency:
    def test_missing_redis_package_raises_informative_import_error(self) -> None:
        with patch.dict("sys.modules", {"redis": None}):
            with pytest.raises(ImportError) as exc_info:
                RedisStorage(url="redis://localhost:6379/0")

            error_message = str(exc_info.value)
            assert "The 'redis' package is required to use RedisStorage" in error_message
            assert "baridimob[redis]" in error_message


class TestRedisStorageContextManagerAndIntegration:
    def test_context_manager_and_close(self, fake_client: fakeredis.FakeRedis) -> None:
        fake_client.close = MagicMock()  # type: ignore[method-assign]
        with RedisStorage(redis_client=fake_client) as storage:
            assert storage.client is fake_client

        fake_client.close.assert_called_once()

    def test_repr_string(self, fake_client: fakeredis.FakeRedis) -> None:
        storage = RedisStorage(redis_client=fake_client, prefix="bm:", key="acc1", ttl=60)
        assert repr(storage) == "RedisStorage(key='bm:acc1', ttl=60)"

    def test_create_client_integration(
        self,
        fake_client: fakeredis.FakeRedis,
        sample_session: StoredSession,
    ) -> None:
        storage = RedisStorage(redis_client=fake_client)
        storage.save(sample_session)

        # BaridiMob client should automatically load the stored session on init
        client = create_client(Config(storage=storage))
        assert client.auth.current_device_id() == sample_session.devid

        # Calling logout should clear the session from Redis
        with patch.object(client, "_request", return_value={}):
            client.auth.logout()
        assert storage.load() is None
        assert client.auth.current_device_id() is None
