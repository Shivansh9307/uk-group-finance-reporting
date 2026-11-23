"""The Tabular Editor scripts, the Best Practice Analyzer rule file and the perspectives, read as text.

These tests need neither Desktop, Tabular Editor nor a database. They check that what the scripts are meant to write is
in the TMDL files (so a script that was not run, or a file edited by hand against the script, fails here), that the rule
file and the committed BPA counts agree with each other, and that tools/summarise_bpa.py reads a result file the way it
says. Running Tabular Editor and comparing its result with evidence/bpa is the CI job `model-bpa`.
"""

from __future__ import annotations

import csv
import importlib.util
import json
import re
import subprocess
import sys
from pathlib import Path

import pytest

MODEL = Path("model") / "UKGroupFinance.SemanticModel" / "definition"
SCRIPTS = Path("te") / "scripts"
BPA = Path("te") / "bpa"
EVIDENCE = Path("evidence") / "bpa"


def _unquote(name: str) -> str:
    name = name.strip()
    if name.startswith("'") and name.endswith("'"):
        return name[1:-1].replace("''", "'")
    return name


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8").replace("\r\n", "\n")


# ------------------------------------------------------------------------------------------------ the model, minimal
def _tables(repo_root) -> dict[str, dict]:
    """table name -> {measures: {name: props}, columns: {name: props}, text}. Only what these tests need."""
    out = {}
    for path in sorted((repo_root / MODEL / "tables").glob("*.tmdl")):
        text = _read(path)
        name = ""
        measures: dict[str, dict] = {}
        columns: dict[str, dict] = {}
        hierarchies: dict[str, dict] = {}
        current = None
        pending: list[str] = []
        description = ""
        for line in text.split("\n"):
            s = line.strip()
            if s.startswith("///"):
                pending.append(s[3:].strip())
                continue
            if line.startswith("table "):
                name = _unquote(line[len("table ") :])
                description = " ".join(pending)
                pending, current = [], None
                continue
            m = re.match(r"^\t(measure|column|hierarchy) (.+?)(?: =.*)?$", line)
            if m:
                kind, ident = m.group(1), _unquote(m.group(2))
                bag = {"measure": measures, "column": columns, "hierarchy": hierarchies}[kind]
                current = {
                    "flags": set(),
                    "description": " ".join(pending),
                    "expr": line.split(" =", 1)[1].strip() if " =" in line else "",
                }
                bag[ident] = current
                pending = []
                continue
            if re.match(r"^\t\S", line):
                current, pending = None, []
                continue
            if current is not None and line.startswith("\t\t") and not line.startswith("\t\t\t"):
                if ":" in s:
                    k, v = s.split(":", 1)
                    current[k.strip()] = v.strip()
                else:
                    current["flags"].add(s)
        out[name] = {
            "measures": measures,
            "columns": columns,
            "hierarchies": hierarchies,
            "text": text,
            "description": description,
        }
    return out


@pytest.fixture(scope="module")
def tables(repo_root):
    return _tables(repo_root)


# ---------------------------------------------------------------------------------------------------- scripts exist
def test_every_script_has_a_header_that_says_what_it_does_and_how_to_run_it(repo_root):
    scripts = sorted((repo_root / SCRIPTS).glob("*.csx"))
    assert {p.stem for p in scripts} >= {
        "real_terms_measures",
        "display_folders",
        "descriptions",
        "perspectives",
        "mdx_availability",
        "bpa_ignores",
    }
    for p in scripts:
        text = _read(p)
        head = text.split("\n\n", 1)[0]
        assert head.startswith(f"// {p.name}"), p.name
        assert "tools\\run_te_script.ps1 -Script te\\scripts\\" + p.name in text, f"{p.name} does not say how to run it"
        assert "Running it twice gives no second change" in text or p.stem == "descriptions", p.name


# ------------------------------------------------------------------------------------------------------ real terms
def _real_terms_sources(repo_root) -> list[str]:
    text = _read(repo_root / SCRIPTS / "real_terms_measures.csx")
    block = re.search(r"var sources = new List<string>\s*\{(.*?)\};", text, re.S)
    assert block, "the list of sources is not at the top of real_terms_measures.csx"
    return re.findall(r'"([^"]+)"', block.group(1))


