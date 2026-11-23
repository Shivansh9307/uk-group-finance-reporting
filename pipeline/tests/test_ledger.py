"""The evidence ledger: the model projection hash, the file hashes, the gate on writing, the check, the model reference
and the committed-scope expected set. None of it needs a database or Desktop."""

from __future__ import annotations

import itertools
import json
import re
import shutil
from pathlib import Path

import pytest

from ukfr import ledger, model_docs, modeltests

CRLF, LF = chr(13) + chr(10), chr(10)

MODEL = """\
/// One table of the fixture.
table Sales
	lineageTag: 11111111-1111-1111-1111-111111111111

	/// The total.
	measure Total = SUM ( Sales[Amount] )
		formatString: #,0
		displayFolder: Totals
		lineageTag: 22222222-2222-2222-2222-222222222222
		annotation PBI_FormatHint = {"isGeneralNumber":true}

	measure 'Net of tax' =
			VAR Gross = [Total]
			RETURN
				Gross * 0.8
		displayFolder: Totals
		lineageTag: 33333333-3333-3333-3333-333333333333

	column Amount
		dataType: decimal
		lineageTag: 44444444-4444-4444-4444-444444444444
		summarizeBy: none
		sourceColumn: amount

		annotation SummarizationSetBy = Automatic

	column Region
		dataType: string
		lineageTag: 55555555-5555-5555-5555-555555555555
		summarizeBy: none
		sourceColumn: region

	partition Sales = m
		mode: import
		source =
				let
					Source = Sql.Database(Server, Database)
				in
					Source

	annotation PBI_ResultType = Table
"""

# The same model as Desktop or Tabular Editor might save it after a change of nothing: other lineage tags, other order
# of objects and properties, a quoted name that needs no quotes, a changed-property marker, a different annotation.
MODEL_RESAVED = """\
/// One table of the fixture.
table 'Sales'
	annotation PBI_ResultType = Table

	partition Sales = m
		source =
				let
					Source = Sql.Database(Server, Database)
				in
					Source
		mode: import

	column Region
		sourceColumn: region
		summarizeBy: none
		dataType: string
		lineageTag: aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa

	/// The total.
	measure 'Total' = SUM ( Sales[Amount] )
		lineageTag: bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb
		displayFolder: Totals
		formatString: #,0
		changedProperty = FormatString
		annotation PBI_FormatHint = {"isGeneralNumber":false}

	column Amount
		annotation SummarizationSetBy = Automatic

		sourceColumn: amount
		dataType: decimal
		summarizeBy: none
		lineageTag: cccccccc-cccc-cccc-cccc-cccccccccccc

	measure 'Net of tax' =
			VAR Gross = [Total]
			RETURN
				Gross * 0.8
		lineageTag: dddddddd-dddd-dddd-dddd-dddddddddddd
		displayFolder: Totals

	lineageTag: eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee
"""

RELATIONSHIPS = """\
relationship 00000000-0000-0000-0000-000000000001
	fromColumn: Sales.Region
	toColumn: Region.Region
"""

ROLE = """\
role Reader
	modelPermission: read

	tablePermission Sales = Sales[Region] = "North"
"""


def canon(text: str) -> str:
    return ledger.canonical_tmdl(text)


# -------------------------------------------------------------------------------------------------- projection
def test_resaving_the_model_in_another_order_with_other_lineage_tags_gives_the_same_projection():
    assert canon(MODEL) == canon(MODEL_RESAVED)


def test_line_endings_do_not_change_the_projection():
    assert canon(MODEL) == canon(MODEL.replace("\n", "\r\n"))


def test_a_changed_measure_expression_changes_the_projection():
    changed = MODEL.replace("SUM ( Sales[Amount] )", "SUM ( Sales[Amount] ) + 1")
    assert canon(changed) != canon(MODEL)


def test_a_changed_multiline_expression_changes_the_projection():
    assert canon(MODEL.replace("Gross * 0.8", "Gross * 0.9")) != canon(MODEL)


def test_the_order_of_lines_inside_an_expression_is_kept():
    swapped = MODEL.replace("\t\t\tVAR Gross = [Total]\n\t\t\tRETURN\n", "\t\t\tRETURN\n\t\t\tVAR Gross = [Total]\n")
    assert swapped != MODEL
    assert canon(swapped) != canon(MODEL)


