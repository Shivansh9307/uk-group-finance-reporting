# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Summarise a VertiPaq Analyzer export (.vpax) into tables.csv and columns.csv.

A .vpax is a zip of JSON files. It can hold the server name (Desktop's local port), the full model
definition including Power Query source expressions, and extraction timestamps, so the raw file stays
out of the repository. This script copies only size statistics:

  tables.csv   table, rows, table_size_bytes, columns_size_bytes
  columns.csv  table, column, data_type, column_type, encoding, cardinality,
               dictionary_bytes, data_bytes, hierarchies_bytes, total_bytes, is_hidden

Row-number columns (internal, one per table) are left out of columns.csv; their size is still part of
the table totals in tables.csv.

Usage:
    uv run tools/vpax_summary.py <file.vpax> --out-dir <folder>
"""
from __future__ import annotations

import argparse
import csv
import json
import sys
import zipfile
from pathlib import Path


def _load(z: zipfile.ZipFile, name: str) -> dict:
    return json.loads(z.read(name).decode("utf-8-sig"))


def summarise(vpax: Path) -> tuple[list[dict], list[dict]]:
    with zipfile.ZipFile(vpax) as z:
        names = set(z.namelist())
        if "DaxModel.json" not in names or "DaxVpaView.json" not in names:
            raise ValueError(f"{vpax.name} does not look like a VertiPaq Analyzer export")
        model = _load(z, "DaxModel.json")
        view = _load(z, "DaxVpaView.json")

    tables = [
        {
            "table": t["TableName"],
            "rows": t.get("RowsCount"),
            "table_size_bytes": t.get("TableSize"),
            "columns_size_bytes": t.get("ColumnsSize"),
        }
        for t in view.get("Tables", [])
    ]
    tables.sort(key=lambda r: (-(r["table_size_bytes"] or 0), r["table"]))

    columns = []
    for t in model.get("Tables", []):
        for c in t.get("Columns", []):
            if c.get("ColumnType") == "RowNumber":
                continue
            columns.append(
                {
                    "table": t["TableName"],
                    "column": c["ColumnName"],
                    "data_type": c.get("DataType"),
                    "column_type": c.get("ColumnType"),
                    "encoding": c.get("Encoding"),
                    "cardinality": c.get("ColumnCardinality"),
                    "dictionary_bytes": c.get("DictionarySize"),
                    "data_bytes": c.get("DataSize"),
                    "hierarchies_bytes": c.get("HierarchiesSize"),
                    "total_bytes": c.get("TotalSize"),
                    "is_hidden": bool(c.get("IsHidden", False)),
                }
            )
    columns.sort(key=lambda r: (r["table"], -(r["total_bytes"] or 0), r["column"]))
    return tables, columns


def _write(path: Path, rows: list[dict]) -> None:
    if not rows:
        path.write_text("", encoding="utf-8")
        return
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()), lineterminator="\n")
        w.writeheader()
        w.writerows(rows)


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("vpax", type=Path)
    p.add_argument("--out-dir", type=Path, required=True)
    args = p.parse_args(argv)
    tables, columns = summarise(args.vpax)
    args.out_dir.mkdir(parents=True, exist_ok=True)
    _write(args.out_dir / "tables.csv", tables)
    _write(args.out_dir / "columns.csv", columns)
    print(f"{len(tables)} tables, {len(columns)} columns -> {args.out_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