def test_every_real_terms_source_has_its_twin_in_the_same_table_with_folder_description_and_a_one_line_call(
    tables, repo_root
):
    sources = _real_terms_sources(repo_root)
    assert len(sources) >= 7 and len(set(sources)) == len(sources)
    for name in sources:
        homes = [t for t, d in tables.items() if name in d["measures"]]
        assert len(homes) == 1, f"{name} is in {homes}"
        home = tables[homes[0]]
        twin = home["measures"].get(f"{name} (real terms)")
        assert twin is not None, f"{name} has no real-terms twin in {homes[0]}"
        source = home["measures"][name]
        assert twin["expr"] == f"Real.Deflate ( [{name}] )", twin["expr"]
        assert twin["displayFolder"] == "Real Terms"
        assert twin["formatString"] == source["formatString"]
        assert twin["description"] and "2025-26 prices" in twin["description"]
        assert "A month takes the index of its financial year" in twin["description"]
        assert "lineageTag" in twin


def test_a_real_terms_measure_exists_only_for_a_listed_source(tables, repo_root):
    sources = set(_real_terms_sources(repo_root))
    twins = {n[: -len(" (real terms)")] for d in tables.values() for n in d["measures"] if n.endswith(" (real terms)")}
    assert twins == sources


def test_the_phased_twin_keeps_the_derived_label(tables):
    phased = tables["Fact Plan Phased (derived)"]["measures"]["Plan (phased) (real terms)"]
    assert phased["description"].startswith("DERIVED")


def test_display_unit_scales_every_real_terms_measure_in_every_item(tables, repo_root):
    text = tables["Display Unit"]["text"]
    for name in _real_terms_sources(repo_root):
        # three items, each with the list in the value expression and the list in the format string expression
        assert text.count(f"[{name} (real terms)]") == 6, name


def test_the_deflation_is_written_once_by_index_year_and_never_falls_back_to_the_nominal_figure(repo_root):
    text = _read(repo_root / MODEL / "functions.tmdl")
    body = text.split("function 'Real.Deflate' =", 1)[1]
    assert "TREATAS" in text.split("function 'Real.Deflate' =", 1)[0].split("function 'Real.IndexTable' =", 1)[1]
    assert "IF ( AnyYearWithoutIndex, BLANK ()" in body
    assert "DIVIDE ( BaseIndex," in body
    # no measure carries its own copy of the deflation
    for p in (repo_root / MODEL / "tables").glob("*.tmdl"):
        for line in _read(p).split("\n"):
            if "(real terms)" in line and line.startswith("\tmeasure"):
                assert line.rstrip().endswith(
                    "= Real.Deflate ( [" + line.split("measure '")[1].split(" (real terms)'")[0] + "] )"
                ), line


# --------------------------------------------------------------------------------------------------- display folders
def test_every_visible_measure_folder_is_the_one_the_script_gives(tables, repo_root):
    text = _read(repo_root / SCRIPTS / "display_folders.csx")
    convention = dict(re.findall(r'\{ "([^"]+)", @?"([^"]+)" \}', text))
    assert convention, "no convention table in display_folders.csx"
    seen = set()
    for t in tables.values():
        for name, m in t["measures"].items():
            if "isHidden" in m["flags"]:
                # the script leaves hidden measures alone; the two kept as evidence sit in one folder by hand
                folder = m.get("displayFolder")
                assert folder == r"Performance\Naive", f"{name}: a hidden measure sits in {folder}"
                assert name not in convention, f"{name} is hidden and so must not be in the convention table"
                continue
            want = "Real Terms" if name.endswith(" (real terms)") else convention.get(name)
            assert want is not None, f"display_folders.csx has no folder for {name}"
            assert m.get("displayFolder") == want, f"{name}: {m.get('displayFolder')} != {want}"
            seen.add(name)
    assert set(convention) <= seen, sorted(set(convention) - seen)


def test_the_authored_and_derived_tables_say_so_and_keep_their_columns_in_a_folder(tables):
    authored = ["Scenario", "Spending Review Group", "Plan Source", "Plan Grain", "Statement Line", "Statement Measure"]
    for name in authored:
        assert tables[name]["description"].startswith("AUTHORED"), name
        if name != "Statement Measure":
            visible = [c for c in tables[name]["columns"].values() if "isHidden" not in c["flags"]]
            assert visible and all(c.get("displayFolder") == "Authored" for c in visible), name
    assert tables["Fact Plan Phased (derived)"]["description"].startswith("DERIVED")
    for real in ("Fact Outturn", "Fact Plan"):
        assert not tables[real]["description"].startswith(("AUTHORED", "DERIVED"))


