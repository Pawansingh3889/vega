"""Encrypting a secret before it reaches the database.

#109 q3. The service holds the key and Postgres never sees it, so the database
holds ciphertext only and a stolen backup is useless on its own. The rejected
alternative was `pgcrypto`, where the key travels inside query text on every
read and write and can land in query logs.

Fernet, from `cryptography`, because it is authenticated encryption with a
sensible default construction. An unauthenticated cipher would let somebody who
can write to the table swap a token's bytes for another's without detection.
"""

from __future__ import annotations

from cryptography.fernet import Fernet, InvalidToken


class SecretBoxError(RuntimeError):
    """The key is missing or malformed, or the ciphertext will not open."""


class SecretBox:
    """Encrypts and decrypts one kind of secret with one key."""

    def __init__(self, key: str) -> None:
        if not key:
            raise SecretBoxError(
                "VEGA_TOKEN_KEY is not set. Generate one with "
                '`python -c "from cryptography.fernet import Fernet; '
                'print(Fernet.generate_key().decode())"` and put it in the '
                "service's environment. There is no default: a default key is "
                "the same as no encryption."
            )
        try:
            self._fernet = Fernet(key.encode())
        except (ValueError, TypeError) as exc:
            raise SecretBoxError(
                "VEGA_TOKEN_KEY is not a valid Fernet key. It must be 32 "
                "url-safe base64-encoded bytes."
            ) from exc

    def seal(self, plaintext: str) -> bytes:
        return self._fernet.encrypt(plaintext.encode())

    def open(self, ciphertext: bytes) -> str:
        """Refuses loudly rather than returning something wrong.

        A failure here means the key changed, the row was tampered with, or the
        ciphertext came from somewhere else. None of those should quietly
        produce a token that is then sent to a tax authority.
        """
        try:
            return self._fernet.decrypt(bytes(ciphertext)).decode()
        except InvalidToken as exc:
            raise SecretBoxError(
                "a stored secret could not be decrypted: the key has changed, "
                "or the stored value is not ours."
            ) from exc