@pytest.mark.parametrize(
    ("old", "new"),
    [
        ("/// The total.", "/// The grand total."),
        ("formatString: #,0", "formatString: 0"),
        ("displayFolder: Totals\n\t\tlineageTag: 22", "displayFolder: Other\n\t\tlineageTag: 22"),
        ("dataType: decimal", "dataType: double"),
        ("sourceColumn: region", "sourceColumn: area"),
        ("summarizeBy: none\n\t\tsourceColumn: amount", "summarizeBy: sum\n\t\tsourceColumn: amount"),
        ("column Region", "column Area"),
        ("measure 'Net of tax'", "measure 'Net of VAT'"),
    ],
)
def test_names_descriptions_formats_types_and_folders_are_in_the_projection(old, new):
    assert old in MODEL
    assert canon(MODEL.replace(old, new)) != canon(MODEL)


def test_a_best_practice_annotation_is_kept_and_a_tool_annotation_is_not():
    with_bpa = MODEL.replace(
        "\tannotation PBI_ResultType = Table",
        '\tannotation BestPracticeAnalyzer_IgnoreRules = {"RuleIDs":["X"]}',
    )
    assert canon(with_bpa) != canon(MODEL)
    assert canon(MODEL.replace("PBI_ResultType = Table", "PBI_ResultType = Text")) == canon(MODEL)


def test_the_time_intelligence_switch_is_kept_although_it_is_a_pbi_annotation():
    on = "annotation __PBI_TimeIntelligenceEnabled = 1\n"
    off = "annotation __PBI_TimeIntelligenceEnabled = 0\n"
    assert canon(on) != canon(off)
    assert canon("annotation __TEdtr = 1\n") == canon("annotation __TEdtr = 2\n")


def test_a_relationship_is_its_columns_and_not_its_generated_id():
    other_id = RELATIONSHIPS.replace("000000000001", "999999999999")
    assert canon(other_id) == canon(RELATIONSHIPS)
    assert canon(RELATIONSHIPS.replace("Region.Region", "Region.Name")) != canon(RELATIONSHIPS)


def test_a_role_filter_is_in_the_projection():
    assert canon(ROLE.replace('"North"', '"South"')) != canon(ROLE)


def test_calculation_items_keep_their_ordinal_and_expression():
    group = (
        "table Time\n\tcalculationGroup\n\t\tcalculationItem Current = SELECTEDMEASURE ()\n\t\t\tordinal: 0\n"
        "\t\tcalculationItem YTD = Window.Ytd ( SELECTEDMEASURE () )\n\t\t\tordinal: 1\n"
    )
    assert canon(group.replace("ordinal: 1", "ordinal: 2")) != canon(group)
    assert canon(group.replace("Window.Ytd", "Window.Mtd")) != canon(group)


def test_a_fenced_block_is_kept_verbatim():
    text = "table T\n\texpression E = ```\n\t\t\tline one\n\tline two at an odd indent\n\t\t\t```\n\tlineageTag: x\n"
    assert "line two at an odd indent" in canon(text)
    assert "lineageTag" not in canon(text)


def test_the_real_model_gives_the_same_hash_after_a_resave_that_changes_only_what_tools_rewrite(repo_root, tmp_path):
    """Change every lineage tag and the line endings of a copy: the hash holds. Change one measure: it does not."""
    src = repo_root / ledger.MODEL_DEFINITION
    dst = tmp_path / "definition"
    shutil.copytree(src, dst)
    base = ledger.projection_hash(tmp_path, dst)
    assert base == ledger.projection_hash(repo_root)

    counter = itertools.count()
    for p in dst.rglob("*.tmdl"):
        text = p.read_bytes().decode("utf-8")
        text = re.sub(
            r"(lineageTag: )[0-9a-f-]{36}",
            lambda m: m.group(1) + f"00000000-0000-0000-0000-{next(counter):012d}",
            text,
        )
        p.write_bytes(text.replace(CRLF, LF).encode("utf-8"))
    assert next(counter) > 100, "the model has lineage tags"
    assert ledger.projection_hash(tmp_path, dst) == base

    for p in sorted((dst / "tables").glob("*.tmdl")):
        text = p.read_text(encoding="utf-8")
        m = re.search(r"^\tmeasure [^\n]*? = [^\n]+$", text, re.MULTILINE)
        if m:
            p.write_text(text.replace(m.group(0), m.group(0) + " + 0", 1), encoding="utf-8", newline="")
            break
    else:
        pytest.fail("no single-line measure to change")
    assert ledger.projection_hash(tmp_path, dst) != base