# ------------------------------------------------------------------------------------------------------ perspectives
def _perspective_files(repo_root) -> dict[str, dict]:
    out = {}
    for path in sorted((repo_root / MODEL / "perspectives").glob("*.tmdl")):
        text = _read(path)
        name = None
        description = []
        table = None
        objects: set[tuple[str, str, str]] = set()
        for line in text.split("\n"):
            s = line.strip()
            if line.startswith("///"):
                description.append(s[3:].strip())
            elif line.startswith("perspective "):
                name = _unquote(line[len("perspective ") :])
            elif s.startswith("perspectiveTable "):
                table = _unquote(s[len("perspectiveTable ") :])
                objects.add((table, "table", ""))
            elif s.startswith(("perspectiveColumn ", "perspectiveMeasure ", "perspectiveHierarchy ")):
                kind, ident = s.split(" ", 1)
                objects.add((table, kind[len("perspective") :].lower(), _unquote(ident)))
        out[name] = {"description": " ".join(description), "objects": objects}
    return out


def _csv_perspectives(repo_root) -> dict[str, dict]:
    out: dict[str, dict] = {}
    with (repo_root / SCRIPTS / "perspectives.csv").open(encoding="utf-8", newline="") as fh:
        for row in csv.DictReader(fh):
            p = out.setdefault(row["perspective"], {"description": "", "entries": []})
            if not row["object"].strip():
                p["description"] = row["description"]
            else:
                p["entries"].append(row["object"].strip())
    return out


PLURAL = {"column": "columns", "measure": "measures", "hierarchy": "hierarchies"}


def _expand(entries, tables) -> set[tuple[str, str, str]]:
    want: set[tuple[str, str, str]] = set()
    for e in entries:
        m = re.match(r"^(.+?)\[(.+)\]$", e)
        if m:
            t, obj = m.group(1), m.group(2)
            kind = "measure" if obj in tables[t]["measures"] else "column"
            assert obj in tables[t][PLURAL[kind]], e
            assert "isHidden" not in tables[t][PLURAL[kind]][obj]["flags"], f"{e} is hidden"
            want.add((t, "table", ""))
            want.add((t, kind, obj))
        else:
            assert e in tables, e
            want.add((e, "table", ""))
            for kind in ("column", "measure", "hierarchy"):
                for obj, props in tables[e][PLURAL[kind]].items():
                    if "isHidden" not in props["flags"]:
                        want.add((e, kind, obj))
    return want


def test_the_perspectives_in_the_model_are_exactly_the_ones_in_the_csv(tables, repo_root):
    in_model = _perspective_files(repo_root)
    in_csv = _csv_perspectives(repo_root)
    assert set(in_model) == set(in_csv) == {"Executive", "Restatement", "Data Controls"}
    model_text = _read(repo_root / MODEL / "model.tmdl")
    for name in in_csv:
        assert f"ref perspective {name}" in model_text or f"ref perspective '{name}'" in model_text
        assert (
            in_model[name]["description"] == in_csv[name]["description"].strip() and in_csv[name]["description"].strip()
        )
        assert in_model[name]["objects"] == _expand(in_csv[name]["entries"], tables), name


def test_a_perspective_holds_only_visible_objects_and_what_its_calculation_groups_need_to_run(tables, repo_root):
    in_model = _perspective_files(repo_root)
    for name, p in in_model.items():
        tables_in = {t for t, kind, _ in p["objects"] if kind == "table"}
        for t, kind, obj in p["objects"]:
            if kind in ("column", "measure"):
                assert "isHidden" not in tables[t][PLURAL[kind]][obj]["flags"], f"{name}: {t}[{obj}] is hidden"
        # a measure's own table is in the perspective with it, and the time calculation needs the periods and the years
        if "Time Intelligence" in tables_in:
            assert {"Fiscal Period", "Fiscal Year"} <= tables_in, name
        if "Scenario Comparison" in tables_in:
            assert {"Fiscal Year"} <= tables_in, name
    executive = {t for t, k, _ in in_model["Executive"]["objects"] if k == "table"}
    assert not executive & {"Data Quality Issue", "Release", "Deflator Quarantine", "CPI Quarantine", "Deflator", "CPI"}
    controls = {t for t, k, _ in in_model["Data Controls"]["objects"] if k == "table"}
    assert {"Deflator Quarantine", "CPI Quarantine", "Plan Grain", "Plan Source", "Data Quality Issue"} <= controls
    restatement_measures = {o for t, k, o in in_model["Restatement"]["objects"] if k == "measure"}
    assert "Outturn as at Release" in restatement_measures and "Plan" not in restatement_measures


