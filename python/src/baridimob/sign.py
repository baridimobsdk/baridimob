from __future__ import annotations

import json
from typing import Any
from urllib.parse import urlencode

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding

INITIAL_STAMP = "00000000000000000000"


def _rsa_sha1_hex(payload: str, private_key_pem: str) -> str:
    private_key = serialization.load_pem_private_key(
        private_key_pem.encode("utf-8"),
        password=None,
    )
    signature = private_key.sign(payload.encode("utf-8"), padding.PKCS1v15(), hashes.SHA1())
    return signature.hex()


def sign_params(params: dict[str, str], private_key_pem: str) -> str:
    with_placeholder = {**params, "stamp": INITIAL_STAMP}
    unsigned = urlencode(with_placeholder)
    signature = _rsa_sha1_hex(unsigned, private_key_pem)
    return unsigned.replace(f"stamp={INITIAL_STAMP}", f"stamp={signature}", 1)


def sign_json_body(body: dict[str, Any], private_key_pem: str) -> str:
    with_placeholder = {**body, "stamp": INITIAL_STAMP}
    unsigned = json.dumps(with_placeholder, separators=(",", ":"), ensure_ascii=False)
    signature = _rsa_sha1_hex(unsigned, private_key_pem)
    marker = f'"stamp":"{INITIAL_STAMP}"'
    return unsigned.replace(marker, f'"stamp":"{signature}"', 1)
