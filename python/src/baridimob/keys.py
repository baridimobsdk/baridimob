from __future__ import annotations

import hashlib
import uuid
from dataclasses import dataclass

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa


DEVKEY_ALGORITHM = "RSA 2048"
DEVKEY_ALGORITHM_HASH = "2irTxfGZWzVtenv242nedCNNC9k3M64egLmFRV8V4tk="


@dataclass
class DeviceKeys:
    devid: str
    private_key_pem: str
    devkey: str
    devkey_algorithm: str
    devkey_algorithm_hash: str


def algorithm_hash(algorithm: str) -> str:
    import base64

    return base64.b64encode(hashlib.sha256(algorithm.encode("utf-8")).digest()).decode("ascii")


def sha256_hex(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def derive_devkey(public_key_pem: str) -> str:
    public_key = serialization.load_pem_public_key(public_key_pem.encode("utf-8"))
    der = public_key.public_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    start = 24 if len(der) > 100 else 20
    return der[start:].hex()


def generate_device_keys(bits: int = 2048) -> DeviceKeys:
    private_key = rsa.generate_private_key(public_exponent=65537, key_size=bits)
    private_pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    ).decode("utf-8")
    public_pem = private_key.public_key().public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    ).decode("utf-8")
    devkey_algorithm = "RSA 2048" if bits == 2048 else "RSA 512"
    return DeviceKeys(
        devid=str(uuid.uuid4()),
        private_key_pem=private_pem,
        devkey=derive_devkey(public_pem),
        devkey_algorithm=devkey_algorithm,
        devkey_algorithm_hash=algorithm_hash(devkey_algorithm),
    )