# ------------------------------------------------------------------------------------------------------- BPA rules
def _rules(repo_root) -> list[dict]:
    return json.loads((repo_root / BPA / "rules.json").read_text(encoding="utf-8"))


def test_the_rule_file_parses_and_every_rule_has_what_tabular_editor_needs(repo_root):
    rules = _rules(repo_root)
    ids = [r["ID"] for r in rules]
    assert len(ids) == len(set(ids)) and ids == sorted(ids)
    allowed = {
        "ID",
        "Name",
        "Category",
        "Description",
        "Severity",
        "Scope",
        "Expression",
        "FixExpression",
        "CompatibilityLevel",
        "Source",
    }
    for r in rules:
        assert set(r) <= allowed, (r["ID"], set(r) - allowed)
        assert {"ID", "Name", "Category", "Description", "Severity", "Scope", "Expression"} <= set(r), r["ID"]
        assert r["Severity"] in (1, 2, 3) and r["Description"].strip() and r["Expression"].strip(), r["ID"]
    mine = [r for r in rules if r["ID"].startswith("UKFR_")]
    assert len(mine) >= 10 and all(r["Source"] == "Project" for r in mine)
    assert all(r["Source"] != "Project" for r in rules if not r["ID"].startswith("UKFR_"))
    required = {
        "UKFR_NO_INACTIVE_RELATIONSHIPS",
        "UKFR_NO_BIDIRECTIONAL_RELATIONSHIPS",
        "UKFR_MEASURE_NAME_NOT_A_COLUMN_NAME",
        "UKFR_DESCRIBE_VISIBLE_OBJECT",
        "UKFR_MEASURE_FOLDER_AND_FORMAT",
        "UKFR_LABEL_AUTHORED_TABLE",
        "UKFR_LABEL_DERIVED_TABLE",
        "UKFR_NO_DOUBLE_AMOUNT",
        "UKFR_DIVIDE_NOT_SLASH",
        "UKFR_NO_IFERROR",
        "UKFR_RELATIONSHIP_COLUMNS_HIDDEN",
    }
    assert required <= set(ids)


def test_every_rule_dropped_from_the_standard_set_has_a_reason_in_the_readme(repo_root):
    readme = _read(repo_root / BPA / "README.md")
    rules = {r["ID"] for r in _rules(repo_root)}
    dropped = set(re.findall(r"^\| `([A-Z0-9_()/'\-]+)` \| dropped \|", readme, re.M))
    assert dropped, "te/bpa/README.md has no table of dropped rules"
    assert not dropped & rules
    for rule in rules:
        if rule.startswith("UKFR_"):
            assert f"`{rule}`" in readme, f"{rule} is not described in te/bpa/README.md"


def test_the_ignore_file_matches_the_annotations_in_the_model_and_every_row_has_a_reason(tables, repo_root):
    rows = list(csv.DictReader((repo_root / BPA / "ignores.csv").open(encoding="utf-8", newline="")))
    rule_ids = {r["ID"] for r in _rules(repo_root)}
    objects = set()
    for r in rows:
        assert r["reason"].strip() and r["rule_id"] in rule_ids, r
        assert not r["reason"].lower().startswith("blanket")
        objects.add(r["object"])
    annotated = 0
    for t in tables.values():
        annotated += t["text"].count("annotation BestPracticeAnalyzer_IgnoreRules")
    assert annotated == len(objects), (annotated, len(objects))
    # the rule ids written in the model are exactly the ones in the file
    in_model = []
    for t in tables.values():
        for m in re.finditer(r'annotation BestPracticeAnalyzer_IgnoreRules = \{"RuleIDs":\[(.*?)\]\}', t["text"]):
            in_model += re.findall(r'"([^"]+)"', m.group(1))
    assert sorted(in_model) == sorted(r["rule_id"] for r in rows)
    readme = _read(repo_root / BPA / "README.md")
    for r in rows:
        assert r["object"] in readme, f"{r['object']} is not in the README list of ignores"


def test_no_blanket_ignore_is_written_at_model_level(repo_root):
    assert "BestPracticeAnalyzer_IgnoreRules" not in _read(repo_root / MODEL / "model.tmdl")


