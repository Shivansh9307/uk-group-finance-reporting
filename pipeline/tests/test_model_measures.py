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
# measures that return text (a label for a page) and so have no number format
TEXT_MEASURES = {"Plan Source and Grain", "Latest Release in View"}

BASE_MEASURES = {
    "Outturn": ("Fact Outturn", "Base"),
    "Outturn (plan basis)": ("Fact Outturn", "Plan"),
    "Comparison Amount": ("Fact Outturn", "Plan"),
    "Plan": ("Fact Plan", "Plan"),
    "Plan Below Grain": ("Fact Plan", "Plan"),
    "Plan (phased)": ("Fact Plan Phased (derived)", "Plan\\Derived"),
    "Statement Amount": ("Fact Outturn", "Statement"),
    "Statement Amount (plan basis)": ("Fact Outturn", "Statement"),
    "Statement Variance": ("Fact Outturn", "Statement"),
    "Statement Variance %": ("Fact Outturn", "Statement"),
    "Statement Plan": ("Fact Plan", "Statement"),
    "Statement Amount PY (OFFSET)": ("Fact Outturn", "Statement\\Windows"),
    "Statement Amount Running (WINDOW)": ("Fact Outturn", "Statement\\Windows"),
    "Statement Amount Moving 3 Months (WINDOW)": ("Fact Outturn", "Statement\\Windows"),
    "Department Rank (Statement Amount)": ("Fact Outturn", "Statement\\Windows"),
    "Outturn as at Release": ("Fact Outturn", "Restatement"),
    "Outturn as at Release (naive)": ("Fact Outturn", r"Performance\Naive"),
    "Outturn as First Reported": ("Fact Outturn", "Restatement"),
    "Revision since First Reported": ("Fact Outturn", "Restatement"),
    "Revision %": ("Fact Outturn", "Restatement"),
    "Revision in Release": ("Fact Outturn", "Restatement"),
    "Restatement in Release": ("Fact Outturn", "Restatement"),
    "Gross Revision in Release": ("Fact Outturn", "Restatement"),
    "Gross Restatement in Release": ("Fact Outturn", "Restatement"),
    "Gross Revision in Release (excl. flagged)": ("Fact Outturn", "Restatement\\Excluding flagged rows"),
    "Gross Restatement in Release (excl. flagged)": ("Fact Outturn", "Restatement\\Excluding flagged rows"),
    "Outturn (current structure)": ("Fact Outturn", "Current Structure"),
    "Outturn (as reported structure)": ("Fact Outturn", "Current Structure"),
    "Machinery of Government Transfer": ("Fact Outturn", "Current Structure"),
    "Outturn (estimated mapping)": ("Fact Outturn", "Current Structure"),
    "Estimated Mapping Share": ("Fact Outturn", "Current Structure"),
    "Plan Source and Grain": ("Fact Plan", "Plan"),
    "Plan and Outturn by Scenario": ("Fact Plan", "Plan"),
    "Variance to Phased Plan": ("Fact Plan Phased (derived)", r"Plan\Derived"),
    "Variance to Phased Plan %": ("Fact Plan Phased (derived)", r"Plan\Derived"),
    "Latest Release in View": ("Fact Outturn", "Report Labels"),
    "File Total (4 decimals)": ("File Control", "Audit and control"),
    "Outturn as at Release (own year)": ("File Control", "Audit and control"),
    "Difference to File Total": ("File Control", "Audit and control"),
    "Plan Coverage Total": ("Plan Coverage", "Audit and control"),
    "Rows Read": ("Load Control", "Audit and control"),
    "Rows Loaded": ("Load Control", "Audit and control"),
    "Rows Quarantined": ("Load Control", "Audit and control"),
    "Web Rows Quarantined": ("Load Control", "Audit and control"),
    "Department Group Rank (YTD Variance %)": ("Fact Outturn", "Plan\\Ranking"),
    "Department Group Rank (YTD Variance %) (naive)": ("Fact Outturn", r"Performance\Naive"),
    "Outturn (real terms)": ("Fact Outturn", "Real Terms"),
    "Outturn (plan basis) (real terms)": ("Fact Outturn", "Real Terms"),
    "Outturn (current structure) (real terms)": ("Fact Outturn", "Real Terms"),
    "Statement Amount (real terms)": ("Fact Outturn", "Real Terms"),
    "Plan (real terms)": ("Fact Plan", "Real Terms"),
    "Statement Plan (real terms)": ("Fact Plan", "Real Terms"),
    "Plan (phased) (real terms)": ("Fact Plan Phased (derived)", "Real Terms"),
    "TAC Closing Balance": ("Fact TAC", "TAC\\Balance sheet"),
    "TAC Opening Balance": ("Fact TAC", "TAC\\Balance sheet"),
    "TAC Prior Year Closing Balance": ("Fact TAC", "TAC\\Balance sheet"),
    "TAC Opening less Prior Year Closing": ("Fact TAC", "TAC\\Balance sheet"),
    "TAC Restatement": ("Fact TAC", "TAC\\Balance sheet"),
    "TAC Amount": ("Fact TAC", "TAC\\Income statement and cash flow"),
    "TAC Providers Reporting": ("Fact TAC", "TAC\\Balance sheet"),
    "TAC Cash Flow (published)": ("Fact TAC", "TAC\\Cash flow"),
    "TAC Provider Sum (control)": ("Fact TAC", "TAC\\Elimination control"),
    "TAC Cash Flow (derived)": ("Fact TAC Cash Flow (derived)", "TAC\\Cash flow"),
    "TAC Cash Flow Residual": ("Fact TAC Cash Flow (derived)", "TAC\\Cash flow"),
    "TAC Consolidated Total": ("TAC Consolidated Accounts", "TAC\\Elimination control"),
    "TAC Elimination Gap": ("TAC Consolidated Accounts", "TAC\\Elimination control"),
    "TAC Elimination Gap %": ("TAC Consolidated Accounts", "TAC\\Elimination control"),
    "TAC Net Change in Cash (published)": ("Fact TAC", "TAC\\Cash flow"),
    "TAC Cash Movement (balance sheet)": ("Fact TAC", "TAC\\Cash flow"),
    "Pay Bridge Prior Paybill": ("Fact Pay Bridge (derived)", "Pay bridge"),
    "Pay Bridge Current Paybill": ("Fact Pay Bridge (derived)", "Pay bridge"),
    "Pay Bridge Volume": ("Fact Pay Bridge (derived)", "Pay bridge"),
    "Pay Bridge Rate": ("Fact Pay Bridge (derived)", "Pay bridge"),
    "Pay Bridge Mix": ("Fact Pay Bridge (derived)", "Pay bridge"),
    "Pay Bridge Entry and Exit": ("Fact Pay Bridge (derived)", "Pay bridge"),
    "Pay Bridge Change": ("Fact Pay Bridge (derived)", "Pay bridge"),
    "Pay Bridge Tie Difference": ("Fact Pay Bridge (derived)", "Pay bridge"),
    "Pay Bridge Rows Not Bridged": ("Fact Pay Bridge (derived)", "Pay bridge"),
    "Pay Bridge Step Amount": ("Fact Pay Bridge (derived)", "Pay bridge"),
    "Pay Paybill": ("Fact Pay Bridge (derived)", r"Pay bridge\Trend"),
    "Pay FTE": ("Fact Pay Bridge (derived)", r"Pay bridge\Trend"),
    "Pay Average Cost": ("Fact Pay Bridge (derived)", r"Pay bridge\Trend"),
    "Pay FTE Coverage": ("Pay Coverage", r"Pay bridge\Coverage"),
    "Pay Paybill Coverage": ("Pay Coverage", r"Pay bridge\Coverage"),
    "Pay Paybill Published": ("Pay Coverage", r"Pay bridge\Coverage"),
    "Pay Paybill Mapped": ("Pay Coverage", r"Pay bridge\Coverage"),
    "Pay Coverage Months": ("Pay Coverage", r"Pay bridge\Coverage"),
    "Forecast Abs Error": ("Fact Forecast Accuracy (derived)", "Forecast accuracy"),
    "Forecast Abs Error (excl. bad returns)": ("Fact Forecast Accuracy (derived)", "Forecast accuracy"),
    "Forecast Abs Outturn": ("Fact Forecast Accuracy (derived)", "Forecast accuracy"),
    "Forecast Abs Outturn (excl. bad returns)": ("Fact Forecast Accuracy (derived)", "Forecast accuracy"),
    "Forecast Error": ("Fact Forecast Accuracy (derived)", "Forecast accuracy"),
    "Forecast Error (excl. bad returns)": ("Fact Forecast Accuracy (derived)", "Forecast accuracy"),
    "Forecast WAPE": ("Fact Forecast Accuracy (derived)", "Forecast accuracy"),
    "Forecast WAPE (excl. bad returns)": ("Fact Forecast Accuracy (derived)", "Forecast accuracy"),
    "Forecast Bias": ("Fact Forecast Accuracy (derived)", "Forecast accuracy"),
    "Forecast Bias (excl. bad returns)": ("Fact Forecast Accuracy (derived)", "Forecast accuracy"),
    "Forecast Month WAPE": ("Fact Forecast Accuracy (derived)", "Forecast accuracy"),
    "Forecast Month WAPE (excl. bad returns)": ("Fact Forecast Accuracy (derived)", "Forecast accuracy"),
    "Forecast Month Bias": ("Fact Forecast Accuracy (derived)", "Forecast accuracy"),
    "Forecast Month Bias (excl. bad returns)": ("Fact Forecast Accuracy (derived)", "Forecast accuracy"),
    "Forecast MAPE": ("Fact Forecast Accuracy (derived)", "Forecast accuracy"),
    "Forecast MAPE (excl. bad returns)": ("Fact Forecast Accuracy (derived)", "Forecast accuracy"),
    "Forecast Cells": ("Fact Forecast Accuracy (derived)", "Forecast accuracy"),
    "Forecast Cells (excl. bad returns)": ("Fact Forecast Accuracy (derived)", "Forecast accuracy"),
    "Known Bad Return Cells": ("Fact Forecast Accuracy (derived)", "Forecast accuracy"),
    "FTE x Cost Cell Coverage": ("Fact Forecast Accuracy (derived)", "Forecast accuracy"),
    "FTE x Cost Pay Cover": ("Fact Forecast Accuracy (derived)", "Forecast accuracy"),
}
GROUPS = {"Scenario Comparison": 10, "Time Intelligence": 20, "Display Unit": 30}


