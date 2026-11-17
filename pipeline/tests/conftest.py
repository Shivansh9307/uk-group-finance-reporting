"""Shared test helpers: a fake web served through httpx.MockTransport (no network is used)."""

from __future__ import annotations

import io
import json
import zipfile
from pathlib import Path

import httpx
import pytest
from dbfixtures import (  # noqa: F401  (fixtures and hooks)
    db,
    db_settings,
    pytest_collection_modifyitems,
    pytest_configure,
    repo_root,
)

from ukfr.config import parse_settings
from ukfr.http import Client

FIXTURES = Path(__file__).parent / "fixtures"
API = "https://www.gov.uk/api/content"
ASSETS = "https://assets.publishing.service.gov.uk/media"


def fixture_json(name: str) -> bytes:
    return (FIXTURES / name).read_bytes()


def zip_bytes(members: dict[str, bytes]) -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        for name, data in members.items():
            z.writestr(name, data)
    return buf.getvalue()


class FakeWeb:
    """URL -> (status, body). Every request is logged as (method, url)."""

    def __init__(self) -> None:
        self.routes: dict[str, tuple[int, bytes]] = {}
        self.calls: list[tuple[str, str]] = []

    def add(self, url: str, body: bytes | str = b"", status: int = 200) -> None:
        self.routes[url] = (status, body.encode() if isinstance(body, str) else body)

    def handler(self, request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        self.calls.append((request.method, url))
        status, body = self.routes.get(url, (404, b'{"error":"not found"}'))
        if request.method == "HEAD":
            return httpx.Response(status, headers={"Content-Length": str(len(body))})
        return httpx.Response(status, content=body)

    def gets(self, fragment: str = "") -> list[str]:
        return [u for m, u in self.calls if m == "GET" and fragment in u]

    def client(self) -> Client:
        return Client("test-agent", min_interval=0, transport=httpx.MockTransport(self.handler), sleep=lambda s: None)


@pytest.fixture
def web() -> FakeWeb:
    w = FakeWeb()
    w.add(API + "/government/collections/hmt-oscar-publishing-from-the-database", fixture_json("collection_oscar.json"))
    w.add(
        API + "/government/publications/oscar-ii-publishing-data-from-the-database-september-2026",
        fixture_json("page_inyear_sep_2026.json"),
    )
    w.add(
        API + "/government/publications/oscar-ii-publishing-data-from-the-database-march-2026",
        fixture_json("page_inyear_mar_2026.json"),
    )
    w.add(
        API + "/government/statistics/oscar-publishing-data-from-the-database-march-2019",
        fixture_json("page_inyear_mar_2019.json"),
    )
    w.add(
        API + "/government/publications/oscar-annual-release-november-2024", fixture_json("page_annual_nov_2024.json")
    )
    # Assets (tiny stand-ins for the real files).
    w.add(
        ASSETS + "/6ab103192f29b3888481876f/OSCAR_in_year_dataset_Sep_2026.csv", "Organisation Code,Amount\r\nA,1\r\n"
    )
    w.add(ASSETS + "/6ab117c0086ce7c57b818785/OSCAR_in_year_dataset_September_2026_.xlsm", b"xlsm")
    w.add(ASSETS + "/6ab101834c0f475de0a66a93/OSCAR_in-year_dataset_guidance.pdf", b"%PDF")
    w.add(ASSETS + "/69bd1090ed813d0d8b690be9/OSCAR_in-year_dataset_guidance.pdf", b"%PDF")
    w.add(ASSETS + "/5c9236bced915d07ae752efb/OSCAR_in-year_dataset_guidance.pdf", b"%PDF")
    w.add(
        "https://www.gov.uk/government/publications/oscar-ii-publishing-data-from-the-database-september-2026"
        "/oscar-in-year-dataset-guidance",
        "<html></html>",
    )
    w.add(ASSETS + "/69bd10a4bbf7c14d0b834dcf/OSCAR_in_year_dataset_March_2026.ods", b"ods-standalone")
    w.add(
        ASSETS + "/69bd10b5ed813d0d8b690bea/OSCAR_in_year_dataset_March_2026.zip",
        zip_bytes({"OSCAR_in_year_dataset_March_2026.ods": b"ods-in-zip"}),
    )
    w.add(ASSETS + "/5c9236d440f0b633f3d4b672/OSCAR_in-year_dataset_21Mar2019.ods", b"ods-2019")
    w.add(
        ASSETS + "/5c9236eded915d07a7e612f2/OSCAR_in-year_dataset_21Mar2019.zip",
        zip_bytes({"OSCAR_in-year_dataset_21Mar2019.csv": b"Organisation Code,Amount\r\nA,2\r\n"}),
    )
    w.add(ASSETS + "/6745b2b683f3d6d843be96c2/BUD_2019-20.xlsx", b"xlsx-bud")
    w.add(ASSETS + "/6745b085e7cf64050b8098b9/Understanding_OSCAR_Data_Release_2024.pdf", b"%PDF-u")
    w.add(ASSETS + "/6745b371bdeffdc82cffe12c/MFO_23-24.zip", b'{"error":"not found"}', status=404)
    return w


SOURCES = {
    "user_agent": "test-agent",
    "min_interval_seconds": 0,
    "commit_limit_mb": 60,
    "sources": [
        {
            "id": "oscar_inyear",
            "title": "in-year",
            "publisher": "HM Treasury",
            "licence": "OGL-3.0",
            "fetch": True,
            "commit": True,
            "prefer_only_if": r"(?i)\.csv$",
            "discover": [
                {
                    "collection": "/government/collections/hmt-oscar-publishing-from-the-database",
                    "group": "In-year data",
                    "release": {
                        "from": "title",
                        "pattern": r"(?P<month>[A-Za-z]+)\s+(?P<year>\d{4})\s*$",
                        "template": "{year}-{month}",
                    },
                    "since": "2019-03",
                }
            ],
            "files": [
                {"match": "(?i)guidance", "action": "catalogue", "note": "release guidance document"},
                {"match": r"(?i)\.(zip|csv)$", "action": "fetch", "tier": 1},
                {"match": r"(?i)\.(ods|xlsm|xlsx)$", "action": "fetch", "tier": 2},
            ],
        },
        {
            "id": "oscar_annual",
            "title": "annual",
            "publisher": "HM Treasury",
            "licence": "OGL-3.0",
            "fetch": True,
            "commit": False,
            "discover": [
                {
                    "page": "/government/publications/oscar-annual-release-november-2024",
                    "release": {
                        "from": "title",
                        "pattern": r"(?P<month>[A-Za-z]+)\s+(?P<year>\d{4})\s*$",
                        "template": "{year}-{month}",
                    },
                }
            ],
            "files": [
                {"match": r"^BUD.*\.xlsx$", "action": "fetch"},
                {"match": r"^MFO_.*\.zip$", "action": "fetch"},
                {"match": r"^Understanding_OSCAR", "action": "catalogue"},
            ],
        },
    ],
}


@pytest.fixture
def repo(tmp_path, monkeypatch):
    """A throwaway repo root with sources.yml, and $UKFR_DATA_DIR pointed inside it."""
    root = tmp_path / "repo"
    (root / "data" / "manifest").mkdir(parents=True)
    (root / "data" / "manifest" / "sources.yml").write_text(json.dumps(SOURCES), encoding="utf-8")
    monkeypatch.setenv("UKFR_DATA_DIR", str(tmp_path / "raw"))
    monkeypatch.delenv("UKFR_REPO_ROOT", raising=False)
    return root


@pytest.fixture
def settings():
    return parse_settings(json.loads(json.dumps(SOURCES)))