# ----------------------------------------------------------------------------------------------- the ledger
def _write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="")


def make_repo(root: Path) -> Path:
    """A small repository that passes the gate: one model, one DAX test, one error role case, a reference."""
    definition = root / ledger.MODEL_DEFINITION
    _write(definition / "tables" / "Sales.tmdl", MODEL)
    _write(definition / "roles" / "Reader.tmdl", ROLE)
    _write(root / "tests/dax/700_total.dax", 'EVALUATE ROW ( "Total", 1 )\n')
    _write(root / "tests/expected/700_total.sql", "SELECT CAST(1 AS DECIMAL(19,4)) AS Total\n")
    _write(root / "tests/expected/700_total.csv", "Total\n1\n")
    _write(root / "tests/expected/_meta.csv", "key,value\nbuild_scope,full\n")
    _write(root / "tests/results/700_total.csv", "Total\n1\n")
    _write(root / "tests/expected_committed/700_total.csv", "Total\n2\n")
    _write(root / "tests/expected_committed/_meta.csv", "key,value\nbuild_scope,committed\n")
    _write(
        root / "tests/rls/manifest.csv",
        "case,query,role,user,mode,expected,expect_error\n"
        "hidden,hidden_table,Reader,a.b@example.org,error,,cannot be found\n",
    )
    _write(root / "tests/rls/queries/hidden_table.dax", "EVALUATE Secret\n")
    _write(root / "tests/rls/results/hidden_table__hidden.csv", "outcome,message\nerror,The table cannot be found\n")
    _write(root / "evidence/model/reference/01_tables.csv", "Table\nSales\n")
    _write(root / "tools/model_reference/01_tables.dax", "EVALUATE INFO.VIEW.TABLES ()\n")
    _write(
        root / ledger.REFERENCE,
        f"# Model reference\n\nModel projection hash: `{ledger.projection_hash(root)}`\n",
    )
    return root


def test_a_ledger_written_for_a_consistent_repository_checks_clean(tmp_path):
    root = make_repo(tmp_path)
    written = ledger.write(root)
    assert written["counts"]["dax_test"] == 1
    assert written["counts"]["expected_committed"] == 2
    assert written["expected_build_scope"] == {"tests/expected": "full", "tests/expected_committed": "committed"}
    assert ledger.check(root) == []
    assert json.loads((root / ledger.LEDGER).read_text(encoding="utf-8"))["files"] == written["files"]


def test_the_ledger_is_the_same_whatever_the_line_endings_of_the_checkout(tmp_path):
    root = make_repo(tmp_path)
    ledger.write(root)
    for p in ledger.tracked_files(root):
        f = root / p
        f.write_bytes(f.read_bytes().replace(b"\n", b"\r\n"))
    assert ledger.check(root, compare=False) == []


def test_a_changed_file_a_missing_file_and_an_extra_file_each_fail(tmp_path):
    root = make_repo(tmp_path)
    ledger.write(root)
    _write(root / "tests/results/700_total.csv", "Total\n1.5\n")
    (root / "tests/dax/700_total.dax").unlink()
    _write(root / "tests/results/701_extra.csv", "x\n1\n")
    problems = ledger.check(root, compare=False)
    assert any(p.startswith("changed: tests/results/700_total.csv") for p in problems)
    assert any(p.startswith("missing: tests/dax/700_total.dax") for p in problems)
    assert any(p.startswith("extra: tests/results/701_extra.csv") for p in problems)


