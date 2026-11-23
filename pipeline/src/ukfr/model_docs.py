"""Render docs/model-reference.md from what the running model says about itself.

`tools/model_reference/*.dax` query the model open in Desktop through the INFO functions (INFO.VIEW.TABLES,
INFO.VIEW.COLUMNS, INFO.VIEW.MEASURES, INFO.VIEW.RELATIONSHIPS, the role, perspective, calculation item, hierarchy and
user-defined function views). `tools/run_dax_tests.ps1` with `-QueryDir tools/model_reference` and
`-OutDir evidence/model/reference` writes one CSV per query. This module turns those CSVs into one Markdown page.

The page is a function of the CSVs and of the model hash of the TMDL files on disk (see `ledger.projection_hash`), and
of nothing else: no clock, no path, no machine name, rows sorted on their full key. Rendering twice gives the same
bytes. The hash is written on the page, so `ukfr ledger check` can tell that the page was generated from a different
model than the one in the repository and fail with "model-reference.md is stale".
"""

from __future__ import annotations

import csv
import re
from pathlib import Path

from . import ledger

INPUT_DIR = ledger.REFERENCE_CSVS
OUTPUT = ledger.REFERENCE

INPUTS = {
    "tables": "01_tables.csv",
    "columns": "02_columns.csv",
    "measures": "03_measures.csv",
    "relationships": "04_relationships.csv",
    "roles": "05_roles.csv",
    "column_permissions": "06_column_permissions.csv",
    "perspectives": "07_perspectives.csv",
    "calculation_items": "08_calculation_items.csv",
    "functions": "09_functions.csv",
    "hierarchies": "10_hierarchies.csv",
}

# TOM enumerations as the INFO functions return them.
MODEL_PERMISSION = {"1": "none", "2": "read", "3": "read and refresh", "4": "refresh", "5": "administrator"}
METADATA_PERMISSION = {"0": "default", "1": "none (hidden)", "2": "read"}


class ModelDocsError(RuntimeError):
    """An input is missing or does not have the columns the renderer needs."""


def read_inputs(root: Path, input_dir: Path | None = None) -> dict[str, list[dict[str, str]]]:
    base = input_dir or root / INPUT_DIR
    out: dict[str, list[dict[str, str]]] = {}
    for key, name in INPUTS.items():
        path = base / name
        if not path.is_file():
            raise ModelDocsError(
                f"{name} is missing from {INPUT_DIR.as_posix()}: run tools/run_dax_tests.ps1 with "
                "-QueryDir tools/model_reference -OutDir evidence/model/reference"
            )
        with path.open(encoding="utf-8-sig", newline="") as fh:
            out[key] = [dict(r) for r in csv.DictReader(fh)]
    return out


def _sort(rows: list[dict[str, str]], *keys: str) -> list[dict[str, str]]:
    return sorted(rows, key=lambda r: tuple(r[k].casefold() for k in keys) + tuple(r[k] for k in keys))


def _cell(text: str) -> str:
    """Text for a table cell: one line, pipes escaped."""
    return re.sub(r"\s+", " ", text).strip().replace("|", "\\|")


def _flag(value: str) -> str:
    return "yes" if value.strip().lower() == "true" else ""


def _code(text: str, lang: str = "") -> list[str]:
    body = text.replace("\r\n", "\n").strip("\n")
    fence = "````" if "```" in body else "```"
    return [f"{fence}{lang}", body, fence, ""]


def _table(header: list[str], rows: list[list[str]]) -> list[str]:
    if not rows:
        return ["None.", ""]
    lines = ["| " + " | ".join(header) + " |", "|" + "|".join("---" for _ in header) + "|"]
    lines += ["| " + " | ".join(r) + " |" for r in rows]
    return lines + [""]


