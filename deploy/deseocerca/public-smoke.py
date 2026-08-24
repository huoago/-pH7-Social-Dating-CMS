#!/usr/bin/env python3
"""Public HTTPS acceptance checks for DeseoCerca staging/production."""

from __future__ import annotations

import argparse
import ssl
import sys
import unicodedata
from html.parser import HTMLParser
from urllib.error import HTTPError, URLError
from urllib.parse import urljoin, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener


class LinkParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.links: list[tuple[str, str]] = []
        self._href: str | None = None
        self._text: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag.lower() != "a" or self._href is not None:
            return
        href = dict(attrs).get("href")
        if href:
            self._href = href
            self._text = []

    def handle_data(self, data: str) -> None:
        if self._href is not None:
            self._text.append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag.lower() == "a" and self._href is not None:
            self.links.append((self._href, " ".join(self._text)))
            self._href = None
            self._text = []


def normalized(value: str) -> str:
    folded = unicodedata.normalize("NFKD", value)
    return " ".join("".join(ch for ch in folded if not unicodedata.combining(ch)).casefold().split())


def get(url: str, timeout: float = 15.0) -> tuple[int, str, dict[str, str], str]:
    request = Request(
        url,
        headers={
            "User-Agent": "DeseoCerca-Release-Gate/1.0",
            "Accept": "text/html,application/xhtml+xml",
        },
    )
    opener = build_opener(HTTPRedirectHandler())
    with opener.open(request, timeout=timeout, context=ssl.create_default_context()) as response:  # type: ignore[arg-type]
        raw = response.read(2_000_000)
        charset = response.headers.get_content_charset() or "utf-8"
        body = raw.decode(charset, errors="replace")
        headers = {key.lower(): value for key, value in response.headers.items()}
        return int(response.status), response.geturl(), headers, body


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("host", help="Public DNS hostname without a path")
    args = parser.parse_args()

    host = args.host.strip().rstrip(".")
    if not host or any(ch not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-" for ch in host):
        print("FAIL  invalid hostname", file=sys.stderr)
        return 1

    failures = 0

    def passed(message: str) -> None:
        print(f"PASS  {message}")

    def failed(message: str) -> None:
        nonlocal failures
        failures += 1
        print(f"FAIL  {message}")

    https_root = f"https://{host}/"
    try:
        status, final_url, headers, body = get(https_root)
        if status == 200 and urlsplit(final_url).scheme == "https":
            passed(f"HTTPS root responds: {final_url}")
        else:
            failed(f"unexpected HTTPS root response: status={status} final={final_url}")
    except (HTTPError, URLError, TimeoutError, ssl.SSLError) as exc:
        failed(f"HTTPS root request failed: {exc}")
        return 1

    body_normalized = normalized(body)
    if "mayores de 18" in body_normalized or "18+" in body_normalized:
        passed("visible 18+ notice found")
    else:
        failed("visible 18+ notice not found on the public root page")

    for marker in ("fatal error", "uncaught exception", "stack trace", "warning: require", "warning: include"):
        if marker in body_normalized:
            failed(f"public root contains application error marker: {marker}")

    parser_html = LinkParser()
    parser_html.feed(body)
    required_links = {
        "contacto y seguridad": "contact",
        "terminos de uso": "terms",
        "privacidad": "privacy",
        "aviso legal": "legal notice",
    }

    parsed_root = urlsplit(https_root)
    for label, description in required_links.items():
        href = None
        for candidate_href, candidate_text in parser_html.links:
            if normalized(candidate_text) == label:
                href = candidate_href
                break
        if href is None:
            failed(f"missing footer link: {description}")
            continue

        absolute = urljoin(https_root, href)
        parsed = urlsplit(absolute)
        if parsed.scheme != "https" or parsed.hostname != parsed_root.hostname:
            failed(f"{description} link leaves the expected HTTPS origin: {absolute}")
            continue

        try:
            page_status, page_final, _, page_body = get(absolute)
            if page_status != 200 or len(page_body.strip()) < 200:
                failed(f"{description} page is not healthy: status={page_status} bytes={len(page_body)}")
            elif urlsplit(page_final).scheme != "https":
                failed(f"{description} page left HTTPS: {page_final}")
            else:
                page_norm = normalized(page_body)
                if any(marker in page_norm for marker in ("fatal error", "uncaught exception", "stack trace")):
                    failed(f"{description} page contains an application error")
                else:
                    passed(f"public page responds: {description}")
        except (HTTPError, URLError, TimeoutError, ssl.SSLError) as exc:
            failed(f"{description} page request failed: {exc}")

    try:
        _, http_final, _, _ = get(f"http://{host}/")
        if urlsplit(http_final).scheme == "https":
            passed("HTTP redirects to HTTPS")
        else:
            failed(f"HTTP did not redirect to HTTPS: {http_final}")
    except (HTTPError, URLError, TimeoutError, ssl.SSLError) as exc:
        failed(f"HTTP redirect check failed: {exc}")

    install_url = f"https://{host}/_install/"
    try:
        install_status, install_final, _, install_body = get(install_url)
        install_norm = normalized(install_body)
        if install_status == 200 and ("installer" in install_norm or "install_access_token" in install_norm):
            failed("installer is publicly reachable after installation")
        else:
            failed(f"/_install/ unexpectedly returned status {install_status} ({install_final})")
    except HTTPError as exc:
        if exc.code in (403, 404, 410):
            passed(f"installer is unavailable publicly (HTTP {exc.code})")
        else:
            failed(f"installer path returned unexpected HTTP {exc.code}")
    except (URLError, TimeoutError, ssl.SSLError) as exc:
        failed(f"installer lock check failed: {exc}")

    hsts = headers.get("strict-transport-security", "")
    if hsts:
        passed("Strict-Transport-Security header present")
    else:
        print("WARN  Strict-Transport-Security header not present")

    print(f"\nPublic smoke summary: failures={failures}")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