@pytest.mark.parametrize(
    "path",
    [
        "tests/expected/700_total.csv",
        "tests/expected/700_total.sql",
        "tests/expected_committed/700_total.csv",
        "tests/rls/manifest.csv",
        "tests/rls/queries/hidden_table.dax",
        "tests/rls/results/hidden_table__hidden.csv",
        "evidence/model/reference/01_tables.csv",
        "tools/model_reference/01_tables.dax",
    ],
)
def test_every_kind_of_tracked_file_is_hash_checked(tmp_path, path):
    root = make_repo(tmp_path)
    ledger.write(root)
    f = root / path
    f.write_text(
        f.read_text(encoding="utf-8") + "\n-- x\n"
        if path.endswith((".sql", ".dax"))
        else f.read_text(encoding="utf-8") + "z,z\n",
        encoding="utf-8",
        newline="",
    )
    assert any(p.startswith(f"changed: {path}") for p in ledger.check(root, compare=False))


def test_a_changed_measure_makes_the_ledger_and_the_reference_stale(tmp_path):
    root = make_repo(tmp_path)
    ledger.write(root)
    table = root / ledger.MODEL_DEFINITION / "tables" / "Sales.tmdl"
    table.write_text(table.read_text(encoding="utf-8").replace("SUM ( Sales[Amount] )", "SUM ( Sales[Amount] ) * 2"))
    problems = ledger.check(root, compare=False)
    assert any("the model changed since the evidence was written" in p for p in problems)
    assert any(
        "model-reference.md is stale: it was generated from model" in p and "Regenerate in Desktop" in p
        for p in problems
    )


def test_a_lineage_tag_change_alone_leaves_the_ledger_valid(tmp_path):
    root = make_repo(tmp_path)
    ledger.write(root)
    table = root / ledger.MODEL_DEFINITION / "tables" / "Sales.tmdl"
    table.write_text(table.read_text(encoding="utf-8").replace("2222-2222", "9999-9999"))
    assert ledger.check(root, compare=False) == []


def test_a_reference_regenerated_for_another_model_is_stale_even_when_the_ledger_is_rewritten_without_the_gate(
    tmp_path,
):
    root = make_repo(tmp_path)
    table = root / ledger.MODEL_DEFINITION / "tables" / "Sales.tmdl"
    table.write_text(table.read_text(encoding="utf-8").replace("Gross * 0.8", "Gross * 0.7"))
    ledger.write(root, ignore_gate=True)  # the page still carries the hash of the model before the change
    assert any("model-reference.md is stale" in p for p in ledger.check(root, compare=False))


def test_compiled_python_next_to_an_expected_source_is_not_evidence(tmp_path):
    root = make_repo(tmp_path)
    _write(root / "tests/expected/__pycache__/703_x.cpython-314.pyc", "compiled")
    assert not [f for f in ledger.tracked_files(root) if "__pycache__" in f]


def test_a_missing_ledger_fails(tmp_path):
    root = make_repo(tmp_path)
    assert any("does not exist" in p for p in ledger.check(root))


def test_the_scope_of_the_expected_values_is_checked(tmp_path):
    root = make_repo(tmp_path)
    ledger.write(root)
    _write(root / "tests/expected_committed/_meta.csv", "key,value\nbuild_scope,full\n")
    assert any("expected build scope" in p for p in ledger.check(root, compare=False))


# ------------------------------------------------------------------------------------------------ the gate
def test_write_refuses_when_a_result_differs_from_its_expected_value(tmp_path):
    root = make_repo(tmp_path)
    _write(root / "tests/results/700_total.csv", "Total\n2\n")
    with pytest.raises(ledger.LedgerError, match="dax test 700_total"):
        ledger.write(root)
    assert not (root / ledger.LEDGER).exists()


def test_write_refuses_when_a_role_case_fails(tmp_path):
    root = make_repo(tmp_path)
    _write(root / "tests/rls/results/hidden_table__hidden.csv", "outcome,message\nerror,Something else\n")
    with pytest.raises(ledger.LedgerError, match="role case hidden_table__hidden"):
        ledger.write(root)


def test_write_refuses_when_the_expected_values_are_not_full_scope(tmp_path):
    root = make_repo(tmp_path)
    _write(root / "tests/expected/_meta.csv", "key,value\nbuild_scope,committed\n")
    with pytest.raises(ledger.LedgerError, match="not full"):
        ledger.write(root)


def test_write_refuses_when_the_reference_was_generated_from_another_model(tmp_path):
    root = make_repo(tmp_path)
    page = root / ledger.REFERENCE
    page.write_text(page.read_text(encoding="utf-8").replace(ledger.projection_hash(root), "0" * 64))
    with pytest.raises(ledger.LedgerError, match="stale"):
        ledger.write(root)


