"""`ukfr profile bud`: profile the OSCAR annual BUD workbooks and reconcile them to the in-year releases.

Outputs (deterministic; Decimal sums under a context that traps rounding):

- `data/audit/bud_file_control_totals.csv`: one row per BUD workbook
- `data/audit/bud_file_control_totals_by_layer.csv`: the same totals by TYPE, STATUS, control budget
- `docs/profiling/data/bud_*.csv`: machinery-of-government layer, mapping tables, the reconciliation to
  the June in-year releases, and restatement between vintages
"""

from __future__ import annotations

import csv
import decimal
import time
from collections import Counter, defaultdict
from decimal import Decimal
from pathlib import Path

from python_calamine import CalamineWorkbook

from ..config import FILES_CSV, data_dir
from ..manifest import RAW_PREFIX, read_rows
from ..readers.oscar_bud import BUD_COLUMNS, BudRow, BudStats, list_bud_files, read_bud
from ..readers.oscar_inyear import list_inyear_files, read_inyear
from .inyear import AUDIT, CB_NORMAL, DOCS_DATA, EXACT, ZERO, norm_name, pct, release_fy, split_code, write_csv

EXCLUDED_STATUS = "Closed"  # see the profiling notes: Closed rows repeat rows held under another status
DIMENSIONS = ("TYPE_CODE", "STATUS_CODE", "CONTROL_BUDGET_L1_LONG_NAME", "CONTROL_BUDGET_L0_LONG_NAME",
              "ECONOMIC_BUDGET_CODE", "VERSION_CODE", "MONTH_SHORT_NAME")  # fmt: skip


def included(r: BudRow) -> bool:
    return r["STATUS_CODE"] != EXCLUDED_STATUS


def amt(r: BudRow) -> Decimal:
    return r.amount if r.amount is not None else ZERO


def run(root: Path, out_docs: Path | None = None, out_audit: Path | None = None, log=print) -> dict:
    out_docs = out_docs or root / DOCS_DATA
    out_audit = out_audit or root / AUDIT
    with decimal.localcontext(EXACT):
        return _run(root, out_docs, out_audit, log)


