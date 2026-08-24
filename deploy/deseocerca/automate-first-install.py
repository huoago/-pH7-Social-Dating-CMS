#!/usr/bin/env python3
"""Complete the one-time pH7 web installer without exposing credentials in logs."""

from __future__ import annotations

import http.cookiejar
import os
import re
import secrets
import sys
import urllib.error
import urllib.parse
import urllib.request
from html.parser import HTMLParser
from pathlib import Path

REMOTE_DIR = Path(os.environ.get("DESEOCERCA_DIR", "/opt/deseocerca-staging"))
ENV_FILE = Path(os.environ.get("DESEOCERCA_ENV_FILE", REMOTE_DIR / ".env"))
INSTALL_INFO = Path(os.environ.get("DESEOCERCA_FIRST_INSTALL_FILE", "/root/deseocerca-first-install.txt"))
ADMIN_CREDENTIALS = Path(os.environ.get("DESEOCERCA_ADMIN_CREDENTIALS_FILE", "/root/deseocerca-admin-credentials"))


class FormParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.forms: list[dict[str, object]] = []
        self._current: dict[str, object] | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attrs_map = {k: (v or "") for k, v in attrs}
        if tag.lower() == "form":
            self._current = {"action": attrs_map.get("action", ""), "inputs": {}}
            self.forms.append(self._current)
        elif tag.lower() == "input" and self._current is not None:
            name = attrs_map.get("name", "")
            if name:
                inputs = self._current["inputs"]
                assert isinstance(inputs, dict)
                inputs[name] = attrs_map.get("value", "")

    def handle_endtag(self, tag: str) -> None:
        if tag.lower() == "form":
            self._current = None


def fail(message: str) -> "NoReturn":
    print(message, file=sys.stderr)
    raise SystemExit(1)