def test_write_refuses_when_the_reference_names_no_model(tmp_path):
    root = make_repo(tmp_path)
    (root / ledger.REFERENCE).write_text("# Model reference\n", encoding="utf-8")
    with pytest.raises(ledger.LedgerError, match="does not say which model"):
        ledger.write(root)


def test_check_reruns_the_comparisons_and_reports_a_failing_one(tmp_path):
    root = make_repo(tmp_path)
    ledger.write(root)
    # A result and the ledger edited together would pass the hash check: the comparison still sees the difference.
    _write(root / "tests/results/700_total.csv", "Total\n7\n")
    ledger.write(root, ignore_gate=True)
    problems = ledger.check(root)
    assert any("dax test 700_total: fail" in p for p in problems)
    assert ledger.check(root, compare=False) == []


# ------------------------------------------------------------------------------ the command and the repository
def test_the_command_runs_on_a_bare_interpreter_module(tmp_path, monkeypatch, capsys):
    root = make_repo(tmp_path)
    monkeypatch.setenv("UKFR_REPO_ROOT", str(root))
    assert ledger.main(["write"]) == 0
    assert ledger.main(["check"]) == 0
    assert "ledger: ok" in capsys.readouterr().out
    _write(root / "tests/dax/700_total.dax", 'EVALUATE ROW ( "Total", 3 )\n')
    assert ledger.main(["check"]) == 1
    assert "changed: tests/dax/700_total.dax" in capsys.readouterr().err


def test_ledger_has_no_dependency_beyond_the_standard_library_and_the_two_comparison_modules():
    text = Path(ledger.__file__).read_text(encoding="utf-8")
    imports = set(re.findall(r"^\s*(?:from|import) (\w[\w.]*)", text, re.MULTILINE))
    third_party = {
        i for i in imports if i.split(".")[0] in {"httpx", "yaml", "mssql_python", "python_calamine", "inflate64"}
    }
    assert not third_party


def test_the_committed_ledger_covers_every_dax_test_and_role_case_and_the_two_expected_sets(repo_root):
    path = repo_root / ledger.LEDGER
    if not path.is_file():
        pytest.skip("evidence/ledger.json is not written yet")
    stored = json.loads(path.read_text(encoding="utf-8"))
    files = stored["files"]
    for dax in modeltests.dax_tests(repo_root):
        assert f"tests/dax/{dax.name}" in files
        assert f"tests/results/{dax.stem}.csv" in files
        assert f"tests/expected/{dax.stem}.csv" in files
    assert stored["expected_build_scope"] == {"tests/expected": "full", "tests/expected_committed": "committed"}
    assert not [f for f in files if re.search(r"[A-Za-z]:[\\/]", f)]


# ------------------------------------------------------------------------------------- committed-scope set
class FakeDb:
    """Stands in for the database: `scalar` answers OBJECT_ID, `columns` answers every query with one row."""

    def __init__(self, tables: set[str]):
        self.tables = tables

    def scalar(self, sql, params=()):
        return 1 if params[0] in self.tables else None

    def columns(self, sql):
        return ["value"], [(1,)]


def _expected_repo(root: Path) -> Path:
    _write(root / "tests/dax/700_a.dax", "x")
    _write(root / "tests/dax/701_b.dax", "x")
    _write(root / "tests/dax/702_c.dax", "x")
    _write(root / "tests/expected/700_a.sql", "SELECT 1 AS value\n")
    _write(root / "tests/expected/701_b.sql", "-- requires: audit.annual_control\nSELECT 1 AS value\n")
    _write(
        root / "tests/expected/702_c.py",
        "def generate(root):\n    raise FileNotFoundError('C:/somewhere/data/raw/file.xlsx')\n",
    )
    return root