def _is_hidden(m) -> bool:
    return m.props.get("isHidden") == "true"


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
                    elif depth == 2 and s == "isHidden":
                        props["isHidden"] = "true"
                    elif s and not s.startswith("annotation "):
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
    # The body is the indented block after `function 'Name' =`, with or without a ``` fence (the Tabular Editor layout
    # has none); it ends at the next top-level line.
    for m in re.finditer(
        r"^function (\S+) =[ \t]*(?:```)?[ \t]*\n(.*?)(?=^(?:///|function |\S)|\Z)", text, re.MULTILINE | re.DOTALL
    ):
        found[m.group(1)] = m.group(2).replace("```", "")
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
        assert m.props.get("formatString") or m.name in TEXT_MEASURES, f"{m.name}: no format string"
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
    formats = [m.props["formatString"] for m in measures if m.name not in TEXT_MEASURES]
    formats += [i.format_expression for i in items]
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
    called = set(re.findall(r"\b((?:Grain|Plan|Basis|Window|Format|Pnl|Restate|Real)\.[A-Za-z0-9]+)\s*\(", haystack))
    assert called <= names, sorted(called - names)


def test_the_grain_guard_is_written_once_and_both_plan_measures_call_it(measures, functions):
    assert "Grain.BelowGrain" in {k.strip("'") for k in functions}
    plan = next(m for m in measures if m.name == "Plan")
    phased = next(m for m in measures if m.name == "Plan (phased)")
    assert "Grain.BelowGrain ( FALSE () )" in plan.expression
    assert "Grain.BelowGrain ( TRUE () )" in phased.expression
    for m in measures:
        if m.name not in ("Plan", "Plan (phased)", "Plan Below Grain", "Plan Source and Grain"):
            assert "Grain.BelowGrain" not in m.expression, m.name
    # the rows of the plan that are added up are chosen in one place, for both measures
    assert "Plan.RowsInScope" in plan.expression and "Plan.RowsInScope" in phased.expression


