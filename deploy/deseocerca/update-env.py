#!/usr/bin/env python3
"""Safely update DeseoCerca deployment environment values.

The updater accepts only an explicit allow-list, never sources shell input, and
supports either the legacy local-MySQL stack or the Google Free Tier + TiDB
stack. Existing secrets that are not part of the supplied overlay are preserved.
"""

from __future__ import annotations

import json
import os
import pathlib
import re
import sys
import tempfile
from typing import NoReturn

ALLOWED_KEYS = {
    "STAGING_SITE_ADDRESS",
    "PH7_MAILER_DSN",
    "PH7_CANONICAL_HOST",
    "PH7_CANONICAL_SCHEME",
    "DESEOCERCA_APP_IMAGE",
    "TIDB_HOST",
    "TIDB_USERNAME",
    "TIDB_PASSWORD",
    "TIDB_DATABASE",
}
LOCAL_MYSQL_KEYS = {
    "MYSQL_DATABASE",
    "MYSQL_USER",
    "MYSQL_PASSWORD",
    "MYSQL_ROOT_PASSWORD",
}
TIDB_KEYS = {
    "TIDB_HOST",
    "TIDB_USERNAME",
    "TIDB_PASSWORD",
    "TIDB_DATABASE",
}
HOST_RE = re.compile(r"^(?:[A-Za-z0-9](?:[A-Za-z0-9.-]{0,253}[A-Za-z0-9])?|\[[0-9A-Fa-f:.]+\])(?::[0-9]{1,5})?$")


def fail(message: str) -> NoReturn:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def validate_value(key: str, value: str) -> None:
    if "\n" in value or "\r" in value or "\x00" in value:
        fail(f"{key} must not contain CR/LF/NUL characters.")
    if key == "PH7_CANONICAL_SCHEME" and value not in {"http", "https"}:
        fail("PH7_CANONICAL_SCHEME must be http or https.")
    if key == "PH7_CANONICAL_HOST" and value and HOST_RE.fullmatch(value) is None:
        fail("PH7_CANONICAL_HOST is invalid.")
    if key == "TIDB_HOST" and value and re.fullmatch(r"[A-Za-z0-9.-]{1,255}", value) is None:
        fail("TIDB_HOST is invalid.")
    if key == "TIDB_DATABASE" and value and re.fullmatch(r"[A-Za-z0-9_$-]{1,64}", value) is None:
        fail("TIDB_DATABASE is invalid.")
    if key == "DESEOCERCA_APP_IMAGE" and value and re.fullmatch(r"[A-Za-z0-9._/:@-]{1,255}", value) is None:
        fail("DESEOCERCA_APP_IMAGE is invalid.")


def main() -> int:
    if len(sys.argv) != 2:
        fail("Usage: update-env.py /path/to/.env")

    env_path = pathlib.Path(sys.argv[1])
    if not env_path.is_file():
        fail(f"Missing environment file: {env_path}")

    payload = json.load(sys.stdin)
    if not isinstance(payload, dict):
        fail("Environment overlay must be a JSON object.")

    unknown = set(payload) - ALLOWED_KEYS
    if unknown:
        fail(f"Unsupported environment keys: {', '.join(sorted(unknown))}")

    updates: dict[str, str] = {}
    for key, value in payload.items():
        if not isinstance(value, str):
            fail(f"{key} must be a string.")
        validate_value(key, value)
        updates[key] = value

    lines = env_path.read_text(encoding="utf-8").splitlines()
    current: dict[str, str] = {}
    for line in lines:
        if not line or line.lstrip().startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        current[key] = value

    has_local_mysql = LOCAL_MYSQL_KEYS.issubset(current)
    has_tidb = TIDB_KEYS.issubset(current)
    if not has_local_mysql and not has_tidb:
        fail("Environment file does not contain a supported database backend definition.")

    # TiDB credentials may only be changed in a file that was explicitly
    # bootstrapped for TiDB. This prevents converting a production MySQL stack
    # into an external database stack through an overlay alone.
    if set(updates) & TIDB_KEYS and not has_tidb:
        fail("TiDB values cannot be written to a non-TiDB environment file.")

    output: list[str] = []
    replaced: set[str] = set()
    for line in lines:
        if "=" not in line or line.lstrip().startswith("#"):
            output.append(line)
            continue
        key, _ = line.split("=", 1)
        if key in updates:
            output.append(f"{key}={updates[key]}")
            replaced.add(key)
        else:
            output.append(line)

    for key in sorted(updates.keys() - replaced):
        output.append(f"{key}={updates[key]}")

    fd, temp_name = tempfile.mkstemp(prefix=".deseocerca-env-", dir=env_path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
            handle.write("\n".join(output) + "\n")
        os.chmod(temp_name, 0o600)
        os.replace(temp_name, env_path)
    finally:
        if os.path.exists(temp_name):
            os.unlink(temp_name)

    os.chmod(env_path, 0o600)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
