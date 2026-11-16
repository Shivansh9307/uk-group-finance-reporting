"""A small polite HTTP client: one request per interval, retries with backoff, streamed downloads."""

from __future__ import annotations

import hashlib
import time
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

import httpx

RETRY_STATUS = {429, 500, 502, 503, 504}
DEAD_STATUS = {404, 410}
CHUNK = 1 << 20


class FetchError(RuntimeError):
    pass


@dataclass
class Download:
    status: int
    bytes: int = 0
    sha256: str = ""
    content_type: str = ""


class Client:
    def __init__(
        self,
        user_agent: str,
        min_interval: float = 1.0,
        retries: int = 5,
        backoff: float = 2.0,
        transport: httpx.BaseTransport | None = None,
        sleep: Callable[[float], None] = time.sleep,
        clock: Callable[[], float] = time.monotonic,
    ):
        self._http = httpx.Client(
            headers={"User-Agent": user_agent},
            follow_redirects=True,
            timeout=httpx.Timeout(60.0, connect=20.0),
            transport=transport,
        )
        self.min_interval = min_interval
        self.retries = retries
        self.backoff = backoff
        self._sleep = sleep
        self._clock = clock
        self._last = -1e9
        self.requests = 0

    def close(self) -> None:
        self._http.close()

    def _pace(self) -> None:
        wait = self._last + self.min_interval - self._clock()
        if wait > 0:
            self._sleep(wait)
        self._last = self._clock()
        self.requests += 1

    def _retry_wait(self, attempt: int, resp: httpx.Response | None) -> float:
        if resp is not None:
            ra = resp.headers.get("Retry-After")
            if ra and ra.isdigit():
                return float(ra)
        return self.backoff * (2**attempt)

    def _send(self, method: str, url: str, stream: bool = False) -> httpx.Response:
        last_exc: Exception | None = None
        for attempt in range(self.retries + 1):
            self._pace()
            try:
                req = self._http.build_request(method, url)
                resp = self._http.send(req, stream=stream)
            except httpx.TransportError as e:
                last_exc = e
                if attempt == self.retries:
                    break
                self._sleep(self._retry_wait(attempt, None))
                continue
            if resp.status_code in RETRY_STATUS and attempt < self.retries:
                wait = self._retry_wait(attempt, resp)
                resp.close()
                self._sleep(wait)
                continue
            return resp
        raise FetchError(f"{method} {url} failed after {self.retries + 1} attempts: {last_exc}")

    def get_json(self, url: str) -> tuple[int, dict | None]:
        resp = self._send("GET", url)
        if resp.status_code != 200:
            return resp.status_code, None
        return 200, resp.json()

    def get_text(self, url: str) -> tuple[int, str]:
        resp = self._send("GET", url)
        return resp.status_code, resp.text if resp.status_code == 200 else ""

    def head(self, url: str) -> tuple[int, int | None]:
        resp = self._send("HEAD", url)
        resp.close()
        if resp.status_code in (403, 405, 501):
            # Some servers refuse HEAD; open a GET and close it before reading the body.
            resp = self._send("GET", url, stream=True)
            resp.close()
        size = resp.headers.get("Content-Length")
        return resp.status_code, int(size) if size and size.isdigit() else None

    def download(self, url: str, dest: Path) -> Download:
        """Stream `url` to `dest` (written as dest.part, then renamed). Returns status and sha256."""
        resp = self._send("GET", url, stream=True)
        try:
            if resp.status_code != 200:
                return Download(status=resp.status_code)
            dest.parent.mkdir(parents=True, exist_ok=True)
            part = dest.with_name(dest.name + ".part")
            h = hashlib.sha256()
            n = 0
            with open(part, "wb") as f:
                for chunk in resp.iter_bytes(CHUNK):
                    f.write(chunk)
                    h.update(chunk)
                    n += len(chunk)
            expected = resp.headers.get("Content-Length")
            if expected and expected.isdigit() and int(expected) != n and "content-encoding" not in resp.headers:
                part.unlink(missing_ok=True)
                raise FetchError(f"{url}: got {n} bytes, Content-Length said {expected}")
            return Download(
                status=200,
                bytes=n,
                sha256=h.hexdigest(),
                content_type=resp.headers.get("Content-Type", "").split(";")[0].strip(),
            )
        finally:
            resp.close()


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(CHUNK), b""):
            h.update(chunk)
    return h.hexdigest()
