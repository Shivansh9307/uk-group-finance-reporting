"""The semantic model's TMDL files, read as text: structure, labels, sources and the rules of the model contract.

These tests need neither Desktop nor a database. They parse only what they need (table, column and relationship
declarations, the partition source), so a convention that a later edit breaks fails here before anyone opens Desktop.
"""

from __future__ import annotations

import csv
import re
from dataclasses import dataclass, field
from pathlib import Path

import pytest

MODEL = Path("model") / "UKGroupFinance.SemanticModel"


def _unquote(name: str) -> str:
    name = name.strip()
    if name.startswith("'") and name.endswith("'"):
        return name[1:-1].replace("''", "'")
    return name


@dataclass
class Column:
    name: str
    props: dict[str, str] = field(default_factory=dict)
    flags: set[str] = field(default_factory=set)
    description: str = ""


@dataclass
class Table:
    name: str
    description: str
    columns: dict[str, Column]
    partition_source: str
    text: str


def _parse_table(path: Path) -> Table:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    description, name = "", ""
    columns: dict[str, Column] = {}
    current: Column | None = None
    pending: list[str] = []
    partition_lines: list[str] = []
    in_partition = False
    for line in lines:
        if line.strip().startswith("///"):
            pending.append(line.strip()[3:].strip())
            continue
        m = re.match(r"^table (.+)$", line)
        if m:
            name = _unquote(m.group(1))
            description = " ".join(pending)
            pending = []
            continue
        m = re.match(r"^\tcolumn (.+)$", line)
        if m:
            current = Column(_unquote(m.group(1)), description=" ".join(pending))
            columns[current.name] = current
            pending, in_partition = [], False
            continue
        if re.match(r"^\t(hierarchy|partition|measure) ", line):
            current, in_partition = None, line.startswith("\tpartition")
            pending = []
            continue
        if in_partition:
            partition_lines.append(line)
        elif current is not None and line.startswith("\t\t") and not line.startswith("\t\t\t"):
            body = line.strip()
            if ":" in body:
                k, v = body.split(":", 1)
                current.props[k.strip()] = v.strip()
            else:
                current.flags.add(body)
        if not line.strip():
            pending = []
    return Table(name, description, columns, "\n".join(partition_lines), text)


@pytest.fixture(scope="module")
def model_dir(repo_root) -> Path:
    return repo_root / MODEL / "definition"


@pytest.fixture(scope="module")
def tables(model_dir) -> dict[str, Table]:
    out = {}
    for p in sorted((model_dir / "tables").glob("*.tmdl")):
        t = _parse_table(p)
        assert t.name, p
        assert p.stem == t.name, f"{p.name}: the file is named differently from its table {t.name}"
        out[t.name] = t
    return out


@pytest.fixture(scope="module")
def relationships(model_dir) -> list[dict[str, str]]:
    text = (model_dir / "relationships.tmdl").read_text(encoding="utf-8")
    out = []
    for block in re.split(r"\n(?=relationship )", text.strip()):
        props = {}
        for line in block.splitlines()[1:]:
            k, _, v = line.strip().partition(":")
            props[k.strip()] = v.strip()
        out.append(props)
    return out


def _split_column(ref: str) -> tuple[str, str]:
    """`'Fact Outturn'.'Release Key'` -> ('Fact Outturn', 'Release Key')."""
    m = re.match(r"^('(?:[^']|'')+'|[^.]+)\.(.+)$", ref)
    assert m, ref
    return _unquote(m.group(1)), _unquote(m.group(2))


# --------------------------------------------------------------------------------------------- model file
def test_the_model_is_at_compatibility_level_1702_with_auto_date_time_off(model_dir):
    assert "compatibilityLevel: 1702" in (model_dir / "database.tmdl").read_text(encoding="utf-8")
    model = (model_dir / "model.tmdl").read_text(encoding="utf-8")
    assert "annotation __PBI_TimeIntelligenceEnabled = 0" in model
    assert "discourageImplicitMeasures" in model


def test_every_table_file_is_referenced_by_the_model_and_back(model_dir, tables):
    refs = set()
    for line in (model_dir / "model.tmdl").read_text(encoding="utf-8").splitlines():
        m = re.match(r"^ref table (.+)$", line)
        if m:
            refs.add(_unquote(m.group(1)))
    assert refs == set(tables)


def test_the_model_has_no_refresh_policy_no_range_parameters_and_no_date_table(model_dir, tables):
    all_text = "\n".join(p.read_text(encoding="utf-8") for p in model_dir.rglob("*.tmdl"))
    for banned in ("refreshPolicy", "RangeStart", "RangeEnd", "dataCategory: Time"):
        assert banned not in all_text, banned
    assert not (model_dir / "roles").exists(), "security is a later task"