def test_a_test_that_needs_a_missing_table_or_an_uncommitted_file_is_skipped_and_listed(tmp_path):
    root = _expected_repo(tmp_path)
    out = tmp_path / "committed"
    skipped: list[tuple[str, str]] = []
    done = modeltests.write_expected(
        root, FakeDb(set()), "committed", out_dir=out, skip_unavailable=True, skipped=skipped
    )
    assert [stem for stem, _ in done] == ["700_a"]
    assert sorted(skipped) == [
        ("701_b", "needs audit.annual_control"),
        ("702_c", modeltests.NOT_COMMITTED),
    ]
    listed = (out / modeltests.SKIPPED_FILE).read_text(encoding="utf-8")
    assert listed.splitlines() == [
        "test,reason",
        "701_b,needs audit.annual_control",
        f"702_c,{modeltests.NOT_COMMITTED}",
    ]
    assert "somewhere" not in listed, "a reason never holds a path"
    assert modeltests.read_scope(out) == "committed"


def test_a_missing_source_file_is_an_error_unless_skipping_is_asked_for(tmp_path):
    root = _expected_repo(tmp_path)
    with pytest.raises(FileNotFoundError):
        modeltests.write_expected(root, FakeDb({"audit.annual_control"}), "full", out_dir=tmp_path / "x")


def test_a_full_run_removes_the_csv_and_the_list_of_an_earlier_partial_run(tmp_path):
    root = _expected_repo(tmp_path)
    out = tmp_path / "set"
    _write(out / "701_b.csv", "value\n9\n")
    modeltests.write_expected(root, FakeDb(set()), "committed", out_dir=out, skip_unavailable=True)
    assert not (out / "701_b.csv").exists()
    # every table now present and the python test given a file: nothing skipped, so no list is left behind
    _write(root / "tests/expected/702_c.py", "def generate(root):\n    return ['value'], [[1]]\n")
    modeltests.write_expected(root, FakeDb({"audit.annual_control"}), "full", out_dir=out)
    assert not (out / modeltests.SKIPPED_FILE).exists()


# --------------------------------------------------------------------------------------- the model reference
def test_the_reference_renders_the_same_bytes_twice_and_names_no_machine(repo_root):
    first = model_docs.generate(repo_root)
    second = model_docs.generate(repo_root)
    assert first == second
    assert "\r" not in first
    assert not re.search(r"[A-Za-z]:[\\/]", first)
    assert Path.home().name not in first and str(Path.home()) not in first
    assert f"Model projection hash: `{ledger.projection_hash(repo_root)}`" in first


def test_the_committed_reference_is_what_the_committed_inputs_render_to(repo_root):
    """Apart from the hash line, which a TMDL edit changes before the page is generated again."""
    committed = repo_root / ledger.REFERENCE
    if not committed.is_file():
        pytest.skip("docs/model-reference.md is not generated yet")
    pattern = re.compile(r"^Model projection hash: `[0-9a-f]{64}`$", re.MULTILINE)
    assert pattern.sub("H", model_docs.generate(repo_root)) == pattern.sub("H", committed.read_text(encoding="utf-8"))


def _tmdl_measures(root: Path) -> set[tuple[str, str]]:
    found = set()
    for p in ledger.model_files(root):
        tree = ledger._parse_tmdl(p.read_text(encoding="utf-8-sig"))
        for node in tree.children:
            if not node.header.startswith("table "):
                continue
            table = node.header[len("table ") :].strip().strip("'")
            for child in node.children:
                m = re.match(r"measure (?:'((?:[^']|'')+)'|([^\s=]+))", child.header)
                if m:
                    found.add((table, (m.group(1) or m.group(2)).replace("''", "'")))
    return found


def test_the_reference_inputs_list_exactly_the_tables_and_measures_of_the_tmdl(repo_root):
    """The inputs came from the engine, the TMDL from disk: they must agree on what the model contains."""
    data = model_docs.read_inputs(repo_root)
    assert {(m["Table"], m["Measure"]) for m in data["measures"]} == _tmdl_measures(repo_root)
    tables = {
        n.header[len("table ") :].strip().strip("'")
        for p in ledger.model_files(repo_root)
        for n in ledger._parse_tmdl(p.read_text(encoding="utf-8-sig")).children
        if n.header.startswith("table ")
    }
    assert {t["Table"] for t in data["tables"]} == tables


def test_a_missing_input_names_the_command_that_writes_it(tmp_path):
    with pytest.raises(model_docs.ModelDocsError, match="run_dax_tests.ps1"):
        model_docs.read_inputs(tmp_path)