# ------------------------------------------------------------------------------------------ the statement
def test_the_statement_functions_are_in_the_pnl_namespace_because_statement_is_reserved(functions, measures, items):
    # "Statement.SignFactor" is a syntax error in a DAX query on this engine; the namespace is Pnl
    names = {k.strip("'") for k in functions}
    assert {"Pnl.SignFactor", "Pnl.LineAmount", "Pnl.AtPlanScope"} <= names
    assert not any(n.startswith("Statement.") for n in names)
    haystack = _all_expressions(measures, items, functions)
    assert not re.search(r"(?<![\w'])Statement\.[A-Za-z]+\s*\(", haystack)


def test_the_statement_amount_is_the_outturn_of_the_line_and_the_plan_measures_use_the_same_scope_function(measures):
    by_name = {m.name: m for m in measures}
    assert re.sub(r"\s+", " ", by_name["Statement Amount"].expression) == "Pnl.LineAmount ( [Outturn] )"
    assert re.sub(r"\s+", " ", by_name["Statement Plan"].expression) == "Pnl.AtPlanScope ( [Plan] )"
    assert "Pnl.AtPlanScope ( [Comparison Amount] )" in by_name["Statement Amount (plan basis)"].expression
    assert "ISBLANK ( [Statement Plan] )" in by_name["Statement Amount (plan basis)"].expression


