"""The report's on-screen figures against the DAX test results, and the screenshots against the pages.

evidence/report/screenshot_figures.csv lists figures that I read off the cropped screenshots, one row for each figure:
the page, the visual, the label, the figure as displayed, the DAX test that returns the same figure, the row of the test
result (`column=value`, several joined with `;`), the column, and how the figure is displayed (divisor and decimals).
The check rounds the test result as displayed, half up, and compares it with the figure as read. A text figure (a plan
badge, a status) must equal the test result, or start with it when the visual cuts the text off. These tests need no
database and no Desktop: they read the committed test results.
"""

from __future__ import annotations

import csv
import re
import struct
from decimal import ROUND_HALF_UP, Decimal
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
FIGURES = ROOT / "evidence" / "report" / "screenshot_figures.csv"
RESULTS = ROOT / "tests" / "results"
SHOTS = ROOT / "screenshots"
PAGES = [
    "01_executive_summary",
    "02_pnl_statement",
    "03_variance",
    "04_restatements",
    "05_data_controls",
    "06_department_detail",
    "07_group_detail",
]


def _figures() -> list[dict]:
    with FIGURES.open(encoding="utf-8", newline="") as fh:
        return list(csv.DictReader(fh))


def _result(test: str) -> list[dict]:
    with (RESULTS / f"{test}.csv").open(encoding="utf-8", newline="") as fh:
        return list(csv.DictReader(fh))


def _number(text: str) -> Decimal:
    return Decimal(re.sub(r"[£,%]|bn|m$|k$", "", text.replace("−", "-")))


def _row(rows: list[dict], key: str) -> dict:
    wanted = dict(part.split("=", 1) for part in key.split(";"))
    found = [r for r in rows if all(str(r.get(c, "")).strip().strip('"') == v for c, v in wanted.items())]
    assert len(found) == 1, f"{key}: {len(found)} rows"
    return found[0]


def test_the_figures_file_covers_every_page_and_every_figure_has_a_source():
    figures = _figures()
    assert {f["page"] for f in figures} == set(PAGES)
    for f in figures:
        assert (RESULTS / f"{f['dax_test']}.csv").exists(), f["dax_test"]
        assert f["displayed"].strip() and f["label"].strip() and f["visual"].strip()


@pytest.mark.parametrize("figure", _figures(), ids=lambda f: f"{f['page']}:{f['visual']}:{f['label']}"[:90])
def test_a_displayed_figure_is_the_dax_test_result_rounded_as_displayed(figure):
    value = _row(_result(figure["dax_test"]), figure["key"])[figure["value_column"]]
    if figure["divisor"] == "":
        shown = figure["displayed"]
        assert value == shown or value.startswith(shown), f"{value!r} against {shown!r}"
        return
    places = Decimal(1).scaleb(-int(figure["decimals"]))
    expected = (Decimal(value) / Decimal(figure["divisor"])).quantize(places, rounding=ROUND_HALF_UP)
    assert expected == _number(figure["displayed"]).quantize(places), f"{expected} against {figure['displayed']}"


def test_the_screenshots_are_there_cropped_and_the_same_size():
    for page in PAGES:
        path = SHOTS / f"{page}.png"
        assert path.exists(), path
        head = path.read_bytes()[:32]
        assert head[:8] == b"\x89PNG\r\n\x1a\n"
        width, height = struct.unpack(">II", head[16:24])
        assert (width, height) == (2034, 1144), (page, width, height)
