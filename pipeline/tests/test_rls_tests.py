"""The role-case framework: manifest checks and the three comparison modes, without Desktop or a database."""

from __future__ import annotations

import csv
from pathlib import Path

import pytest

from ukfr import rlstests
from ukfr.rlstests import Case


def test_the_committed_manifest_agrees_with_the_queries_the_expected_sources_and_the_roles(repo_root):
    cases = rlstests.read_manifest(repo_root)
    assert len(cases) > 50
    assert rlstests.check_manifest(repo_root, cases) == []
    assert {c.mode for c in cases} == {"values", "differs", "error"}
    assert {c.role for c in cases} == {"Department Analyst", "Restricted Viewer"}
    assert all(c.user.lower().endswith("@example.org") for c in cases), "role cases use invented users only"


def test_every_role_case_names_a_user_so_that_no_case_runs_as_the_person_who_runs_it(repo_root):
    for c in rlstests.read_manifest(repo_root):
        assert c.user, c.case


def test_the_unmapped_user_is_run_under_both_roles_and_the_full_total_is_refused_to_every_mapped_role(repo_root):
    cases = rlstests.read_manifest(repo_root)
    assert {c.role for c in cases if c.user == "nobody@example.org"} == {"Department Analyst", "Restricted Viewer"}
    differs = [c for c in cases if c.mode == "differs"]
    assert {c.role for c in differs} == {"Department Analyst", "Restricted Viewer"}
    assert {c.expected for c in differs} == {"full_totals"}


def test_a_user_is_substituted_as_a_unicode_literal_and_anything_but_an_example_address_is_refused():
    assert rlstests.user_literal("a.b@example.org") == "N'a.b@example.org'"
    for bad in ("a@example.com", "x'; DROP TABLE t;--@example.org", "someone@gmail.com", ""):
        with pytest.raises(rlstests.RlsTestError):
            rlstests.user_literal(bad)


def _write(path: Path, header: list[str], rows: list[list[str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh, lineterminator="\n")
        w.writerow(header)
        w.writerows(rows)


def _case(mode: str, expect_error: str = "") -> Case:
    return Case("c", "q", "Department Analyst", "a@example.org", mode, "q", expect_error)


def test_values_mode_passes_on_equal_rows_in_any_order_and_fails_on_a_wrong_number(tmp_path):
    c = _case("values")
    _write(tmp_path / rlstests.EXPECTED_DIR / "q__c.csv", ["k", "v"], [["a", "1.0000"], ["b", "2"]])
    _write(tmp_path / rlstests.RESULTS_DIR / "q__c.csv", ["k", "v"], [["b", "2"], ["a", "1"]])
    assert rlstests.compare_case(tmp_path, c).ok
    _write(tmp_path / rlstests.RESULTS_DIR / "q__c.csv", ["k", "v"], [["b", "2"], ["a", "5"]])
    assert not rlstests.compare_case(tmp_path, c).ok


def test_a_blank_is_not_a_zero_and_a_header_only_result_equals_a_header_only_expectation(tmp_path):
    c = _case("values")
    _write(tmp_path / rlstests.EXPECTED_DIR / "q__c.csv", ["v"], [[""]])
    _write(tmp_path / rlstests.RESULTS_DIR / "q__c.csv", ["v"], [["0"]])
    assert not rlstests.compare_case(tmp_path, c).ok
    _write(tmp_path / rlstests.EXPECTED_DIR / "q__c.csv", ["v"], [])
    _write(tmp_path / rlstests.RESULTS_DIR / "q__c.csv", ["v"], [])
    assert rlstests.compare_case(tmp_path, c).ok


def test_differs_mode_passes_only_when_the_result_is_not_the_unfiltered_total(tmp_path):
    c = _case("differs")
    _write(tmp_path / rlstests.EXPECTED_DIR / "q__c.csv", ["outturn"], [["100"]])
    _write(tmp_path / rlstests.RESULTS_DIR / "q__c.csv", ["outturn"], [["40"]])
    assert rlstests.compare_case(tmp_path, c).ok
    _write(tmp_path / rlstests.RESULTS_DIR / "q__c.csv", ["outturn"], [["100"]])
    assert not rlstests.compare_case(tmp_path, c).ok


def test_error_mode_needs_a_refusal_with_the_stated_text_and_fails_on_an_answer_or_a_different_error(tmp_path):
    c = _case("error", "Cannot find table 'File Control'")
    res = tmp_path / rlstests.RESULTS_DIR / "q__c.csv"
    _write(res, ["outcome", "message"], [["error", "Error: Query (1, 2) Cannot find table 'File Control'."]])
    assert rlstests.compare_case(tmp_path, c).ok
    _write(res, ["outcome", "message"], [["error", "Error: something else"]])
    assert not rlstests.compare_case(tmp_path, c).ok
    _write(res, ["rows"], [["31"]])
    out = rlstests.compare_case(tmp_path, c)
    assert not out.ok and "not refused" in out.details[0]


def test_a_values_case_whose_query_was_refused_fails_and_says_so_and_a_missing_result_is_a_failure(tmp_path):
    c = _case("values")
    _write(tmp_path / rlstests.EXPECTED_DIR / "q__c.csv", ["v"], [["1"]])
    assert rlstests.compare_case(tmp_path, c).status == "missing_result"
    _write(tmp_path / rlstests.RESULTS_DIR / "q__c.csv", ["outcome", "message"], [["error", "Cannot find table"]])
    out = rlstests.compare_case(tmp_path, c)
    assert not out.ok and "refused" in out.details[0]