def _run(root: Path, out_docs: Path, out_audit: Path, log) -> dict:
    t0 = time.perf_counter()
    files = list_bud_files(root)
    control = []
    layers = []
    mog = defaultdict(lambda: [0, ZERO])
    dept_map = defaultdict(lambda: [set(), set(), 0])
    org_type = defaultdict(lambda: [set(), set(), 0])
    accounts = defaultdict(lambda: [set(), set(), set(), 0])
    bud_by_year: dict[tuple[str, str], dict] = {}  # (vintage, year) -> aggregates for reconciliation
    closed_twins = {}
    for f in files:
        t1 = time.perf_counter()
        stats = BudStats()
        rows = list(read_bud(f, root, stats))
        years = Counter(r.financial_year for r in rows)
        if len(years) != 1:
            raise ValueError(f"{f.filename}: expected one financial year, found {dict(years)}")
        year = next(iter(years))
        total_all = sum((amt(r) for r in rows), ZERO)
        inc = [r for r in rows if included(r)]
        total_inc = sum((amt(r) for r in inc), ZERO)
        by = {d: defaultdict(lambda: [0, ZERO]) for d in (*DIMENSIONS, "TYPE_CODE | STATUS_CODE")}
        for r in rows:
            for d in DIMENSIONS:
                by[d][r[d]][0] += 1
                by[d][r[d]][1] += amt(r)
            k = f"{r['TYPE_CODE']} | {r['STATUS_CODE']}"
            by["TYPE_CODE | STATUS_CODE"][k][0] += 1
            by["TYPE_CODE | STATUS_CODE"][k][1] += amt(r)
        cb_inc = defaultdict(lambda: ZERO)
        for r in inc:
            cb_inc[r["CONTROL_BUDGET_L1_LONG_NAME"]] += amt(r)

        # Closed rows: does an identical row (all columns but STATUS_CODE) exist under another status?
        def twin_key(r: BudRow) -> tuple:
            return tuple(v for k, v in r.values.items() if k != "STATUS_CODE")

        others = Counter(twin_key(r) for r in rows if r["STATUS_CODE"] != EXCLUDED_STATUS)
        closed = [r for r in rows if r["STATUS_CODE"] == EXCLUDED_STATUS]
        closed_twins[(f.vintage, f.filename)] = (len(closed), sum(1 for r in closed if others[twin_key(r)]))
        control.append((
            f.vintage, f.filename, f.sha256, year, stats.sheet, " ".join(stats.other_sheets), len(BUD_COLUMNS), "Y",
            stats.total_rows, stats.blank_rows, stats.data_rows,
            " ".join(f"{k}:{v}" for k, v in sorted(stats.amount_forms.items())),
            " ".join(sorted(by["VERSION_CODE"])), " ".join(sorted(by["MONTH_SHORT_NAME"])),
            " ".join(f"{k}:{v[0]}" for k, v in sorted(by["STATUS_CODE"].items())),
            len(by["TYPE_CODE"]), len(closed), closed_twins[(f.vintage, f.filename)][1],
            total_all, total_inc, total_all - total_inc,
            cb_inc.get("DEL", ZERO), cb_inc.get("AME", ZERO), cb_inc.get("NON-BUDGET", ZERO),
            sum((v for k, v in cb_inc.items() if k not in ("DEL", "AME", "NON-BUDGET")), ZERO),
        ))  # fmt: skip
        for d, values in by.items():
            for v, (n, a) in sorted(values.items()):
                layers.append((f.vintage, f.filename, year, d, v, n, a))
        for r in rows:
            if "MOG" in r["TYPE_CODE"]:
                k = (year, f.vintage, r["TYPE_CODE"], r["STATUS_CODE"], r["DEPARTMENT_GROUP_CODE"],
                     r["DEPARTMENT_GROUP_LONG_NAME"], r["ORGANISATION_CODE"], r["ORGANISATION_LONG_NAME"])  # fmt: skip
                mog[k][0] += 1
                mog[k][1] += amt(r)
            dm = dept_map[(r["DEPARTMENT_GROUP_CODE"], r["DEPARTMENT_GROUP_LONG_NAME"], r["SR_GROUP_CODE"],
                           r["SR_GROUP_LONG_NAME"], r["PESA_GROUP_CODE"], r["PESA_GROUP_LONG_NAME"])]  # fmt: skip
            dm[0].add(f.vintage)
            dm[1].add(year)
            dm[2] += 1
            ot = org_type[(r["ORGANISATION_CODE"], r["ORGANISATION_LONG_NAME"], r["ORGANISATION_TYPE_CODE"],
                           r["ORGANISATION_TYPE_L1_CODE"], r["ORGANISATION_TYPE_L1_LONG_NAME"],
                           r["DEPARTMENT_GROUP_CODE"])]  # fmt: skip
            ot[0].add(f.vintage)
            ot[1].add(year)
            ot[2] += 1
            ac = accounts[(r["ECONOMIC_CATEGORY_CODE"], r["ECONOMIC_CATEGORY_LONG_NAME"], r["ECONOMIC_GROUP_CODE"],
                           r["ECONOMIC_GROUP_LONG_NAME"], r["ECONOMIC_BUDGET_CODE"])]  # fmt: skip
            ac[0].add(f.vintage)
            ac[1].add(year)
            ac[2].add(r["CHART_OF_ACCOUNTS_L5_CODE"])
            ac[3] += 1
        agg = {"total": total_inc, "cb": defaultdict(lambda: ZERO), "dept": defaultdict(lambda: ZERO),
               "org_dept": {}, "dept_name": {}, "seg_dept": defaultdict(lambda: defaultdict(lambda: ZERO)),
               "measure": defaultdict(lambda: ZERO)}  # fmt: skip
        for r in inc:
            for name, (col, cb, eb) in PESA_MEASURES.items():
                if r[col] == cb and r["ECONOMIC_BUDGET_CODE"] == eb:
                    agg["measure"][name] += amt(r)
            agg["cb"][r["CONTROL_BUDGET_L1_LONG_NAME"]] += amt(r)
            agg["dept"][r["DEPARTMENT_GROUP_CODE"]] += amt(r)
            agg["dept"][(r["DEPARTMENT_GROUP_CODE"], r["CONTROL_BUDGET_L1_LONG_NAME"])] += amt(r)
            agg["org_dept"].setdefault(r["ORGANISATION_CODE"], set()).add(r["DEPARTMENT_GROUP_CODE"])
            agg["dept_name"][r["DEPARTMENT_GROUP_CODE"]] = r["DEPARTMENT_GROUP_LONG_NAME"]
            agg["seg_dept"][r["SEGMENT_L4_CODE"]][r["DEPARTMENT_GROUP_CODE"]] += amt(r)
        bud_by_year[(f.vintage, year)] = agg
        log(f"  {f.vintage} {f.filename}: {stats.data_rows} rows, {time.perf_counter() - t1:.1f} s")

    control.sort()
    write_csv(out_audit / "bud_file_control_totals.csv",
              ("vintage", "filename", "sha256", "financial_year", "sheet", "empty_sheets", "columns",
               "header_matches_layout", "total_rows", "blank_rows", "data_rows", "amount_forms", "version_codes",
               "month_values", "status_counts", "n_type_codes", "closed_rows", "closed_rows_with_identical_twin",
               "amount_sum_all_rows", "amount_sum_excluding_closed", "amount_closed", "amount_del", "amount_ame",
               "amount_non_budget", "amount_other_control_budget"), control)  # fmt: skip
    write_csv(
        out_audit / "bud_file_control_totals_by_layer.csv",
        ("vintage", "filename", "financial_year", "dimension", "value", "rows", "amount"),
        sorted(layers),
    )
    write_csv(out_docs / "bud_mog_movements.csv",
              ("financial_year", "vintage", "type_code", "status_code", "department_group_code",
               "department_group_name", "organisation_code", "organisation_name", "rows", "amount"),
              [(*k, n, a) for k, (n, a) in sorted(mog.items())])  # fmt: skip

    latest = max(f.vintage for f in files)
    code_variants = Counter(k[0] for k in dept_map)
    write_csv(out_docs / "bud_department_group_map.csv",
              ("department_group_code", "department_group_name", "sr_group_code", "sr_group_name", "pesa_group_code",
               "pesa_group_name", "vintages", "financial_years", "rows", "in_latest_vintage",
               "variants_for_code"),
              [(*k, " ".join(sorted(v)), " ".join(sorted(y)), n, latest in v, code_variants[k[0]])
               for k, (v, y, n) in sorted(dept_map.items())])  # fmt: skip

    # In-year organisation codes in the latest release, matched against the latest BUD vintage.
    inyear_files = list_inyear_files(root)
    latest_inyear = max(f.release for f in inyear_files)
    latest_orgs: dict[str, str] = {}
    for f in inyear_files:
        if f.release == latest_inyear:
            for r in read_inyear(f, root):
                latest_orgs[r.organisation_code] = r.organisation_name
    bud_latest_orgs = {k[0] for k, v in org_type.items() if latest in v[0]}
    org_variants = Counter(k[0] for k in org_type)
    write_csv(out_docs / "bud_organisation_type.csv",
              ("organisation_code", "organisation_name", "organisation_type_code", "organisation_type_l1_code",
               "organisation_type_l1_name", "department_group_code", "vintages", "financial_years", "rows",
               "in_latest_vintage", "variants_for_code", f"in_inyear_{latest_inyear}"),
              [(*k, " ".join(sorted(v)), " ".join(sorted(y)), n, latest in v, org_variants[k[0]],
                k[0] in latest_orgs) for k, (v, y, n) in sorted(org_type.items())])  # fmt: skip
    unmatched = sorted(set(latest_orgs) - bud_latest_orgs)
    write_csv(out_docs / "bud_inyear_org_match.csv",
              ("organisation_code", "organisation_name", f"in_inyear_{latest_inyear}", f"in_bud_{latest}",
               "same_prefix_in_bud"),
              [(c, latest_orgs.get(c, ""), c in latest_orgs, c in bud_latest_orgs,
                " ".join(sorted(b for b in bud_latest_orgs if split_code(b)[0] == split_code(c)[0] and b != c)))
               for c in sorted(set(latest_orgs) | bud_latest_orgs)])  # fmt: skip

    acc_variants = Counter(k[0] for k in accounts)
    write_csv(out_docs / "bud_account_hierarchy.csv",
              ("economic_category_code", "economic_category_name", "economic_group_code", "economic_group_name",
               "economic_budget_code", "n_chart_of_accounts_l5_codes", "vintages", "financial_years", "rows",
               "in_latest_vintage", "variants_for_code"),
              [(*k, len(l5), " ".join(sorted(v)), " ".join(sorted(y)), n, latest in v, acc_variants[k[0]])
               for k, (v, y, l5, n) in sorted(accounts.items())])  # fmt: skip

    facts = reconcile(root, out_docs, bud_by_year, inyear_files, log)
    facts.update(pesa_check(root, out_docs, bud_by_year))
    facts.update(beis_crosscheck(out_docs, bud_by_year))
    facts["closed_twins"] = closed_twins
    facts["unmatched_inyear_orgs"] = unmatched
    facts["seconds"] = time.perf_counter() - t0
    log(f"profile bud: {len(files)} workbooks, {facts['seconds']:.0f} s")
    return facts