def test_the_window_measures_use_the_window_functions_they_are_named_for(measures):
    by_name = {m.name: m for m in measures}
    assert "OFFSET (" in by_name["Statement Amount PY (OFFSET)"].expression
    assert "WINDOW (" in by_name["Statement Amount Running (WINDOW)"].expression
    assert "WINDOW (" in by_name["Statement Amount Moving 3 Months (WINDOW)"].expression
    assert "RANK (" in by_name["Department Rank (Statement Amount)"].expression


def test_the_field_parameter_points_at_four_measures_that_exist(table_text, measures):
    text = table_text["Statement Measure"]
    refs = re.findall(r"NAMEOF \( '([^']+)'\[([^\]]+)\] \)", text)
    assert len(refs) == 4
    by_name = {m.name: m.table for m in measures}
    for table, name in refs:
        assert by_name.get(name) == table, f"{table}[{name}] is not a measure"
    assert '"version": 3' in text and '"kind": 2' in text, "ParameterMetadata marks the field parameter"


def test_the_statement_measures_act_through_the_calculation_groups(items):
    by_name = {(i.group, i.name): i for i in items}
    for name in ("Plan", "Variance", "Variance %", "Favourable/Adverse", "Actual"):
        assert "[Statement Amount]" in by_name[("Scenario Comparison", name)].expression, name
    for unit in ("£k", "£m", "£bn"):
        assert "[Statement Amount]" in by_name[("Display Unit", unit)].expression
        scaled = by_name[("Display Unit", unit)].expression
        assert "[Statement Variance %]" not in scaled, "a percentage is never scaled"


