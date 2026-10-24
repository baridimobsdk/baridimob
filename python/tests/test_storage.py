from __future__ import annotations

import json
from pathlib import Path

import pytest

from baridimob import (
    FileStorage,
    MemoryStorage,
    SessionStorage,
    StoredSession,
)


@pytest.fixture
def sample_session() -> StoredSession:
    return StoredSession(
        version=1,
        devid="test-devid-mem-123",
        private_key_pem="-----BEGIN RSA PRIVATE KEY-----\nMIIE...\n-----END RSA PRIVATE KEY-----\n",
        devkey="test-devkey-xyz",
        devkey_algorithm="RSA 2048",
        cookies={"SESSIONID": "abc"},
        locale="ar",
        account="000123456789",
    )


class TestMemoryStorage:
    def test_implements_protocol(self) -> None:
        storage = MemoryStorage()
        assert isinstance(storage, SessionStorage)

    def test_empty_load(self) -> None:
        storage = MemoryStorage()
        assert storage.load() is None

    def test_save_and_load(self, sample_session: StoredSession) -> None:
        storage = MemoryStorage()
        storage.save(sample_session)

        loaded = storage.load()
        assert loaded is not None
        assert loaded.devid == sample_session.devid

        # Verify deep copy isolation
        loaded.cookies["NEW_COOKIE"] = "val"
        assert "NEW_COOKIE" not in storage.load().cookies

    def test_clear(self, sample_session: StoredSession) -> None:
        storage = MemoryStorage(initial=sample_session)
        assert storage.load() is not None

        storage.clear()
        assert storage.load() is None


class TestFileStorage:
    def test_implements_protocol(self, tmp_path: Path) -> None:
        storage = FileStorage(tmp_path / "session.json")
        assert isinstance(storage, SessionStorage)

    def test_load_non_existent_file(self, tmp_path: Path) -> None:
        storage = FileStorage(tmp_path / "non_existent.json")
        assert storage.load() is None

    def test_save_and_load_roundtrip(self, tmp_path: Path, sample_session: StoredSession) -> None:
        file_path = tmp_path / "subdir" / "session.json"
        storage = FileStorage(file_path)
        storage.save(sample_session)

        assert file_path.exists()
        loaded = storage.load()
        assert loaded is not None
        assert loaded.devid == sample_session.devid
        assert loaded.account == sample_session.account

    def test_clear_deletes_file(self, tmp_path: Path, sample_session: StoredSession) -> None:
        file_path = tmp_path / "session.json"
        storage = FileStorage(file_path)
        storage.save(sample_session)
        assert file_path.exists()

        storage.clear()
        assert not file_path.exists()
        assert storage.load() is None

    def test_clear_non_existent_is_noop(self, tmp_path: Path) -> None:
        storage = FileStorage(tmp_path / "non_existent.json")
        storage.clear()  # should not raise

    def test_corrupted_file_raises_value_error(self, tmp_path: Path) -> None:
        file_path = tmp_path / "bad.json"
        file_path.write_text("invalid json { content", encoding="utf-8")

        storage = FileStorage(file_path)
        with pytest.raises(ValueError, match="Corrupted session file"):
            storage.load()

    def test_corrupted_missing_field_raises_value_error(self, tmp_path: Path) -> None:
        file_path = tmp_path / "incomplete.json"
        file_path.write_text(json.dumps({"version": 1, "foo": "bar"}), encoding="utf-8")

        storage = FileStorage(file_path)
        with pytest.raises(ValueError, match="Corrupted session file"):
            storage.load()