def render(data: dict[str, list[dict[str, str]]], projection_hash: str) -> str:
    tables = _sort(data["tables"], "Table")
    columns = _sort(data["columns"], "Table", "Column")
    measures = _sort(data["measures"], "Table", "Measure")
    n_cols: dict[str, int] = {}
    n_meas: dict[str, int] = {}
    for c in columns:
        n_cols[c["Table"]] = n_cols.get(c["Table"], 0) + 1
    for m in measures:
        n_meas[m["Table"]] = n_meas.get(m["Table"], 0) + 1

    out: list[str] = [
        "# Model reference",
        "",
        "This page is generated. I do not edit it by hand: `ukfr model-docs` writes it from the model open in Power BI "
        "(`INFO.VIEW.TABLES`, `INFO.VIEW.COLUMNS`, `INFO.VIEW.MEASURES`, `INFO.VIEW.RELATIONSHIPS` and the views "
        "of the roles, perspectives, calculation items, hierarchies and user-defined functions). What the model is "
        "for, how it is built and why is in [model.md](model.md); how its evidence is kept honest is in "
        "[evidence.md](evidence.md).",
        "built and why is in [model.md](model.md); how its evidence is kept honest is in [evidence.md](evidence.md).",
        "",
        "The hash below is the hash of the model's TMDL files that this page was generated from "
        "(`ukfr ledger`, see evidence.md). If the model has changed since, `ukfr ledger check` fails with "
        '"model-reference.md is stale" until the page is generated again.',
        "",
        f"Model projection hash: `{projection_hash}`",
        "",
        f"The model has {len(tables)} tables, {len(columns)} columns, {len(measures)} measures, "
        f"{len(data['relationships'])} relationships, {len(data['functions'])} user-defined functions, "
        f"{len({r['Role'] for r in data['roles']})} roles and "
        f"{len({r['Perspective'] for r in data['perspectives']})} perspectives.",
        "",
        "## Tables",
        "",
    ]
    out += _table(
        ["Table", "Kind", "Columns", "Measures", "Description"],
        [
            [
                _cell(t["Table"]),
                ", ".join(
                    k
                    for k, on in (
                        (
                            "calculation group, precedence " + t["Calculation Group Precedence"],
                            bool(t["Calculation Group Precedence"]),
                        ),
                        ("hidden", t["Is Hidden"] == "True"),
                    )
                    if on
                )
                or "table",
                str(n_cols.get(t["Table"], 0)),
                str(n_meas.get(t["Table"], 0)),
                _cell(t["Description"]),
            ]
            for t in tables
        ],
    )

    out += ["## Relationships", ""]
    rels = _sort(data["relationships"], "From Table", "From Column", "To Table", "To Column")
    out += _table(
        ["From", "To", "Cardinality", "Active", "Cross filter", "Security filter"],
        [
            [
                _cell(f"{r['From Table']}[{r['From Column']}]"),
                _cell(f"{r['To Table']}[{r['To Column']}]"),
                f"{r['From Cardinality']} to {r['To Cardinality']}".lower(),
                _flag(r["Is Active"]) or "no",
                r["Cross Filtering"],
                r["Security Filtering"],
            ]
            for r in rels
        ],
    )

    out += ["## Measures", ""]
    for table in sorted({m["Table"] for m in measures}, key=str.casefold):
        out += [f"### {table}", ""]
        for m in (m for m in measures if m["Table"] == table):
            facts = [
                f"display folder `{m['Display Folder']}`" if m["Display Folder"] else "",
                f"format `{m['Format String']}`" if m["Format String"] else "",
                "hidden" if m["Is Hidden"] == "True" else "",
            ]
            out += [f"#### {m['Measure']}", ""]
            line = "; ".join(f for f in facts if f)
            if line:
                out += [line[0].upper() + line[1:] + ".", ""]
            if m["Description"]:
                out += [m["Description"].strip(), ""]
            out += _code(m["Expression"], "dax")
            if m["Format String Definition"]:
                out += ["Format string expression:", ""] + _code(m["Format String Definition"], "dax")

    out += ["## Columns", ""]
    for table in (t["Table"] for t in tables):
        cols = [c for c in columns if c["Table"] == table]
        if not cols:
            continue
        out += [f"### {table}", ""]
        out += _table(
            [
                "Column",
                "Type",
                "Data type",
                "Hidden",
                "Key",
                "Source or expression",
                "Format",
                "Sort by",
                "Display folder",
                "Description",
            ],
            [
                [
                    _cell(c["Column"]),
                    c["Type"],
                    c["Data Type"].lower(),
                    _flag(c["Is Hidden"]),
                    _flag(c["Is Key"]),
                    _cell(c["Source Column"] or c["Expression"]),
                    _cell(c["Format String"]),
                    _cell(c["Sort By Column"]),
                    _cell(c["Display Folder"]),
                    _cell(c["Description"]),
                ]
                for c in cols
            ],
        )

    out += ["## Calculation groups", ""]
    items = sorted(data["calculation_items"], key=lambda r: (r["Table"].casefold(), int(r["Ordinal"]), r["Item"]))
    for table in sorted({i["Table"] for i in items}, key=str.casefold):
        group = [i for i in items if i["Table"] == table]
        out += [f"### {table}", "", f"Precedence {group[0]['Precedence']}.", ""]
        for i in group:
            out += [f"#### {i['Item']}", ""]
            if i["Description"]:
                out += [i["Description"].strip(), ""]
            out += _code(i["Expression"], "dax")

    out += ["## User-defined functions", ""]
    for f in _sort(data["functions"], "Function"):
        out += [f"### {f['Function']}", ""]
        if f["Description"]:
            out += [f["Description"].strip(), ""]
        out += _code(f["Expression"], "dax")

    out += ["## Hierarchies", ""]
    out += _table(
        ["Table", "Hierarchy", "Levels", "Hidden", "Description"],
        [
            [
                _cell(h["Table"]),
                _cell(h["Hierarchy"]),
                _cell(h["Levels"]),
                _flag(h["Is Hidden"]),
                _cell(h["Description"]),
            ]
            for h in _sort(data["hierarchies"], "Table", "Hierarchy")
        ],
    )

    out += ["## Roles", ""]
    roles = _sort(data["roles"], "Role", "Table")
    for role in sorted({r["Role"] for r in roles}, key=str.casefold):
        rows = [r for r in roles if r["Role"] == role]
        out += [
            f"### {role}",
            "",
            f"Model permission: {MODEL_PERMISSION.get(rows[0]['Model Permission'], rows[0]['Model Permission'])}.",
            "",
        ]
        if rows[0]["Role Description"]:
            out += [rows[0]["Role Description"].strip(), ""]
        for r in rows:
            if r["Row Filter"]:
                out += [f"Row filter on `{r['Table']}`:", ""] + _code(r["Row Filter"], "dax")
        hidden = [c for c in _sort(data["column_permissions"], "Table", "Column") if c["Role"] == role]
        if hidden:
            out += ["Columns hidden from this role (object-level security):", ""]
            out += _table(
                ["Table", "Column", "Permission"],
                [
                    [
                        _cell(c["Table"]),
                        _cell(c["Column"]),
                        METADATA_PERMISSION.get(c["Metadata Permission"], c["Metadata Permission"]),
                    ]
                    for c in hidden
                ],
            )
        other = [r for r in rows if r["Metadata Permission"] not in ("", "0") and not r["Row Filter"]]
        if other:
            out += ["Tables with their own permission:", ""]
            out += _table(
                ["Table", "Permission"],
                [
                    [_cell(r["Table"]), METADATA_PERMISSION.get(r["Metadata Permission"], r["Metadata Permission"])]
                    for r in other
                ],
            )

    out += ["## Perspectives", ""]
    persp = _sort(data["perspectives"], "Perspective", "Table")
    for name in sorted({p["Perspective"] for p in persp}, key=str.casefold):
        rows = [p for p in persp if p["Perspective"] == name]
        out += [f"### {name}", ""]
        if rows[0]["Perspective Description"]:
            out += [rows[0]["Perspective Description"].strip(), ""]
        out += _table(
            ["Table", "Whole table", "Listed measures", "Listed columns"],
            [[_cell(p["Table"]), _flag(p["Include All"]), p["Listed Measures"], p["Listed Columns"]] for p in rows],
        )

    text = "\n".join(out)
    text = re.sub(r"[ \t]+\n", "\n", text)  # no trailing blanks
    return text.rstrip("\n") + "\n"


def generate(root: Path, input_dir: Path | None = None) -> str:
    return render(read_inputs(root, input_dir), ledger.projection_hash(root))


def write(root: Path, input_dir: Path | None = None, output: Path | None = None) -> Path:
    text = generate(root, input_dir)
    path = output or root / OUTPUT
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")
    return path