# ------------------------------------------------------------------------------------------ restatement
def test_outturn_as_at_release_is_a_column_filter_and_its_plain_form_is_kept_hidden_as_evidence(measures):
    # slow measure 1: the rewrite filters the Release Sequence column after clearing the Release table; the plain form
    # (a CALCULATE over a FILTER of ALL releases) stays as a hidden measure that the equality tests compare it with
    by_name = {m.name: m for m in measures}
    e = re.sub(r"\s+", " ", by_name["Outturn as at Release"].expression)
    assert "MAX ( 'Release'[Release Sequence] )" in e
    assert "CALCULATE ( [Outturn], REMOVEFILTERS ( 'Release' ), 'Release'[Release Sequence] <= AsAt )" in e
    assert "FILTER (" not in e.replace("REMOVEFILTERS (", "")
    assert "RANKX" not in e and "WINDOW" not in e and "OFFSET" not in e
    assert not _is_hidden(by_name["Outturn as at Release"])
    naive = by_name["Outturn as at Release (naive)"]
    n = re.sub(r"\s+", " ", naive.expression)
    assert "CALCULATE ( [Outturn], FILTER ( ALL ( 'Release' ), 'Release'[Release Sequence] <= AsAt ) )" in n
    assert _is_hidden(naive) and "kept as evidence" in naive.description.lower()


def test_first_reported_sums_the_deltas_of_revision_zero_up_to_the_as_at_release(measures):
    by_name = {m.name: m for m in measures}
    e = re.sub(r"\s+", " ", by_name["Outturn as First Reported"].expression)
    assert "'Fact Outturn'[Revision Number] = 0" in e and "'Release'[Release Sequence] <= AsAt" in e
    r = re.sub(r"\s+", " ", by_name["Revision since First Reported"].expression)
    assert "[Outturn as at Release]" in r and "[Outturn as First Reported]" in r


def test_the_data_quality_variants_wrap_the_stated_pattern_and_only_the_gross_measures_have_one(measures, functions):
    by_name = {m.name: m for m in measures}
    variants = sorted(n for n in by_name if n.endswith("(excl. flagged)"))
    assert variants == ["Gross Restatement in Release (excl. flagged)", "Gross Revision in Release (excl. flagged)"]
    for n in variants:
        base = n.replace(" (excl. flagged)", "")
        assert re.sub(r"\s+", " ", by_name[n].expression) == f"Restate.Unflagged ( [{base}] )"
    body = re.sub(r"\s+", " ", functions["'Restate.Unflagged'"])
    assert "'Fact Outturn'[Data Quality Issue Key] = 0" in body and "KEEPFILTERS" in body


def test_the_current_structure_counterpart_is_found_by_department_number_and_never_by_name(measures):
    by_name = {m.name: m for m in measures}
    for n in ("Outturn (as reported structure)", "Outturn (current structure)", "Machinery of Government Transfer"):
        e = by_name[n].expression
        assert "'Department (current structure)'[Department]" not in e, f"{n} must not use a name"
        assert "[Department (as reported)]" not in e, f"{n} must not use a name"
    assert "Reported Department Numbers" in by_name["Outturn (as reported structure)"].expression
    assert "Department Number (as reported)" in by_name["Outturn (as reported structure)"].expression


def test_the_rank_by_ytd_variance_percent_works_out_each_groups_value_once_and_ranks_that_column(measures):
    by_name = {m.name: m for m in measures}
    e = re.sub(r"\s+", " ", by_name["Department Group Rank (YTD Variance %)"].expression)
    assert "ADDCOLUMNS (" in e and "RANKX ( Groups, [@ytd], YtdVariancePercent, DESC, SKIP )" in e
    assert "ALLSELECTED ( 'Spending Review Group' )" in e
    # the calculation is written twice (the cell's own value and the value of every group), not three times
    assert e.count("'Time Intelligence'[Time Calculation] = \"YTD\"") == 2
    assert e.count("'Scenario Comparison'[Comparison] = \"Variance %\"") == 2
    assert "Department Rank (Statement Amount)" not in e
    assert not _is_hidden(by_name["Department Group Rank (YTD Variance %)"])