# PESA total line -> (BUD column, value, economic budget) that should reproduce it
PESA_MEASURES = {
    "Total resource DEL": ("CONTROL_BUDGET_L1_LONG_NAME", "DEL", "RESOURCE"),
    "Total capital DEL": ("CONTROL_BUDGET_L1_LONG_NAME", "DEL", "CAPITAL"),
    "Total resource departmental AME": ("CONTROL_BUDGET_L0_LONG_NAME", "DEPT AME", "RESOURCE"),
    "Total capital departmental AME": ("CONTROL_BUDGET_L0_LONG_NAME", "DEPT AME", "CAPITAL"),
}
PESA_SHEETS = {"Total resource DEL": "Table_1_3", "Total resource departmental AME": "Table_1_3",
               "Total capital DEL": "Table_1_8", "Total capital departmental AME": "Table_1_8"}  # fmt: skip


def pesa_check(root: Path, out: Path, bud: dict) -> dict:
    """Published PESA (December 2025 update, £ million) against the BUD totals of the November 2025 vintage."""
    path = None
    for r in read_rows(root / FILES_CSV):
        if r.source_id == "pesa" and "Dec_Chapter_1" in r.filename and r.fetched == "yes":
            path = data_dir(root) / r.path[len(RAW_PREFIX) :] if r.path.startswith(RAW_PREFIX) else root / r.path
    if path is None or not path.is_file():
        return {"pesa_check": "PESA December 2025 file not available"}
    wb = CalamineWorkbook.from_path(str(path))
    rows = []
    for measure, sheet in PESA_SHEETS.items():
        table = wb.get_sheet_by_name(sheet).to_python()
        years = [str(c).strip() for c in table[3]]
        line = next(t for t in table if str(t[0]).strip() == measure)
        for i, y in enumerate(years):
            if (latest := ("2025-11", y)) in bud and isinstance(line[i], (int, float)):
                published = Decimal(repr(float(line[i])))
                ours = bud[latest]["measure"][measure]
                ours_m = ours / 1000
                diff = ours_m - published
                rows.append((y, measure, sheet, published, ours, diff, pct(diff, published)))
    write_csv(out / "bud_pesa_check.csv",
              ("financial_year", "pesa_line", "pesa_table", "pesa_published_gbp_m", "bud_2025_11_gbp_000",
               "difference_gbp_m", "difference_share"), sorted(rows))  # fmt: skip
    return {"pesa_check_rows": len(rows)}