# --------------------------------------------------------------------------------------- committed counts, the tool
def test_the_committed_counts_cover_every_rule_in_the_file_and_nothing_at_severity_three_is_violated(repo_root):
    rules = {r["ID"]: r["Severity"] for r in _rules(repo_root)}
    raw = (repo_root / EVIDENCE / "bpa_counts.csv").read_bytes()
    assert b"\r" not in raw and raw.endswith(b"\n")
    rows = list(csv.DictReader(raw.decode("utf-8").splitlines()))
    assert [r["rule_id"] for r in rows] == sorted(rules), "bpa_counts.csv must list every rule, sorted"
    for r in rows:
        assert int(r["severity"]) == rules[r["rule_id"]], r
        if rules[r["rule_id"]] >= 3:
            assert int(r["violations"]) == 0, f"{r['rule_id']} fails the build"
    violations = list(
        csv.DictReader((repo_root / EVIDENCE / "bpa_violations.csv").read_bytes().decode("utf-8").splitlines())
    )
    assert sum(int(r["violations"]) for r in rows) == len(violations)
    assert [tuple(v.values()) for v in violations] == sorted(tuple(v.values()) for v in violations)
    text = (repo_root / EVIDENCE / "bpa_violations.csv").read_text(encoding="utf-8")
    assert not re.search(r"[A-Za-z]:\\|/Users/|/home/", text)


def _load_tool(repo_root):
    spec = importlib.util.spec_from_file_location("summarise_bpa", repo_root / "tools" / "summarise_bpa.py")
    mod = importlib.util.module_from_spec(spec)
    sys.modules["summarise_bpa"] = mod
    spec.loader.exec_module(mod)
    return mod


TRX = """<?xml version="1.0" encoding="utf-8"?>
<TestRun xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010">
  <Results>
    <UnitTestResult testId="1" outcome="Failed"><Output><ErrorInfo><Message>2 object(s) in violation of rule</Message>
      <StackTrace>Objects in violation:
  'Deflator' (Table (Import))
  [Outturn (current structure)] (Measure)</StackTrace></ErrorInfo></Output></UnitTestResult>
    <UnitTestResult testId="2" outcome="Passed" />
    <UnitTestResult testId="3" outcome="{third}" />
  </Results>
  <TestDefinitions>
    <UnitTest name="a" id="1"><Properties><Property><Key>Severity</Key><Value>2</Value></Property><Property><Key>RuleID</Key><Value>RULE_B</Value></Property></Properties></UnitTest>
    <UnitTest name="b" id="2"><Properties><Property><Key>Severity</Key><Value>3</Value></Property><Property><Key>RuleID</Key><Value>RULE_A</Value></Property></Properties></UnitTest>
    <UnitTest name="c" id="3"><Properties><Property><Key>Severity</Key><Value>1</Value></Property><Property><Key>RuleID</Key><Value>RULE_C</Value></Property></Properties></UnitTest>
  </TestDefinitions>
</TestRun>
"""  # noqa: E501


def test_the_summary_tool_counts_objects_by_rule_and_sorts_and_catches_a_difference(repo_root, tmp_path):
    tool = repo_root / "tools" / "summarise_bpa.py"
    trx = tmp_path / "run.trx"
    trx.write_text(TRX.replace("{third}", "Passed"), encoding="utf-8")
    out = tmp_path / "out"
    run = lambda *a: subprocess.run([sys.executable, "-I", str(tool), *a], capture_output=True, text=True)  # noqa: E731
    assert run("--trx", str(trx), "--write", str(out)).returncode == 0
    assert (out / "bpa_counts.csv").read_text(
        encoding="utf-8"
    ) == "rule_id,severity,violations\nRULE_A,3,0\nRULE_B,2,2\nRULE_C,1,0\n"
    assert (out / "bpa_violations.csv").read_text(encoding="utf-8") == (
        "rule_id,object_type,object_name\n"
        "RULE_B,Measure,[Outturn (current structure)]\n"
        "RULE_B,Table (Import),'Deflator'\n"
    )
    assert run("--trx", str(trx), "--check", str(out)).returncode == 0
    (out / "bpa_counts.csv").write_text("rule_id,severity,violations\nRULE_A,3,1\n", encoding="utf-8")
    again = run("--trx", str(trx), "--check", str(out))
    assert again.returncode == 1 and "RULE_B,2,2" in again.stdout
    trx.write_text(TRX.replace("{third}", "Inconclusive"), encoding="utf-8")
    broken = run("--trx", str(trx), "--check", str(out))
    assert broken.returncode == 2 and "RULE_C" in broken.stderr
