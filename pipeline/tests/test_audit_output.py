"""The exact-sum SQL function and the audit CSV export."""

from __future__ import annotations

import datetime
from decimal import Decimal

import pytest

from ukfr.build import DEFAULT_AUDIT_DIR, export_audit, plain_text


def test_plain_text_is_exact_and_locale_free():
    assert plain_text(None) == ""
    assert plain_text(True) == "1"
    assert plain_text(Decimal("1.5000")) == "1.5"
    assert plain_text(Decimal("1E+3")) == "1000"
    assert plain_text(Decimal("-0.0")) == "0"
    assert (
        plain_text(Decimal("946817223.6410417009665510197161520200381")) == "946817223.6410417009665510197161520200381"
    )
    assert plain_text(datetime.date(2019, 3, 21)) == "2019-03-21"
    assert plain_text("x") == "x"


@pytest.mark.db
@pytest.mark.parametrize(
    "whole, frac, expected",
    [
        (5, "0", "5"),
        (-5, "0", "-5"),
        (0, "0", "0"),
        (5, "-0.3", "4.7"),
        (-5, "0.3", "-4.7"),
        (0, "-0.3", "-0.3"),
        (0, "0.3", "0.3"),
        (5, "12.5", "17.5"),
        (-5, "-12.5", "-17.5"),
        (-12, "12.5", "0.5"),
        (12, "-12.5", "-0.5"),
        (12, "-12", "0"),
        (1, "-1.5", "-0.5"),
        (3, "-3.0000000000000000000000000000001", "-0.0000000000000000000000000000001"),
        (946817223, "0.6410417009665510197161520200381", "946817223.6410417009665510197161520200381"),
        (-946817223, "-0.6410417009665510197161520200381", "-946817223.6410417009665510197161520200381"),
    ],
)
def test_exact_sum_text(db, whole, frac, expected):
    got = db.scalar("SELECT audit.exact_sum_text(?, CAST(? AS decimal(38,31)))", (whole, frac))
    assert got == expected


@pytest.mark.db
def test_the_audit_export_is_deterministic_and_matches_the_committed_evidence(db, repo_root, tmp_path):
    first = export_audit(db, tmp_path / "a")
    second = export_audit(db, tmp_path / "b")
    assert [p.name for p in first] == [p.name for p in second] and first
    for a, b in zip(first, second, strict=True):
        assert a.read_bytes() == b.read_bytes()
        assert b"\r" not in a.read_bytes()
    committed = repo_root / DEFAULT_AUDIT_DIR
    committed_names = {p.name for p in committed.glob("*.csv")}
    exported = {p.name: p for p in first}
    scope = db.scalar(
        "SELECT CAST(value AS varchar(20)) FROM sys.extended_properties WHERE class = 0 AND name = N'ukfr_build_scope'"
    )
    # evidence/build holds what a committed-scope build writes. A database built with --scope full has more audit
    # tables and more rows in some of them (table counts, plan coverage), so for it every committed file must still
    # be in the export and nothing is compared byte for byte.
    if scope == "full":
        assert committed_names <= set(exported), sorted(committed_names - set(exported))
        return
    assert committed_names == set(exported), (
        sorted(committed_names - set(exported)),
        sorted(set(exported) - committed_names),
    )
    for name in sorted(committed_names):
        want = (committed / name).read_bytes().replace(b"\r\n", b"\n")
        assert want == exported[name].read_bytes(), (
            f"{name} differs from the committed copy; rebuild and commit evidence/build"
        )