def reconcile(root: Path, out: Path, bud: dict, inyear_files, log) -> dict:
    """June in-year release (full year) against each BUD vintage holding that year."""
    years = sorted({y for _v, y in bud})
    june = {release_fy(f.release): f for f in inyear_files if f.release.endswith("-06")}
    tot_rows, dept_rows = [], []
    for year in years:
        f = june.get(year)
        if f is None:
            continue
        rows = list(read_inyear(f, root))
        iy_total = sum((r.amount or ZERO for r in rows), ZERO)
        iy_cb = defaultdict(lambda: ZERO)
        for r in rows:
            iy_cb[CB_NORMAL.get(r.control_budget_code, "OTHER")] += r.amount or ZERO
        for vintage in sorted(v for v, y in bud if y == year):
            agg = bud[(vintage, year)]
            for level, a, b in [("TOTAL", iy_total, agg["total"])] + [
                (cb, iy_cb.get(cb, ZERO), agg["cb"].get(cb, ZERO)) for cb in ("DEL", "AME", "NON-BUDGET")
            ]:
                tot_rows.append((year, f.release, vintage, level, a, b, a - b, pct(a - b, b)))
            # department level: in-year organisation code -> BUD department group of the same code
            iy_dept = defaultdict(lambda: ZERO)
            iy_orgs = defaultdict(set)
            for r in rows:
                groups = agg["org_dept"].get(r.organisation_code)
                g = next(iter(groups)) if groups and len(groups) == 1 else ("AMBIGUOUS" if groups else "UNMATCHED")
                iy_dept[(g, "ALL")] += r.amount or ZERO
                iy_dept[(g, CB_NORMAL.get(r.control_budget_code, "OTHER"))] += r.amount or ZERO
                iy_orgs[g].add(r.organisation_code)
            bud_dept = {(k, "ALL") if isinstance(k, str) else k: v for k, v in agg["dept"].items()}
            for g, level in sorted(set(iy_dept) | set(bud_dept), key=lambda k: (k[1] != "ALL", k[1], k[0])):
                a, b = iy_dept.get((g, level), ZERO), bud_dept.get((g, level), ZERO)
                dept_rows.append(
                    (
                        year,
                        f.release,
                        vintage,
                        level,
                        g,
                        agg["dept_name"].get(g, ""),
                        len(iy_orgs.get(g, ())),
                        a,
                        b,
                        a - b,
                        pct(a - b, b),
                        " ".join(sorted(iy_orgs[g])) if g == "UNMATCHED" else "",
                    )
                )
        log(f"  reconciled {year} ({f.release})")
    write_csv(out / "bud_inyear_reconciliation_total.csv",
              ("financial_year", "inyear_release", "bud_vintage", "level", "inyear_amount", "bud_amount", "gap",
               "gap_share_of_bud"), tot_rows)  # fmt: skip
    write_csv(out / "bud_inyear_reconciliation_department.csv",
              ("financial_year", "inyear_release", "bud_vintage", "control_budget", "department_group_code",
               "department_group_name", "inyear_organisations", "inyear_amount", "bud_amount", "gap",
               "gap_share_of_bud",
               "unmatched_organisation_codes"), dept_rows)  # fmt: skip

    # restatement between vintages for the same year
    rest = []
    for year in years:
        vs = sorted(v for v, y in bud if y == year)
        groups = sorted(set().union(*({k for k in bud[(v, year)]["dept"] if isinstance(k, str)} for v in vs)))
        for g in ["TOTAL", *groups]:
            vals = [bud[(v, year)]["total"] if g == "TOTAL" else bud[(v, year)]["dept"].get(g) for v in vs]
            name = "" if g == "TOTAL" else next((bud[(v, year)]["dept_name"][g] for v in vs
                                                 if g in bud[(v, year)]["dept_name"]), "")  # fmt: skip
            by_v = dict(zip(vs, vals, strict=True))
            first, last = vals[0], vals[-1]
            rest.append(
                (
                    year,
                    g,
                    name,
                    by_v.get("2023-11"),
                    by_v.get("2024-11"),
                    by_v.get("2025-11"),
                    len(vs),
                    None if first is None or last is None else last - first,
                    "" if first is None or last is None else pct(last - first, first),
                )
            )
    write_csv(out / "bud_vintage_restatement.csv",
              ("financial_year", "department_group_code", "department_group_name", "amount_2023_11", "amount_2024_11",
               "amount_2025_11", "n_vintages", "change_first_to_last", "change_share"), rest)  # fmt: skip
    return {"recon_rows": len(tot_rows)}