# ------------------------------------------------------------------------------------------------ tables
def test_every_table_has_a_description(tables):
    missing = [n for n, t in tables.items() if len(t.description) < 40]
    assert not missing, missing


def test_every_visible_column_has_a_description_and_every_column_is_not_summarised(tables):
    for n, t in tables.items():
        for c in t.columns.values():
            assert c.props.get("summarizeBy") == "none", f"{n}[{c.name}] must be summarizeBy: none"
            if "isHidden" not in c.flags:
                assert c.description, f"{n}[{c.name}] is visible and has no description"


def test_keys_and_technical_columns_are_hidden(tables):
    for n, t in tables.items():
        for c in t.columns.values():
            src = c.props.get("sourceColumn", "")
            durable = src in ("durable_key", "successor_durable_key")  # business attributes, not surrogate keys
            if not durable and (
                src.endswith("_key")
                or c.name.endswith(" Key")
                or c.name in ("Amount Delta", "Plan Amount", "Phased Amount")
            ):
                assert "isHidden" in c.flags, f"{n}[{c.name}] is a key or an amount and must be hidden"


def test_sort_by_columns_exist_and_are_hidden_or_visible_on_purpose(tables):
    for n, t in tables.items():
        for c in t.columns.values():
            s = c.props.get("sortByColumn")
            if s:
                assert _unquote(s) in t.columns, f"{n}[{c.name}] sorts by a column that is not in the table"


def test_each_sql_table_reads_one_view_with_the_server_and_database_parameters(tables, repo_root):
    views = set()
    view_files = sorted((repo_root / "sql" / "dw").glob("7[0467]?_*.sql"))
    view_files += sorted((repo_root / "sql" / "audit").glob("78?_*.sql"))
    sql_text = "\n".join(p.read_text(encoding="utf-8") for p in view_files)
    created = set(re.findall(r"CREATE VIEW dw\.(v_model_\w+)", sql_text))
    used: list[str] = []
    for n, t in tables.items():
        if "Sql.Database(Server, Database)" in t.partition_source:
            m = re.search(r'Schema = "dw", Item = "(v_model_\w+)"', t.partition_source)
            assert m, f"{n}: a SQL partition must navigate to a dw.v_model_ view"
            used.append(m.group(1))
            assert "Web.Contents" not in t.partition_source, f"{n}: a table must not read both SQL and the web"
            assert "Table.Join" not in t.partition_source and "Table.NestedJoin" not in t.partition_source
        else:
            views.add(n)
    assert len(used) == len(set(used)), "two tables read the same view"
    assert set(used) == created, sorted(set(used) ^ created)
    calculation_groups = {
        n for n, t in tables.items() if "	calculationGroup" in t.text and not t.partition_source.strip()
    }
    assert calculation_groups == {"Time Intelligence", "Scenario Comparison", "Display Unit"}
    web_tables = {"Deflator", "Deflator Quarantine", "CPI", "CPI Quarantine"}
    assert views - calculation_groups == web_tables | {"Statement Measure"}
    # the one calculated table is the field parameter: a table constructor of NAMEOF references and no source data
    parameter = tables["Statement Measure"]
    assert "= calculated" in parameter.text and "NAMEOF" in parameter.partition_source


def test_derived_and_real_tables_are_labelled(tables):
    phased = tables["Fact Plan Phased (derived)"]
    assert phased.description.startswith("DERIVED"), "the phased plan must say DERIVED first"
    visible = [c for c in phased.columns.values() if "isHidden" not in c.flags]
    assert visible and all(c.props.get("displayFolder") == "Derived" for c in visible)
    for name in ("Fact Outturn", "Fact Plan"):
        assert "derived" not in tables[name].description.lower().replace("not derived", "")


# ----------------------------------------------------------------------------------------- relationships
def test_every_relationship_joins_existing_columns_and_is_active_single_direction_many_to_one(relationships, tables):
    assert len(relationships) == 23
    seen = set()
    for r in relationships:
        for end in ("fromColumn", "toColumn"):
            table, col = _split_column(r[end])
            assert table in tables and col in tables[table].columns, f"{r[end]} does not exist"
        assert r.get("isActive") in (None, "true"), "no inactive relationship"
        assert r.get("crossFilteringBehavior") in (None, "oneDirection"), "single direction only"
        assert "fromCardinality" not in r and "toCardinality" not in r, "default many-to-one only"
        key = (r["fromColumn"], r["toColumn"])
        assert key not in seen
        seen.add(key)