def test_the_plain_form_of_the_rank_is_kept_hidden_with_the_calculation_written_three_times(measures):
    by_name = {m.name: m for m in measures}
    naive = by_name["Department Group Rank (YTD Variance %) (naive)"]
    e = re.sub(r"\s+", " ", naive.expression)
    assert "RANKX (" in e and "ADDCOLUMNS" not in e and "ALLSELECTED ( 'Spending Review Group' )" in e
    assert e.count("'Time Intelligence'[Time Calculation] = \"YTD\"") == 3
    assert e.count("'Scenario Comparison'[Comparison] = \"Variance %\"") == 3
    assert _is_hidden(naive) and "kept as evidence" in naive.description.lower()


def test_the_hidden_plain_forms_are_in_no_perspective_and_no_other_measure_reads_them(measures, table_text):
    hidden = [m.name for m in measures if _is_hidden(m)]
    assert hidden == ["Outturn as at Release (naive)", "Department Group Rank (YTD Variance %) (naive)"]
    for m in measures:
        for h in hidden:
            assert f"[{h}]" not in m.expression, f"{m.name} reads the hidden measure {h}"


def test_every_restatement_and_current_structure_amount_is_scaled_by_the_display_unit_and_no_percentage_is(
    items, measures
):
    amounts = [m.name for m in measures if m.props["displayFolder"].startswith(("Restatement", "Current Structure"))]
    percent = {"Revision %", "Estimated Mapping Share"}
    assert len(amounts) == 15
    for unit in ("£k", "£m", "£bn"):
        expr = next(i for i in items if i.group == "Display Unit" and i.name == unit).expression
        for n in amounts:
            assert (f"[{n}]" in expr) == (n not in percent), f"{unit}: {n}"


def test_no_pay_measure_is_scaled_by_the_display_unit(items, measures):
    pay = [m.name for m in measures if m.table in ("Fact Pay Bridge (derived)", "Pay Coverage")]
    assert len(pay) >= 15
    for unit in ("£k", "£m", "£bn"):
        expr = next(i for i in items if i.group == "Display Unit" and i.name == unit).expression
        for n in pay:
            assert f"[{n}]" not in expr, f"{unit}: {n} is in pounds, not GBP thousands"


def test_no_forecast_measure_is_scaled_by_the_display_unit_and_every_excl_pair_uses_keepfilters(items, measures):
    fc = [m for m in measures if m.table == "Fact Forecast Accuracy (derived)"]
    assert len(fc) == 21
    for unit in ("£k", "£m", "£bn"):
        expr = next(i for i in items if i.group == "Display Unit" and i.name == unit).expression
        for m in fc:
            assert f"[{m.name}]" not in expr, f"{unit}: {m.name} is in GBP thousands and not scaled"
    excl = [m for m in fc if m.name.endswith("(excl. bad returns)")]
    assert len(excl) == 9
    for m in excl:
        assert "KEEPFILTERS" in m.expression and "[Known Bad Return] = FALSE ()" in m.expression, m.name


def test_the_forecast_ratios_are_ratios_of_sums_and_never_an_average(measures):
    by = {m.name: m.expression for m in measures}
    for name in ("Forecast WAPE", "Forecast Bias", "Forecast Month WAPE", "Forecast Month Bias", "Forecast MAPE"):
        e = by[name]
        assert e.count("SUM (") == 2 and "DIVIDE (" in e, name
        assert "AVERAGE" not in e and "SUMX" not in e, name


def test_the_share_measures_are_blanked_under_year_on_year(items):
    for name in ("YoY", "YoY %"):
        e = next(i for i in items if i.group == "Time Intelligence" and i.name == name).expression
        assert "ISSELECTEDMEASURE ( [Revision %], [Estimated Mapping Share] )" in e, name
