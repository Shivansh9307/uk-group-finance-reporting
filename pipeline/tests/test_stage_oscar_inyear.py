"""The in-year load stage: pure helpers, then the quarantine mechanism against the database.

The planted rows below are a fixture: a small CSV in the v2023 layout with rows the load must reject.
They go through the same `load_rows` the real build uses, into scratch tables, and never touch the
real releases.
"""

from __future__ import annotations

from dataclasses import replace
from decimal import Decimal

import pytest

from ukfr.db import Db
from ukfr.readers.oscar_inyear import InyearFile, ReadStats, read_inyear_bytes
from ukfr.stages import all_stages, select_stages
from ukfr.stages.oscar_inyear import (
    QUARANTINE_COLUMNS,
    RAW_COLUMNS,
    Tables,
    choose_primaries,
    classify,
    content_digest,
    load_rows,
    plain,
    raw_tuple,
    row_digest,
    split_amount,
)

HEADER = (
    "Organisation Code,Organisation,Control Budget Code,Control Budget Detail Code,Segment Department Long Name,"
    "Sub Segment Code,Sub Segment Long Name,Economic Category Code,Economic Category Long Name,Economic Budget Code,"
    "PESA Economic Group Code,Version,Year,Quarter,Month,Amount\r\n"
)


def line(org: str, month: str, amount: str, sub: str = "X001A001") -> str:
    return (
        f"{org},Org {org},TOTAL DEL,DEL ADMIN,Dept,{sub},{sub}-name,A101,Pay,RESOURCE,STAFF COSTS,"
        f"MFO_2099-00_R01,2099-00,Qtr1 - 99-00,{month},{amount}\r\n"
    )


PLANTED = (
    HEADER
    + line("GOOD01", "Apr-22", "12.5")  # row 2: loads
    + line("BADAMT", "Apr-22", "twelve")  # row 3: amount that is not a number
    + line("BLANKA", "May-22", "")  # row 4: blank amount
    + line("BADMON", "Foo-99", "5")  # row 5: month that is not a month
    + line("BADPER", "Period 13 - 22-23", "7")  # row 6: an unknown period label
    + line("PERIO0", "Period 0 - 18-19", "-8")  # row 7: the one non-month label that is allowed
    + line("THOUSD", "Jun-22", '"1,234.5"')  # row 8: thousands separator, loads
    + line("TOOFINE", "Jul-22", "0." + "1" * 35)  # row 9: more decimal places than the raw table keeps
    + line("EXACT31", "Aug-22", "1.0000000000000000000000000000001")  # row 10: 31 places, loads exactly
)


def read_planted():
    stats = ReadStats()
    return list(read_inyear_bytes(PLANTED.encode("cp1252"), "2099-03", "csv", stats, lenient=True)), stats


def test_planted_rows_are_classified_with_the_right_reason():
    rows, stats = read_planted()
    verdicts = {r.organisation_code: classify(r) for r in rows}
    reasons = {k: (v[0] if v else None) for k, v in verdicts.items()}
    assert reasons == {
        "GOOD01": None,
        "BADAMT": "amount_unparseable",
        "BLANKA": "amount_blank",
        "BADMON": "month_unrecognised",
        "BADPER": "month_unrecognised",
        "PERIO0": None,
        "THOUSD": None,
        "TOOFINE": "amount_scale",
        "EXACT31": None,
    }
    assert stats.data_rows == 9


def test_a_strict_read_still_raises_on_the_bad_amount():
    from ukfr.readers.oscar_inyear import InyearFormatError

    with pytest.raises(InyearFormatError, match="twelve"):
        list(read_inyear_bytes(PLANTED.encode("cp1252"), "2099-03", "csv"))


def test_split_amount_is_exact_and_keeps_the_sign():
    assert split_amount(Decimal("12.5")) == (12, Decimal("0.5"))
    assert split_amount(Decimal("-12.5")) == (-12, Decimal("-0.5"))
    assert split_amount(Decimal("-0.25")) == (0, Decimal("-0.25"))
    assert split_amount(Decimal("1E+3")) == (1000, Decimal(0))
    whole, frac = split_amount(Decimal("-1.06581E-14"))
    assert whole == 0 and frac == Decimal("-0.0000000000000106581")
    whole, frac = split_amount(Decimal("946817223.6410417009665510197161520200381"))
    assert whole == 946817223 and format(frac, "f") == "0.6410417009665510197161520200381"


def test_plain_does_not_round_long_values():
    long = "946817223.6410417009665510197161520200381"
    assert plain(Decimal(long)) == long
    assert plain(Decimal("1.500")) == "1.5" and plain(Decimal("-0")) == "0" and plain(Decimal("1E+3")) == "1000"


def test_row_digest_ignores_text_form_but_not_content():
    rows, _ = read_planted()
    good = rows[0]
    assert row_digest(good) == row_digest(good._replace(amount_text="12.50", amount=Decimal("12.50")))
    assert row_digest(good) != row_digest(good._replace(amount=Decimal("12.6")))
    a, b = row_digest(rows[0]), row_digest(rows[6])
    assert content_digest([a, b]) == content_digest([b, a])
    assert content_digest([a, b]) != content_digest([a, a])