def read_key_values(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        if "=" not in raw or raw.lstrip().startswith("#"):
            continue
        key, value = raw.split("=", 1)
        if re.fullmatch(r"[A-Z0-9_]+", key):
            values[key] = value
    return values


def read_env() -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in ENV_FILE.read_text(encoding="utf-8").splitlines():
        if not raw or raw.lstrip().startswith("#") or "=" not in raw:
            continue
        key, value = raw.split("=", 1)
        values[key] = value
    return values


def parse_form(html: str, expected_field: str) -> tuple[str, dict[str, str]]:
    parser = FormParser()
    parser.feed(html)
    for form in parser.forms:
        inputs = form.get("inputs")
        if isinstance(inputs, dict) and expected_field in inputs:
            action = form.get("action")
            return str(action or ""), {str(k): str(v) for k, v in inputs.items()}
    fail(f"Installer form containing '{expected_field}' was not found.")


def main() -> int:
    if os.geteuid() != 0:
        fail("Run automated installer as root through root-ops.sh.")
    for required in (ENV_FILE, INSTALL_INFO):
        if not required.is_file():
            fail(f"Missing installer input: {required}")

    env = read_env()
    canonical_host = env.get("PH7_CANONICAL_HOST", "").strip()
    canonical_scheme = env.get("PH7_CANONICAL_SCHEME", "https").strip().lower()
    if canonical_scheme not in {"http", "https"}:
        fail("PH7_CANONICAL_SCHEME is invalid.")
    if not canonical_host or re.fullmatch(r"[A-Za-z0-9.-]+(?::[0-9]{1,5})?", canonical_host) is None:
        fail("PH7_CANONICAL_HOST must be configured before automatic installation.")

    info = read_key_values(INSTALL_INFO)
    required_info = {
        "INSTALL_ACCESS_TOKEN",
        "DB_HOST",
        "DB_PORT",
        "DB_NAME",
        "DB_USER",
        "DB_PASSWORD",
        "DB_PREFIX",
        "PROTECTED_PATH",
    }
    missing = sorted(required_info - info.keys())
    if missing:
        fail("First-install file is missing: " + ", ".join(missing))

    admin_email = os.environ.get("DESEOCERCA_ADMIN_EMAIL", "admin@deseocerca.com").strip()
    if re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", admin_email) is None:
        fail("DESEOCERCA_ADMIN_EMAIL is invalid.")
    admin_username = "dcadmin"
    admin_password = "Dc9!" + secrets.token_urlsafe(28)

    base = f"{canonical_scheme}://{canonical_host}/"
    installer = urllib.parse.urljoin(base, "_install/")
    cookie_jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cookie_jar))

    def request(url: str, fields: dict[str, str] | None = None) -> tuple[str, str]:
        data = None if fields is None else urllib.parse.urlencode(fields).encode("utf-8")
        req = urllib.request.Request(url, data=data, headers={"User-Agent": "DeseoCerca-Installer/1.0"})
        try:
            with opener.open(req, timeout=30) as response:
                body = response.read().decode("utf-8", errors="replace")
                return response.geturl(), body
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            fail(f"Installer HTTP {exc.code} at {url}: {re.sub(r'<[^>]+>', ' ', body)[:300]}")
        except urllib.error.URLError as exc:
            fail(f"Installer request failed at {url}: {exc.reason}")

    def get_action(action: str, expected_field: str) -> tuple[str, str, dict[str, str]]:
        candidates = [urllib.parse.urljoin(installer, action), installer + "?a=" + urllib.parse.quote(action)]
        errors: list[str] = []
        for url in candidates:
            try:
                final_url, html = request(url)
                form_action, defaults = parse_form(html, expected_field)
                return final_url, form_action, defaults
            except SystemExit as exc:
                errors.append(str(exc))
        fail(f"Unable to open installer action {action}: {'; '.join(errors)}")

    def post_form(page_url: str, action: str, defaults: dict[str, str], fields: dict[str, str]) -> tuple[str, str]:
        token = defaults.get("action_token", "")
        if not re.fullmatch(r"[a-f0-9]{64}", token):
            fail("Installer CSRF action token is missing or invalid.")
        payload = {"action_token": token, **fields}
        target = urllib.parse.urljoin(page_url, action) if action else page_url
        return request(target, payload)

    # Authenticate the protected installer.
    index_url, index_html = request(installer)
    action, defaults = parse_form(index_html, "install_access_token")
    post_form(index_url, action, defaults, {
        "install_access_token": info["INSTALL_ACCESS_TOKEN"],
        "install_access_submit": "1",
    })

    # License acknowledgement.
    page_url, action, defaults = get_action("license", "license_agreed")
    post_form(page_url, action, defaults, {
        "license_agreed": "1",
        "conform_laws_agreed": "1",
        "responsibilities_agreed": "1",
        "license_agreements_submit": "1",
    })

    # Protected path.
    page_url, action, defaults = get_action("config_path", "path_protected")
    post_form(page_url, action, defaults, {"path_protected": info["PROTECTED_PATH"]})

    # TiDB is intentionally presented to pH7 as a local MySQL-compatible
    # endpoint through the verified db-tls proxy.
    page_url, action, defaults = get_action("config_system", "db_hostname")
    post_form(page_url, action, defaults, {
        "db_hostname": info["DB_HOST"],
        "db_username": info["DB_USER"],
        "db_password": info["DB_PASSWORD"],
        "db_name": info["DB_NAME"],
        "db_prefix": info["DB_PREFIX"],
        "db_port": info["DB_PORT"],
        "ffmpeg_path": "",
        "bug_report_email": admin_email,
        "config_system_submit": "1",
    })

    # Initial administrator. Do not create sample users in production data.
    page_url, action, defaults = get_action("config_site", "site_name")
    post_form(page_url, action, defaults, {
        "site_name": "DeseoCerca",
        "admin_username": admin_username,
        "admin_login_email": admin_email,
        "admin_password": admin_password,
        "admin_passwords": admin_password,
        "admin_first_name": "Site",
        "admin_last_name": "Admin",
        "admin_email": admin_email,
        "admin_feedback_email": admin_email,
        "admin_return_email": admin_email,
        "config_site_submit": "1",
    })

    # Keep the neutral base niche; DeseoCerca's guarded bootstrap applies the
    # product-specific settings afterwards.
    page_url, action, defaults = get_action("niche", "niche_submit")
    post_form(page_url, action, defaults, {"niche_submit": "base"})

    # Remove the web installer once installation has fully completed.
    page_url, action, defaults = get_action("finish", "confirm_remove_install")
    post_form(page_url, action, defaults, {"confirm_remove_install": "1"})

    credentials = "\n".join([
        "service=DeseoCerca",
        f"admin_url={base}admin123",
        f"admin_email={admin_email}",
        f"admin_username={admin_username}",
        f"admin_password={admin_password}",
        "",
    ])
    ADMIN_CREDENTIALS.write_text(credentials, encoding="utf-8")
    os.chmod(ADMIN_CREDENTIALS, 0o600)

    # Never print the generated password to CI logs.
    print(f"pH7 first installation completed for {canonical_host}.")
    print(f"Administrator credentials stored root-only at {ADMIN_CREDENTIALS}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
