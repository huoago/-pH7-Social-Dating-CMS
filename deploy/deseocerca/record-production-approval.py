#!/usr/bin/env python3
"""Record one explicit DeseoCerca production approval for the deployed release."""

from __future__ import annotations

import json
import os
import re
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path

MARKERS = {
    "legal": Path("/root/deseocerca-legal-approved"),
    "e2e": Path("/root/deseocerca-e2e-approved"),
    "restore-drill": Path("/root/deseocerca-restore-drill-approved"),
    "offsite-backup": Path("/root/deseocerca-offsite-backup-approved"),
}


def clean_text(value: object, name: str, minimum: int, maximum: int) -> str:
    if not isinstance(value, str):
        raise ValueError(f"{name} must be a string")
    value = value.strip()
    if not minimum <= len(value) <= maximum:
        raise ValueError(f"{name} must contain {minimum}-{maximum} characters")
    if "\r" in value or "\n" in value or "\x00" in value:
        raise ValueError(f"{name} must be one line")
    return value


def main() -> int:
    if os.geteuid() != 0:
        raise SystemExit("Run as root.")

    payload = json.load(__import__("sys").stdin)
    approval_type = clean_text(payload.get("approval_type"), "approval_type", 3, 32)
    approved_by = clean_text(payload.get("approved_by"), "approved_by", 2, 200)
    evidence = clean_text(payload.get("evidence"), "evidence", 5, 1000)

    marker = MARKERS.get(approval_type)
    if marker is None:
        raise SystemExit("Unsupported approval_type.")

    remote_dir = os.environ.get("DESEOCERCA_DIR", "/opt/deseocerca-staging")
    result = subprocess.run(
        ["git", "-C", remote_dir, "rev-parse", "HEAD"],
        check=True,
        capture_output=True,
        text=True,
    )
    release_sha = result.stdout.strip()
    if re.fullmatch(r"[a-f0-9]{40}", release_sha) is None:
        raise SystemExit("Could not resolve an exact deployed release SHA.")

    content = "\n".join(
        [
            "service=DeseoCerca",
            f"approval_type={approval_type}",
            f"release_sha={release_sha}",
            f"approved_at_utc={datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}",
            f"approved_by={approved_by}",
            f"evidence={evidence}",
            "",
        ]
    )

    marker.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        "w",
        encoding="utf-8",
        dir=str(marker.parent),
        prefix=f".{marker.name}.",
        delete=False,
    ) as handle:
        tmp_path = Path(handle.name)
        handle.write(content)
        handle.flush()
        os.fsync(handle.fileno())

    os.chmod(tmp_path, 0o600)
    os.replace(tmp_path, marker)
    print(f"Recorded {approval_type} approval for release {release_sha}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