def test_raw_tuple_matches_the_column_list():
    rows, _ = read_planted()
    t = raw_tuple(7, rows[0])
    assert len(t) == len(RAW_COLUMNS) == 22
    assert t[:3] == (7, rows[0].line, "2099-03") and t[-2:] == (12, Decimal("0.5"))
    assert len(QUARANTINE_COLUMNS) == 22


def test_primary_choice_is_checked_against_the_control_csv():
    files = [InyearFile("2024-03", "a.zip", "p", "h1", "m"), InyearFile("2024-03", "b.ods", "p", "h2", "")]
    expected = [
        {"release": "2024-03", "filename": "a.zip", "sha256": "h1", "primary_for_release": "Y"},
        {"release": "2024-03", "filename": "b.ods", "sha256": "h2", "primary_for_release": "N"},
    ]
    assert choose_primaries(files, expected) == {("2024-03", "a.zip"): True, ("2024-03", "b.ods"): False}
    with pytest.raises(ValueError, match="exactly one primary"):
        choose_primaries(files, [dict(e, primary_for_release="Y") for e in expected])
    with pytest.raises(ValueError, match="sha256"):
        choose_primaries(files, [dict(expected[0], sha256="other"), expected[1]])
    with pytest.raises(ValueError, match="not in"):
        choose_primaries(files + [InyearFile("2024-06", "c.zip", "p", "h3", "m")], expected)


def test_the_stage_registry_finds_the_inyear_stage_and_respects_scope():
    names = [s.name for s in all_stages()]
    assert "oscar_inyear" in names
    assert [s.name for s in select_stages("committed")] == [s.name for s in all_stages() if s.scope == "committed"]
    assert [s.name for s in select_stages("committed", ["oscar_inyear"])] == ["oscar_inyear"]
    with pytest.raises(ValueError, match="unknown stage"):
        select_stages("committed", ["nope"])


# -- against the database -----------------------------------------------------------------------


@pytest.fixture
def scratch(db):
    """Copies of the raw and quarantine tables for one test, dropped afterwards."""
    raw, quarantine = "raw.zz_test_inyear", "quarantine.zz_test_inyear"
    for t in (raw, quarantine):
        db.execute(f"DROP TABLE IF EXISTS {t}")
    db.execute(f"SELECT * INTO {raw} FROM raw.oscar_inyear WHERE 1 = 0")
    db.execute(f"SELECT * INTO {quarantine} FROM quarantine.oscar_inyear WHERE 1 = 0")
    yield Tables(raw=raw, quarantine=quarantine)
    for t in (raw, quarantine):
        db.execute(f"DROP TABLE IF EXISTS {t}")


@pytest.mark.db
@pytest.mark.parametrize("loader", ["bulk", "executemany"])
def test_planted_bad_rows_land_in_quarantine_with_their_reason(db, db_settings, scratch, loader):
    rows, stats = read_planted()
    conn = Db(replace(db_settings, loader=loader))
    try:
        res = load_rows(
            conn, 99, InyearFile("2099-03", "x.csv", "p", "h", ""), iter(rows), stats, scratch, keep_digest=False
        )
    finally:
        conn.close()
    assert (res.loaded, res.quarantined) == (4, 5)
    assert res.reasons == {"amount_unparseable": 1, "amount_blank": 1, "month_unrecognised": 2, "amount_scale": 1}

    loaded = db.query(f"SELECT organisation_code, amount_whole, amount_frac FROM {scratch.raw} ORDER BY source_row")
    assert [r[0] for r in loaded] == ["GOOD01", "PERIO0", "THOUSD", "EXACT31"]
    assert loaded[0][1:] == (12, Decimal("0.5"))
    assert loaded[1][1:] == (-8, Decimal(0))
    assert loaded[2][1:] == (1234, Decimal("0.5"))
    assert loaded[3][1] == 1 and format(loaded[3][2], "f") == "0." + "0" * 30 + "1"

    q = db.query(
        f"SELECT organisation_code, reason_code, amount_text, [month], source_row FROM {scratch.quarantine} "
        "ORDER BY source_row"
    )
    assert q == [
        ("BADAMT", "amount_unparseable", "twelve", "Apr-22", 3),
        ("BLANKA", "amount_blank", "", "May-22", 4),
        ("BADMON", "month_unrecognised", "5", "Foo-99", 5),
        ("BADPER", "month_unrecognised", "7", "Period 13 - 22-23", 6),
        ("TOOFINE", "amount_scale", "0." + "1" * 35, "Jul-22", 9),
    ]
    # every source row went to exactly one place
    assert (
        db.scalar(f"SELECT COUNT(*) FROM {scratch.raw}") + db.scalar(f"SELECT COUNT(*) FROM {scratch.quarantine}") == 9
    )