def beis_crosscheck(out: Path, bud: dict) -> dict:
    """Successor departments of the last BEIS release's sub-segments, read from the restated BUD year."""
    path = out / "org_beis_subsegment_map_candidates.csv"
    if not path.is_file():
        return {}
    with open(path, encoding="utf-8", newline="") as f:
        cands = list(csv.DictReader(f))
    rows = []
    for vintage, year in sorted(bud):
        if year != "2022-23":
            continue
        seg = bud[(vintage, year)]["seg_dept"]
        names = bud[(vintage, year)]["dept_name"]
        for c in cands:
            present = seg.get(c["sub_segment_code"], {})
            groups = {g for g, a in present.items() if a != 0}  # groups where the segment nets to non-zero
            bud_names = " / ".join(sorted(norm_name(names.get(g, g)) for g in groups))
            rows.append(
                (
                    vintage,
                    c["sub_segment_code"],
                    c["core_or_body"],
                    c["amount_full_year"],
                    c["successor_departments"],
                    " ".join(sorted(groups)),
                    bud_names,
                    sum(present.values(), ZERO),
                    ("not_in_bud" if not present else "nets_to_zero")
                    if not groups
                    else ("one_group" if len(groups) == 1 else "several_groups"),
                )
            )
    write_csv(out / "bud_beis_subsegment_crosscheck.csv",
              ("bud_vintage", "sub_segment_code", "core_or_body", "inyear_amount_full_year",
               "inyear_successor_departments", "bud_department_groups", "bud_department_group_names",
               "bud_amount", "bud_status"),
              rows)  # fmt: skip
    return {"beis_crosscheck_rows": len(rows)}
