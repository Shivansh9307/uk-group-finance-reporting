"""The measures, calculation groups and functions of the semantic model, read as text.

Like test_model_files.py these tests need neither Desktop nor a database. They check the conventions that the DAX tests
cannot: that every measure and calculation item is described and formatted, that no format string scales with commas,
that the calendar time-intelligence functions are not used, that every function is defined once, quoted, and used, and
that the derived monthly plan is read by exactly one measure.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

import pytest

MODEL = Path("model") / "UKGroupFinance.SemanticModel" / "definition"
CALENDAR_FUNCTIONS = (
    "DATESYTD",
    "DATESMTD",
    "DATESQTD",
    "TOTALYTD",
    "TOTALMTD",
    "TOTALQTD",
    "SAMEPERIODLASTYEAR",
    "DATEADD",
    "PREVIOUSYEAR",
    "PREVIOUSMONTH",
    "PARALLELPERIOD",
    "DATESINPERIOD",
    "DATESBETWEEN",
)
BASE_MEASURES = {
    "Outturn": ("Fact Outturn", "Base"),
    "Outturn (plan basis)": ("Fact Outturn", "Plan"),
    "Comparison Amount": ("Fact Outturn", "Plan"),
    "Plan": ("Fact Plan", "Plan"),
    "Plan Below Grain": ("Fact Plan", "Plan"),
    "Plan (phased)": ("Fact Plan Phased (derived)", "Plan\\Derived"),
}
GROUPS = {"Scenario Comparison": 10, "Time Intelligence": 20, "Display Unit": 30}


def _unquote(name: str) -> str:
    name = name.strip()
    if name.startswith("'") and name.endswith("'"):
        return name[1:-1].replace("''", "'")
    return name


@dataclass
class Measure:
    table: str
    name: str
    description: str
    expression: str
    props: dict[str, str]


@dataclass
class Item:
    group: str
    name: str
    description: str
    expression: str
    props: dict[str, str]
    format_expression: str


def _blocks(text: str, header: re.Pattern[str], indent: int) -> list[tuple[str, list[str], list[str]]]:
    """Split `text` at lines matching `header`; return (name, description lines, body lines) for each."""
    lines = text.splitlines()
    out = []
    pending: list[str] = []
    current = None
    for line in lines:
        stripped = line.strip()
        depth = len(line) - len(line.lstrip("\t"))
        if stripped.startswith("///") and depth == indent:
            pending.append(stripped[3:].strip())
            continue
        m = header.match(line)
        if m:
            current = (m.group(1), pending, [])
            out.append(current)
            pending = []
            continue
        if current is not None and (not stripped or depth > indent):
            current[2].append(line)
        elif stripped:
            current = None
            pending = []
    return out


def _split_body(body: list[str], indent: int) -> tuple[str, dict[str, str], str]:
    """Expression lines (deeper than the properties), property lines (`key: value`), and a `formatStringDefinition`."""
    expr: list[str] = []
    props: dict[str, str] = {}
    fmt: list[str] = []
    target = expr
    for line in body:
        stripped = line.strip()
        depth = len(line) - len(line.lstrip("\t"))
        if depth == indent + 1 and stripped:
            if stripped.startswith("formatStringDefinition"):
                fmt = [stripped.split("=", 1)[1].strip()]
                target = fmt
                continue
            m = re.match(r"^(\w+):\s*(.*)$", stripped)
            if m:
                props[m.group(1)] = m.group(2)
                target = expr
                continue
            target = expr
        target.append(line)
    return "\n".join(expr), props, "\n".join(fmt)


@pytest.fixture(scope="module")
def model_dir(repo_root) -> Path:
    return repo_root / MODEL


@pytest.fixture(scope="module")
def table_text(model_dir) -> dict[str, str]:
    out = {}
    for p in sorted((model_dir / "tables").glob("*.tmdl")):
        out[p.stem] = p.read_text(encoding="utf-8")
    return out


@pytest.fixture(scope="module")
def measures(table_text) -> list[Measure]:
    found = []
    header = re.compile(r"^\tmeasure (.+?)(?: =(.*))?$")
    for table, text in table_text.items():
        lines = text.splitlines()
        pending: list[str] = []
        i = 0
        while i < len(lines):
            line = lines[i]
            if line.startswith("\t///"):
                pending.append(line.strip()[3:].strip())
            elif line.startswith("\tmeasure "):
                m = header.match(line)
                assert m, line
                name = _unquote(m.group(1).split(" =")[0])
                inline = (m.group(2) or "").strip()
                body: list[str] = []
                i += 1
                while i < len(lines) and (not lines[i].strip() or lines[i].startswith("\t\t")):
                    body.append(lines[i])
                    i += 1
                expr_lines = [inline] if inline else []
                props: dict[str, str] = {}
                for b in body:
                    depth = len(b) - len(b.lstrip("\t"))
                    s = b.strip()
                    if depth == 2 and re.match(r"^\w+:", s):
                        k, v = s.split(":", 1)
                        props[k] = v.strip()
                    elif s:
                        expr_lines.append(s)
                found.append(Measure(table, name, " ".join(pending), "\n".join(expr_lines), props))
                pending = []
                continue
            elif not line.strip():
                pending = []
            i += 1
    return found


@pytest.fixture(scope="module")
def items(table_text) -> list[Item]:
    out = []
    for group in GROUPS:
        text = table_text[group]
        for name, desc, body in _blocks(text, re.compile(r"^\t\tcalculationItem (.+?) =.*$"), 2):
            expr, props, fmt = _split_body(body, 2)
            first = [ln for ln in text.splitlines() if ln.startswith(f"\t\tcalculationItem {name} =")]
            inline = first[0].split(" =", 1)[1].strip() if first else ""
            out.append(Item(group, _unquote(name), " ".join(desc), (inline + "\n" + expr).strip(), props, fmt))
    return out


@pytest.fixture(scope="module")
def functions(model_dir) -> dict[str, str]:
    text = (model_dir / "functions.tmdl").read_text(encoding="utf-8")
    found = {}
    for m in re.finditer(r"^function (\S+) = ```(.*?)```", text, re.MULTILINE | re.DOTALL):
        found[m.group(1)] = m.group(2)
    return found


def _all_expressions(measures, items, functions) -> str:
    return "\n".join(
        [m.expression for m in measures]
        + [i.expression + "\n" + i.format_expression for i in items]
        + list(functions.values())
    )


# ------------------------------------------------------------------------------------------------ measures
def test_the_base_measures_exist_in_their_homes_with_a_folder(measures):
    by_name = {m.name: m for m in measures}
    assert set(by_name) == set(BASE_MEASURES), sorted(set(by_name) ^ set(BASE_MEASURES))
    for name, (table, folder) in BASE_MEASURES.items():
        assert by_name[name].table == table, f"{name} must live on {table}"
        assert by_name[name].props.get("displayFolder") == folder, f"{name}: display folder"


def test_every_measure_has_a_description_a_format_string_and_a_lineage_tag(measures):
    for m in measures:
        assert len(m.description) >= 60, f"{m.name}: a measure states what it is, its unit and its sign"
        assert m.props.get("formatString"), f"{m.name}: no format string"
        assert m.props.get("lineageTag"), f"{m.name}: no lineage tag"


def test_no_measure_shares_a_name_with_a_column_of_its_own_table(measures, table_text):
    for m in measures:
        columns = {c.lower() for c in re.findall(r"^\tcolumn (.+)$", table_text[m.table], re.MULTILINE)}
        columns = {_unquote(c).lower() for c in columns}
        assert m.name.lower() not in columns, f"{m.table}[{m.name}] is also a column"


def test_measure_names_are_unique_across_the_model(measures):
    names = [m.name.lower() for m in measures]
    assert len(names) == len(set(names))


def test_the_derived_phased_plan_is_read_by_one_measure_and_by_no_other(measures, items, functions):
    readers = [m.name for m in measures if "Fact Plan Phased (derived)" in m.expression]
    assert readers == ["Plan (phased)"], readers
    assert not any("Fact Plan Phased (derived)" in i.expression for i in items)
    assert not any("Fact Plan Phased (derived)" in body for body in functions.values())
    by_name = {m.name: m for m in measures}
    for real in ("Outturn", "Plan", "Outturn (plan basis)", "Comparison Amount"):
        assert "Phased" not in by_name[real].expression and "phased" not in by_name[real].expression.lower().replace(
            "plan (phased)", ""
        )
    assert "DERIVED" in by_name["Plan (phased)"].description
    assert "Derived" in by_name["Plan (phased)"].props["displayFolder"]


def test_outturn_is_a_plain_sum_of_the_deltas_and_never_filters_releases(measures):
    by_name = {m.name: m for m in measures}
    assert re.sub(r"\s+", " ", by_name["Outturn"].expression) == "SUM ( 'Fact Outturn'[Amount Delta] )"
    assert "Release" not in by_name["Outturn"].expression


def test_no_format_string_scales_with_a_comma(measures, items, functions):
    # a comma after the last digit placeholder divides by 1,000 on the engine and prints a wrong number on the canvas
    scaling = re.compile(r"[0#],(?![0#])")
    formats = [m.props["formatString"] for m in measures] + [i.format_expression for i in items]
    for body in functions.values():
        for literal in re.findall(r'"((?:[^"]|"")*)"', body):
            if "£" in literal or "%" in literal:
                formats.append(literal.replace('""', '"'))
    assert len(formats) > len(measures)
    for f in formats:
        assert not scaling.search(re.sub(r'"[^"]*"', "", f)), f"scaling comma in {f}"
    assert not any(",," in re.sub(r'"[^"]*"', "", f) for f in formats)


def test_the_calendar_time_intelligence_functions_are_not_used_anywhere(measures, items, functions, model_dir):
    text = _all_expressions(measures, items, functions).upper()
    for f in CALENDAR_FUNCTIONS:
        assert not re.search(rf"\b{f}\s*\(", text), f"{f} needs a date table; the model has none"


def test_no_float_is_used_for_an_amount_in_the_measures(measures):
    for m in measures:
        assert "CONVERT" not in m.expression.upper() or "DOUBLE" not in m.expression.upper()


# ---------------------------------------------------------------------------------------- calculation groups
def test_the_three_calculation_groups_have_distinct_precedence_with_display_unit_outermost(table_text):
    found = {}
    for name in GROUPS:
        m = re.search(r"^\t\tprecedence: (\d+)$", table_text[name], re.MULTILINE)
        assert m, f"{name} has no precedence"
        found[name] = int(m.group(1))
    assert found == GROUPS
    assert found["Display Unit"] > found["Time Intelligence"] > found["Scenario Comparison"]


def test_every_calculation_item_is_described_and_has_an_ordinal_and_the_items_are_the_ones_designed(items):
    expected = {
        "Scenario Comparison": ["Actual", "Plan", "Variance", "Variance %", "Favourable/Adverse"],
        "Time Intelligence": ["Current", "MTD", "QTD", "YTD", "PY", "YoY", "YoY %", "Rolling 12 months"],
        "Display Unit": ["£k", "£m", "£bn"],
    }
    for group, names in expected.items():
        mine = [i for i in items if i.group == group]
        assert [i.name for i in mine] == names, group
        assert [int(i.props["ordinal"]) for i in mine] == list(range(len(names))), f"{group}: ordinals"
        for i in mine:
            assert len(i.description) >= 40, f"{group}.{i.name}: describe the item"


def test_the_scenario_comparison_acts_only_on_the_comparison_measure(items):
    for i in items:
        if i.group == "Scenario Comparison" and i.name != "Actual":
            assert "ISSELECTEDMEASURE ( [Comparison Amount] )" in i.expression, i.name


def test_the_nonsense_combinations_are_blanked_in_the_time_intelligence_items(items):
    for i in items:
        if i.group == "Time Intelligence" and i.name in ("YoY", "YoY %"):
            assert '"Variance %", "Favourable/Adverse"' in i.expression, i.name


def test_variance_percent_divides_by_the_absolute_plan(items):
    v = next(i for i in items if i.name == "Variance %")
    assert "ABS ( PlanAmount )" in v.expression


def test_the_favourable_indicator_is_a_number_and_its_words_are_a_format_string(items):
    f = next(i for i in items if i.name == "Favourable/Adverse")
    assert "IF ( Difference < 0, 1, IF ( Difference > 0, -1, 0 ) )" in f.expression
    assert '[=1]""Favourable"";[=-1]""Adverse"";""On plan""' in f.format_expression


# --------------------------------------------------------------------------------------------- functions
def test_every_function_name_is_quoted_in_the_file(model_dir):
    # An unquoted name with a dot is read as a namespace and the function loses its prefix (found in Desktop).
    text = (model_dir / "functions.tmdl").read_text(encoding="utf-8")
    for m in re.finditer(r"^function (\S+) =", text, re.MULTILINE):
        assert m.group(1).startswith("'") and m.group(1).endswith("'"), f"{m.group(1)} must be quoted"


def test_every_function_is_used_by_a_measure_an_item_or_another_function_and_every_call_is_defined(
    measures, items, functions
):
    names = {k.strip("'") for k in functions}
    haystack = _all_expressions(measures, items, functions)
    for name in names:
        uses = len(re.findall(rf"(?<![\w.']){re.escape(name)}\s*\(", haystack))
        own = len(re.findall(rf"(?<![\w.']){re.escape(name)}\s*\(", functions[f"'{name}'"]))
        assert uses - own >= 1, f"{name} is never called"
    called = set(re.findall(r"\b((?:Grain|Plan|Basis|Window|Format)\.[A-Za-z0-9]+)\s*\(", haystack))
    assert called <= names, sorted(called - names)


def test_the_grain_guard_is_written_once_and_both_plan_measures_call_it(measures, functions):
    assert "Grain.BelowGrain" in {k.strip("'") for k in functions}
    plan = next(m for m in measures if m.name == "Plan")
    phased = next(m for m in measures if m.name == "Plan (phased)")
    assert "Grain.BelowGrain ( FALSE () )" in plan.expression
    assert "Grain.BelowGrain ( TRUE () )" in phased.expression
    for m in measures:
        if m.name not in ("Plan", "Plan (phased)", "Plan Below Grain"):
            assert "Grain.BelowGrain" not in m.expression, m.name
    # the rows of the plan that are added up are chosen in one place, for both measures
    assert "Plan.RowsInScope" in plan.expression and "Plan.RowsInScope" in phased.expression
