"""Profile the NHS trust accounts consolidation (TAC) data files.

One pass over the 12 data workbooks through `ukfr.readers.tac`. It writes, to `docs/profiling/data/`
(sorted, LF line ends, no paths, no timestamps):

- `tac_files.csv`          one row per workbook: sheets, rows, providers listed and present
- `tac_code_scheme.csv`    one row per file, statement, table id and main code: rows, providers, sub codes
- `tac_subcode_years.csv`  one row per statement, sub code and release: providers reporting the line
- `tac_value_decimals.csv` one row per file and number of decimal places: rows
- `tac_provider_list.csv`  one row per file and listed provider: code, sector, comment, present in the data

The profile describes the files; it does not decide anything. The decisions it supports are in
`docs/profiling/tac.md`.
"""

from __future__ import annotations

import csv
from collections import Counter, defaultdict
from pathlib import Path

from ..readers import tac as rt

OUT = Path("docs") / "profiling" / "data"


def _write(path: Path, header: tuple[str, ...], rows: list[list]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh, lineterminator="\n")
        w.writerow(header)
        w.writerows(rows)


def run(repo_root: Path) -> None:
    files = [f for f in rt.list_tac_files(repo_root) if f.kind == "data"]
    if not files:
        raise SystemExit("no TAC data files in the manifest (set UKFR_DATA_DIR and run ukfr fetch --source tac)")
    f_rows: list[list] = []
    scheme: list[list] = []
    sub_years: dict[tuple[str, str, str], set[str]] = defaultdict(set)
    decimals: list[list] = []
    plist: list[list] = []
    for f in files:
        stats = rt.TacStats()
        by_code: dict[tuple[str, str, str], dict] = {}
        providers: set[str] = set()
        dp: Counter = Counter()
        for row in rt.read_data(f, repo_root, stats):
            name, ws, table_id, main, _rn, sub, _v = row.values
            statement = rt.STATEMENTS[rt.worksheet_code(ws)]
            providers.add(name)
            e = by_code.setdefault((statement, table_id, main), {"rows": 0, "providers": set(), "subs": set()})
            e["rows"] += 1
            e["providers"].add(name)
            e["subs"].add(sub)
            sub_years[(statement, sub, f.release)].add(name)
            if row.amount is not None:
                exp = row.amount.as_tuple().exponent
                dp[max(-exp, 0) if isinstance(exp, int) else -1] += 1
        listed = rt.read_providers(f, repo_root)
        listed_names = {p.values[0] for p in listed}
        f_rows.append(
            [
                f.release,
                f.provider_type,
                f.filename,
                len(stats.sheets),
                len(stats.worksheet_rows),
                stats.data_rows,
                stats.statement_rows,
                len(listed),
                len(providers),
                len(listed_names - providers),
                len(providers - listed_names),
            ]
        )
        for (statement, table_id, main), e in sorted(by_code.items()):
            scheme.append(
                [f.release, f.provider_type, statement, table_id, main, e["rows"], len(e["providers"]), len(e["subs"])]
            )
        for n, c in sorted(dp.items()):
            decimals.append([f.release, f.provider_type, n, c])
        for p in sorted(listed, key=lambda p: (p.values[1], p.values[0])):
            name, code, _auth, _region, sector, comment = p.values
            plist.append(
                [f.release, f.provider_type, code, name, sector, "yes" if name in providers else "no", comment]
            )
        print(f"  profiled {f.filename}: {stats.statement_rows} statement rows")

    _write(
        repo_root / OUT / "tac_files.csv",
        (
            "release",
            "provider_type",
            "filename",
            "sheets",
            "worksheets_in_all_data",
            "all_data_rows",
            "statement_rows",
            "providers_listed",
            "providers_in_statements",
            "listed_not_in_statements_by_exact_name",
            "in_statements_not_listed_by_exact_name",
        ),
        sorted(f_rows, key=lambda r: (r[0], r[1])),
    )
    _write(
        repo_root / OUT / "tac_code_scheme.csv",
        ("release", "provider_type", "statement", "table_id", "main_code", "rows", "providers", "sub_codes"),
        sorted(scheme, key=lambda r: (r[0], r[1], r[2], r[3], r[4])),
    )
    _write(
        repo_root / OUT / "tac_subcode_years.csv",
        ("statement", "sub_code", "release", "providers"),
        [[s, c, r, len(v)] for (s, c, r), v in sorted(sub_years.items())],
    )
    _write(
        repo_root / OUT / "tac_value_decimals.csv",
        ("release", "provider_type", "decimal_places", "rows"),
        sorted(decimals, key=lambda r: (r[0], r[1], r[2])),
    )
    _write(
        repo_root / OUT / "tac_provider_list.csv",
        ("release", "provider_type", "nhs_code", "provider_name", "sector", "in_statements_by_exact_name", "comment"),
        sorted(plist, key=lambda r: (r[0], r[1], r[2], r[3])),
    )