def test_the_one_side_of_every_relationship_is_a_key_column_of_a_dimension(relationships, tables):
    for r in relationships:
        t, c = _split_column(r["toColumn"])
        assert "isKey" in tables[t].columns[c].flags, f"{t}[{c}] is the one side and must be marked isKey"
        assert not t.startswith("Fact "), f"{t} is a fact and is on the one side of {r}"


def test_the_many_side_columns_of_the_facts_are_hidden(relationships, tables):
    for r in relationships:
        t, c = _split_column(r["fromColumn"])
        if t.startswith("Fact "):
            assert "isHidden" in tables[t].columns[c].flags, f"{t}[{c}] must be hidden"


def test_the_deflator_and_cpi_tables_are_not_related_to_anything(relationships):
    touched = {_split_column(r[e])[0] for r in relationships for e in ("fromColumn", "toColumn")}
    assert touched.isdisjoint({"Deflator", "Deflator Quarantine", "CPI", "CPI Quarantine"})


# ------------------------------------------------------------------------------- the web sources, one place
def test_the_web_links_are_the_manifest_links_and_appear_once_in_one_expression(model_dir, repo_root):
    manifest = {}
    with (repo_root / "data" / "manifest" / "files.csv").open(encoding="utf-8", newline="") as fh:
        for r in csv.DictReader(fh):
            if r["source_id"] in ("gdp_deflator", "ons_cpi"):
                manifest[r["file_url"]] = r["source_id"]
    assert len(manifest) == 5
    found: dict[str, list[str]] = {}
    for p in model_dir.rglob("*.tmdl"):
        for url in re.findall(r'https?://[^"\s]+', p.read_text(encoding="utf-8")):
            found.setdefault(url, []).append(p.name)
    assert set(found) == set(manifest), set(found) ^ set(manifest)
    for url, files in found.items():
        assert files == ["expressions.tmdl"], f"{url} appears outside expressions.tmdl: {files}"


def test_the_parse_functions_find_things_by_header_text_not_position(model_dir):
    text = (model_dir / "expressions.tmdl").read_text(encoding="utf-8")
    assert '"Financial year"' in text and '"= 100"' in text and '"per cent change"' in text.lower()
    assert "fnParseGdpDeflator" in text and "fnParseCpi" in text
    for banned in ("Sheet1", "Column1", "{[Item"):
        assert banned not in text.split("fnParseGdpDeflator", 1)[1], banned


def test_server_and_database_are_parameters_with_the_local_defaults(model_dir):
    text = (model_dir / "expressions.tmdl").read_text(encoding="utf-8")
    assert re.search(r'expression Server = "localhost" meta \[IsParameterQuery = true', text)
    assert re.search(r'expression Database = "UKGroupFinance" meta \[IsParameterQuery = true', text)


# ------------------------------------------------------------------------------------------ what leaks
def test_no_local_path_machine_or_account_name_is_in_the_model_or_the_test_files(repo_root):
    bad = re.compile(r"[A-Za-z]:\\\\?Users|/Users/|C:\\\\|AppData|\\\\\\\\[A-Za-z0-9_-]+\\\\", re.IGNORECASE)
    roots = [
        repo_root / "model",
        repo_root / "tests" / "dax",
        repo_root / "tests" / "expected",
        repo_root / "tests" / "results",
    ]
    for root in roots:
        for p in root.rglob("*"):
            if p.is_file() and p.suffix in (
                ".tmdl",
                ".json",
                ".dax",
                ".sql",
                ".csv",
                ".pbip",
                ".pbir",
                ".pbism",
                ".py",
            ):
                text = p.read_text(encoding="utf-8", errors="replace")
                assert not bad.search(text), f"{p.relative_to(repo_root)} holds a local path"


# ------------------------------------------------------------------------------------------- the tests
def test_dax_tests_only_name_tables_and_columns_that_exist(repo_root, tables):
    ref = re.compile(r"'((?:[^']|'')+)'\[([^\]]+)\]|\b([A-Za-z_][A-Za-z0-9_]*)\[([^\]]+)\]")
    for p in sorted((repo_root / "tests" / "dax").glob("*.dax")):
        text = re.sub(r"//[^\n]*", "", p.read_text(encoding="utf-8"))
        defined = set(re.findall(r"MEASURE\s+'[^']+'\[([^\]]+)\]", text))
        for m in ref.finditer(text):
            table = (m.group(1) or m.group(3)).replace("''", "'")
            col = m.group(2) or m.group(4)
            if col in defined:
                continue
            assert table in tables, f"{p.name}: no table {table}"
            assert col in tables[table].columns, f"{p.name}: no column {table}[{col}]"
