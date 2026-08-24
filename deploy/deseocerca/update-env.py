#!/usr/bin/env python3
"""Safely update non-database values in the DeseoCerca Compose .env.

Reads a small JSON object from stdin. Database credentials already present in the
file are preserved, so GitHub Actions never needs to retrieve or rewrite them.
"""

from __future__ import annotations

import json
import os
import pathlib
import sys
import tempfile

ALLOWED_KEYS = {"STAGING_SITE_ADDRESS", "PH7_MAILER_DSN"}
REQUIRED_DATABASE_KEYS = {
    "MYSQL_DATABASE",
    "MYSQL_USER",
    "MYSQL_PASSWORD",
    "MYSQL_ROOT_PASSWORD",
}


def fail(message: str) -> "NoReturn":
    print(message, file=sys.stderr)
    raise SystemExit(1)


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
        if "\n" in value or "\r" in value:
            fail(f"{key} must not contain CR/LF characters.")
        updates[key] = value

    lines = env_path.read_text(encoding="utf-8").splitlines()
    current: dict[str, str] = {}
    for line in lines:
        if not line or line.lstrip().startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        current[key] = value

    missing_database_keys = sorted(REQUIRED_DATABASE_KEYS - current.keys())
    if missing_database_keys:
        fail(
            "Environment file is missing database keys: "
            + ", ".join(missing_database_keys)
        )

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

    mode = env_path.stat().st_mode & 0o777
    fd, temp_name = tempfile.mkstemp(prefix=".deseocerca-env-", dir=env_path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
            handle.write("\n".join(output) + "\n")
        os.chmod(temp_name, 0o600)
        os.replace(temp_name, env_path)
    finally:
        if os.path.exists(temp_name):
            os.unlink(temp_name)

    # Never weaken a previously protected file.
    if mode != 0o600:
        os.chmod(env_path, 0o600)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
