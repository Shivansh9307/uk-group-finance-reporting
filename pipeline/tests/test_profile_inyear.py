"""ukfr.profile.inyear: helpers, and an end-to-end run on a two-release repository built from snippets."""

from __future__ import annotations

import csv
import hashlib
import zipfile
from decimal import Decimal
from pathlib import Path

from oscar_snippets import V2021DEC, V2021SEP

from ukfr.manifest import Row, write_rows
from ukfr.profile import inyear
from ukfr.profile.inyear import is_abbreviation, norm_name, release_fy, split_code, token_similarity


def test_release_fy():
    assert release_fy("2022-09") == "2022-23"
    assert release_fy("2022-12") == "2022-23"
    assert release_fy("2023-03") == "2022-23"
    assert release_fy("2023-06") == "2022-23"


def test_name_helpers():
    assert norm_name("Foreign, Commonwealth & Development Office") == "FOREIGN COMMONWEALTH AND DEVELOPMENT OFFICE"
    assert split_code("ACA084") == ("ACA", "084")
    assert is_abbreviation("SSRO", "SINGLE SOURCE REGULATIONS OFFICE")
    assert not is_abbreviation("HOMES ENGLAND", "HOME AND COMMUNITIES AGENCY")
    assert token_similarity("DEPARTMENT FOR INTERNATIONAL TRADE", "DEPARTMENT FOR BUSINESS AND TRADE") == 1 / 3


def _repo(tmp: Path) -> Path:
    files = []
    for release, name, data in (("2021-09", "sep.zip", V2021SEP), ("2021-12", "dec.zip", V2021DEC)):
        path = tmp / "data" / "committed" / "oscar_inyear" / release / name
        path.parent.mkdir(parents=True)
        with zipfile.ZipFile(path, "w") as z:
            z.writestr(name.replace(".zip", ".csv"), data)
        rel = path.relative_to(tmp).as_posix()
        files.append(Row("oscar_inyear", release, "", "", "", "", name, "", "", str(path.stat().st_size),
                         hashlib.sha256(path.read_bytes()).hexdigest(), "yes", "200", rel, "",
                         f"{name.replace('.zip', '.csv')}|deflate|{len(data)}"))  # fmt: skip
    write_rows(tmp / "data" / "manifest" / "files.csv", files)
    return tmp


def _read(path: Path) -> list[dict]:
    with open(path, encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def test_end_to_end_control_totals_deltas_and_determinism(tmp_path):
    root = _repo(tmp_path)
    inyear.run(root, log=lambda *_: None)
    audit = root / "data" / "audit" / "inyear_file_control_totals.csv"
    control = _read(audit)
    assert [r["release"] for r in control] == ["2021-09", "2021-12"]
    assert [r["header_variant"] for r in control] == ["v2021sep", "v2021dec"]
    assert [Decimal(r["amount_sum"]) for r in control] == [Decimal(138), Decimal(138)]
    assert control[0]["amount_ame"] == "0" and control[0]["amount_del"] == "138"

    delta = {r["release"]: r for r in _read(root / "docs" / "profiling" / "data" / "inyear_delta_rowcount.csv")}
    # Dec-21 holds only the Sep-21 line: one first appearance, two keys vanish (one of them was zero).
    assert (delta["2021-12"]["first_appearances"], delta["2021-12"]["vanished"]) == ("1", "2")
    assert (delta["2021-12"]["delta_rows_all"], delta["2021-12"]["delta_rows_non_zero"]) == ("3", "2")

    grain = _read(root / "docs" / "profiling" / "data" / "inyear_grain.csv")
    assert all(r["duplicate_groups"] == "0" for r in grain)

    first = {p: p.read_bytes() for p in (root / "docs").rglob("*.csv")} | {audit: audit.read_bytes()}
    inyear.run(root, log=lambda *_: None)
    assert {p: p.read_bytes() for p in first} == first
