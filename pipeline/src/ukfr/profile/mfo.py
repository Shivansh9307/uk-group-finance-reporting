"""Profile the MFO forecast returns (FY2021-22, FY2022-23)."""

from __future__ import annotations

import pickle
import sys
import time
from collections import Counter, defaultdict
from decimal import Decimal
from pathlib import Path

from ..readers import oscar_mfo as rm

SCAN_VERSION = 2


def scan_return(path: Path, member: str) -> dict:
    t0 = time.perf_counter()
    intern = sys.intern
    cube: dict[tuple, list] = {}
    grain: set = set()
    counters = {
        k: Counter()
        for k in (
            "VERSION_CODE",
            "STATUS_CODE",
            "TYPE_CODE",
            "USAGE_CODE",
            "ACCOUNTS_LONG_NAME",
            "YEAR_SHORT_NAME",
            "MONTH_SHORT_NAME",
            "CONTROL_BUDGET_L0_LONG_NAME",
            "CONTROL_BUDGET_L1_LONG_NAME",
        )
    }
    names: Counter = Counter()
    rows_total = bad_width = 0
    amount_total = Decimal(0)
    stats = rm.RepairStats()
    with rm.open_return(path, member, stats) as (header, ix, rows):
        idx = {k: ix[k] for k in counters}
        i_dgc, i_dgn = ix["DEPARTMENT_GROUP_CODE"], ix["DEPARTMENT_GROUP_LONG_NAME"]
        i_src, i_srn = ix["SR_GROUP_CODE"], ix["SR_GROUP_LONG_NAME"]
        i_org, i_ec, i_eb = ix["ORGANISATION_CODE"], ix["ECONOMIC_CATEGORY_CODE"], ix["ECONOMIC_BUDGET_CODE"]
        i_cb0, i_cb1 = ix["CONTROL_BUDGET_L0_LONG_NAME"], ix["CONTROL_BUDGET_L1_LONG_NAME"]
        i_st, i_ty, i_use, i_acc = ix["STATUS_CODE"], ix["TYPE_CODE"], ix["USAGE_CODE"], ix["ACCOUNTS_LONG_NAME"]
        i_month, i_amt = ix["MONTH_SHORT_NAME"], ix["AMOUNT"]
        ncol = len(header)
        detail_cache: dict = {}
        for row in rows:
            rows_total += 1
            if len(row) != ncol:
                bad_width += 1
                continue
            amt = rm.parse_amount(row[i_amt])
            amount_total += amt
            for k, j in idx.items():
                counters[k][row[j]] += 1
            cbk = (row[i_cb0], row[i_cb1])
            cbd = detail_cache.get(cbk)
            if cbd is None:
                cbd = detail_cache[cbk] = intern(rm.control_budget_detail(*cbk))
            period = rm.parse_period(row[i_month])
            eb = intern(row[i_eb])
            dgc = intern(row[i_dgc])
            key = (period, intern(row[i_st]), intern(row[i_ty]), intern(row[i_use]), intern(row[i_acc]), cbd, eb, dgc)
            c = cube.get(key)
            if c is None:
                cube[key] = [1, amt]
            else:
                c[0] += 1
                c[1] += amt
            grain.add((intern(row[i_org]), intern(row[i_ec]), cbd, eb, period))
            names[(dgc, intern(row[i_dgn]), intern(row[i_src]), intern(row[i_srn]))] += 1
    ret, fy = rm.parse_member(member)
    return {
        "member": member,
        "return": ret,
        "fy": fy,
        "ncol": len(header),
        "header": header,
        "rows": rows_total,
        "bad_width": bad_width,
        "joined_rows": list(stats.joined),
        "amount_total": amount_total,
        "seconds": round(time.perf_counter() - t0, 1),
        "cube": cube,
        "grain_keys": len(grain),
        "counters": {k: dict(v) for k, v in counters.items()},
        "names": dict(names),
    }


def scan_zip(path: Path) -> dict:
    t0 = time.perf_counter()
    out = {"scan_version": SCAN_VERSION, "file": path.name, "bytes_zip": path.stat().st_size, "returns": []}
    for _ret, _fy, member in rm.returns(path):
        out["returns"].append(scan_return(path, member))
    out["seconds"] = round(time.perf_counter() - t0, 1)
    return out


def cached_scan(path: Path, cache_dir: Path | None) -> dict:
    if cache_dir is None:
        return scan_zip(path)
    cache = cache_dir / f"{path.stem}.mfo.pkl"
    if cache.is_file():
        with open(cache, "rb") as f:
            res = pickle.load(f)
        if res.get("scan_version") == SCAN_VERSION and res.get("bytes_zip") == path.stat().st_size:
            return res
    res = scan_zip(path)
    cache_dir.mkdir(parents=True, exist_ok=True)
    with open(cache, "wb") as f:
        pickle.dump(res, f, protocol=pickle.HIGHEST_PROTOCOL)
    return res


# ---------------------------------------------------------------- reports

MFO_SUBDIRS = [Path("oscar_mfo") / "2022-11", Path("oscar_mfo") / "2023-11"]
DEL = ("DEL PROG", "DEL ADMIN")
# Scopes for totals: name -> predicate on (control budget detail, economic budget)
SCOPES = {
    "RDEL": lambda cbd, eb: cbd in DEL and eb == "RESOURCE",
    "CDEL": lambda cbd, eb: cbd in DEL and eb == "CAPITAL",
    "TDEL": lambda cbd, eb: cbd in DEL,
    "DEPT AME": lambda cbd, eb: cbd == "DEPT AME",
}
FROZEN_PCT = Decimal(1)  # a month counts as settled if it is within 1% of final outturn


def mfo_paths(data_dir: Path) -> list[Path]:
    out = []
    for d in MFO_SUBDIRS:
        out.extend(sorted((data_dir / d).glob("*.zip")))
    return out


def load_scans(data_dir: Path, cache_dir: Path | None, log=print) -> list[dict]:
    scans = []
    for p in mfo_paths(data_dir):
        s = cached_scan(p, cache_dir)
        log(
            f"mfo {p.name}: {len(s['returns'])} returns, {sum(r['rows'] for r in s['returns']):,} rows, "
            f"full stream {s['seconds']} s"
        )
        scans.append(s)
    return scans


def returns_cube(extract_scans: list[dict], mfo_scans: list[dict]) -> dict[tuple, Decimal]:
    """(fiscal year, source, return, period, group code, control budget detail, economic budget) -> amount.

    Extract years use versions R0-R13, periods 1-12 (TYPE_INYEAR is the only type there), every status
    (DRAFT and CONFIRMED rows never come from the same organisation in one return). MFO years use every row.
    FY2021-22 is taken from the MFO files; the extract holds only its R13, which matches MFO R13 to
    rounding."""
    from .extract import RETURN_VERSIONS, _cube_rows, fiscal_year

    cube: dict[tuple, Decimal] = defaultdict(Decimal)
    mfo_years = {r["fy"] for s in mfo_scans for r in s["returns"]}
    for s in extract_scans:
        fy = fiscal_year(s)
        if fy in mfo_years:
            continue
        for ver, per, _st, _ty, _use, _acc, _cb0, cbd, eb, dgc, _n, a in _cube_rows(s):
            if ver in RETURN_VERSIONS and 1 <= per <= 12:
                cube[(fy, "extract", int(ver[1:]), per, dgc, cbd, eb)] += a
    for s in mfo_scans:
        for r in s["returns"]:
            for (per, _st, _ty, _use, _acc, cbd, eb, dgc), (_n, a) in r["cube"].items():
                cube[(r["fy"], "mfo", r["return"], per, dgc, cbd, eb)] += a
    return cube


def _names(extract_scans: list[dict], mfo_scans: list[dict]) -> dict[tuple, str]:
    from .extract import fiscal_year, group_names

    out = {}
    for s in extract_scans:
        for k, v in group_names(s).items():
            out[(fiscal_year(s), k)] = v
    for s in mfo_scans:
        for r in s["returns"]:
            for (dgc, dgn, _src, _srn), _n in r["names"].items():
                out.setdefault((r["fy"], dgc), dgn)
    return out


def return_month_totals(mfo_scans: list[dict]) -> list[list]:
    rows = []
    for s in mfo_scans:
        for r in s["returns"]:
            agg: dict[tuple, list] = defaultdict(lambda: [0, Decimal(0)])
            for (per, _st, _ty, _use, _acc, cbd, eb, _dgc), (n, a) in r["cube"].items():
                agg[(per, cbd, eb)][0] += n
                agg[(per, cbd, eb)][1] += a
            for k in sorted(agg):
                rows.append([r["fy"], r["return"], r["member"], *k, agg[k][0], agg[k][1]])
    return rows


def file_control_totals(mfo_scans: list[dict]) -> list[list]:
    rows = []
    for s in mfo_scans:
        for r in s["returns"]:
            c = r["counters"]
            rows.append(
                [
                    s["file"],
                    r["member"],
                    r["fy"],
                    r["return"],
                    r["ncol"],
                    r["rows"],
                    r["bad_width"],
                    len(r["joined_rows"]),
                    ";".join(str(x) for x in r["joined_rows"]),
                    r["amount_total"],
                    ";".join(sorted(c["MONTH_SHORT_NAME"])),
                    ";".join(f"{k}={v}" for k, v in sorted(c["VERSION_CODE"].items())),
                    ";".join(f"{k}={v}" for k, v in sorted(c["STATUS_CODE"].items())),
                    ";".join(f"{k}={v}" for k, v in sorted(c["TYPE_CODE"].items())),
                    ";".join(f"{k}={v}" for k, v in sorted(c["USAGE_CODE"].items())),
                    r["grain_keys"],
                ]
            )
    return rows


INYEAR_COMPARE = [("2021-22", "2022-06"), ("2022-23", "2023-06")]


def r13_vs_inyear(mfo_scans: list[dict], repo_root: Path) -> list[list]:
    from .extract import inyear_release_path, inyear_rows

    rows = []
    for fy, rel in INYEAR_COMPARE:
        r13 = next((r for s in mfo_scans for r in s["returns"] if r["fy"] == fy and r["return"] == 13), None)
        path = inyear_release_path(repo_root, rel)
        if r13 is None or path is None:
            continue
        m: dict[tuple, Decimal] = defaultdict(Decimal)
        for (per, _st, _ty, _use, _acc, cbd, eb, _dgc), (_n, a) in r13["cube"].items():
            m[(per, cbd, "n/a" if eb in ("NA", "n/a", "") else eb)] += a
        i: dict[tuple, Decimal] = defaultdict(Decimal)
        versions = set()
        for _org, _dept, cbd, eb, _pg, v, _y, per, a in inyear_rows(path):
            i[(per, cbd, "n/a" if eb in ("NA", "n/a", "") else eb)] += a
            versions.add(v)
        for k in sorted(set(m) | set(i)):
            a, b = m.get(k, Decimal(0)), i.get(k, Decimal(0))
            rows.append([fy, rel, ";".join(sorted(versions)), *k, a, b, a - b])
    return rows


def _by(cube, fy, pred, group=False):
    """{(return, period[, group]) -> amount} for one year and scope."""
    out: dict[tuple, Decimal] = defaultdict(Decimal)
    for (y, _src, ret, per, dgc, cbd, eb), a in cube.items():
        if y == fy and pred(cbd, eb):
            out[(ret, per, dgc) if group else (ret, per)] += a
    return out


def _years(cube) -> list[tuple[str, str, list[int]]]:
    yrs: dict[tuple, set] = defaultdict(set)
    for fy, src, ret, *_r in cube:
        yrs[(fy, src)].add(ret)
    return [(fy, src, sorted(rets)) for (fy, src), rets in sorted(yrs.items())]


def top_groups(cube, fy, n=10) -> list[str]:
    tot: dict[str, Decimal] = defaultdict(Decimal)
    for (y, _src, ret, _per, dgc, cbd, eb), a in cube.items():
        if y == fy and ret == 13 and SCOPES["TDEL"](cbd, eb):
            tot[dgc] += a
    return [k for k, _ in sorted(tot.items(), key=lambda x: (-abs(x[1]), x[0]))[:n]]


def revisions(cube) -> list[list]:
    """Q7: for every return n and month m, the return's value against final outturn (R13)."""
    from .extract import pct

    rows = []
    pred = SCOPES["TDEL"]
    for fy, src, rets in _years(cube):
        tot = _by(cube, fy, pred)
        grp = _by(cube, fy, pred, group=True)
        top = set(top_groups(cube, fy))
        groups = sorted({k[2] for k in grp})
        for n in rets:
            for m in range(1, 13):
                v, f = tot.get((n, m), Decimal(0)), tot.get((13, m), Decimal(0))
                dev_all = sum(
                    (abs(grp.get((n, m, g), Decimal(0)) - grp.get((13, m, g), Decimal(0))) for g in groups), Decimal(0)
                )
                base_all = sum((abs(grp.get((13, m, g), Decimal(0))) for g in groups), Decimal(0))
                dev_top = sum(
                    (abs(grp.get((n, m, g), Decimal(0)) - grp.get((13, m, g), Decimal(0))) for g in top), Decimal(0)
                )
                base_top = sum((abs(grp.get((13, m, g), Decimal(0))) for g in top), Decimal(0))
                rows.append(
                    [
                        fy,
                        src,
                        n,
                        m,
                        n - m,
                        "actual" if m <= n else "forecast",
                        v,
                        f,
                        v - f,
                        pct(abs(v - f), abs(f)),
                        dev_all,
                        pct(dev_all, base_all),
                        dev_top,
                        pct(dev_top, base_top),
                    ]
                )
    return rows


def arrears(cube, names) -> list[list]:
    """Per department group and year: how often the month a return has just closed (lag 0), the month
    before it (lag 1) and the month after it (lag -1, a forecast under the rule) are already within
    FROZEN_PCT of final outturn. A group whose lag-0 months look like its forecasts reports in arrears."""
    from .extract import pct

    rows = []
    pred = SCOPES["TDEL"]
    for fy, _src, rets in _years(cube):
        grp = _by(cube, fy, pred, group=True)
        final: dict[str, Decimal] = defaultdict(Decimal)
        for (ret, _m, g), a in grp.items():
            if ret == 13:
                final[g] += a
        for g in sorted(final, key=lambda x: (-abs(final[x]), x)):
            if abs(final[g]) < 1_000_000:  # under £1bn a year: too small to judge month by month
                continue
            counts = {}
            for lag in (-1, 0, 1, 2):
                settled = total = 0
                for n in rets:
                    if n == 13:
                        continue
                    m = n - lag
                    if not 1 <= m <= 12:
                        continue
                    f = grp.get((13, m, g), Decimal(0))
                    v = grp.get((n, m, g), Decimal(0))
                    if f == 0:
                        continue
                    total += 1
                    if Decimal(100) * abs(v - f) / abs(f) <= FROZEN_PCT:
                        settled += 1
                counts[lag] = (settled, total)
            s0, t0 = counts[0]
            s1, t1 = counts[1]
            sf, tf = counts[-1]
            share0 = pct(Decimal(s0), Decimal(t0)) if t0 else None
            share1 = pct(Decimal(s1), Decimal(t1)) if t1 else None
            sharef = pct(Decimal(sf), Decimal(tf)) if tf else None
            s2, t2 = counts[2]
            share2 = pct(Decimal(s2), Decimal(t2)) if t2 else None
            verdict = ""
            if share0 is not None and share1 is not None:
                if share0 < 50 and share1 >= 50:
                    verdict = "one month in arrears"
                elif share1 < 50 and share2 is not None and share2 >= 50:
                    verdict = "two months in arrears"
                elif share0 >= 50:
                    verdict = "current"
                else:
                    verdict = "revises actuals heavily"
            rows.append([fy, g, names.get((fy, g), ""), final[g], sharef, share0, share1, share2, verdict])
    return rows


def accuracy(cube) -> list[list]:
    """Q8: full-year forecast in each return (all twelve months as the return states them) against final
    outturn, in total and across departments (WAPE: sum of absolute department errors / sum of absolute
    department outturn)."""
    from .extract import pct

    rows = []
    for fy, src, rets in _years(cube):
        for scope, pred in SCOPES.items():
            grp = _by(cube, fy, pred, group=True)
            year: dict[tuple, Decimal] = defaultdict(Decimal)
            for (ret, _m, g), a in grp.items():
                year[(ret, g)] += a
            groups = sorted({g for _r, g in year})
            final = {g: year.get((13, g), Decimal(0)) for g in groups}
            ftot = sum(final.values(), Decimal(0))
            fabs = sum((abs(v) for v in final.values()), Decimal(0))
            for n in rets:
                fc = {g: year.get((n, g), Decimal(0)) for g in groups}
                tot = sum(fc.values(), Decimal(0))
                abs_err = sum((abs(fc[g] - final[g]) for g in groups), Decimal(0))
                # groups missing from the return, and groups whose return is off by a factor of 20 or more
                # (units entered in pounds rather than thousands): reported, then left out of the like-for-like
                missing = [g for g in groups if fc[g] == 0 and final[g] != 0]
                scale = [g for g in groups if abs(fc[g]) > 20 * abs(final[g]) and abs(fc[g]) > 1_000_000]
                keep = [g for g in groups if g not in missing and g not in scale]
                k_fc = sum((fc[g] for g in keep), Decimal(0))
                k_final = sum((final[g] for g in keep), Decimal(0))
                k_abs = sum((abs(fc[g] - final[g]) for g in keep), Decimal(0))
                k_base = sum((abs(final[g]) for g in keep), Decimal(0))
                rows.append(
                    [
                        fy,
                        src,
                        scope,
                        n,
                        tot,
                        ftot,
                        tot - ftot,
                        pct(tot - ftot, abs(ftot)),
                        abs_err,
                        pct(abs_err, fabs),
                        pct(k_base, fabs),
                        ";".join(missing),
                        ";".join(scale),
                        k_fc - k_final,
                        pct(k_fc - k_final, abs(k_final)),
                        pct(k_abs, k_base),
                    ]
                )
    return rows


def history(extract_scans: list[dict], repo_root: Path) -> list[list]:
    """Q9: which years have twelve months of final outturn for seasonality, and from where."""
    from .extract import INYEAR_DIR, fiscal_year

    rows = []
    for s in extract_scans:
        months = sorted({p for ver, p, *_r in _iter_r13(s)})
        rows.append([fiscal_year(s), "annual extract R13 (Nov 2022)", len([m for m in months if 1 <= m <= 12])])
    from .extract import inyear_rows

    for d in sorted((repo_root / INYEAR_DIR).iterdir()):
        if not d.name.endswith("-06"):
            continue
        files = sorted(p for p in d.iterdir() if p.suffix.lower() in (".zip", ".csv"))
        if not files:
            continue
        months = set()
        years = set()
        versions = set()
        for _org, _dept, _cbd, _eb, _pg, v, y, per, _a in inyear_rows(files[0]):
            months.add(per)
            years.add(y)
            versions.add(v)
        rows.append(
            [
                ";".join(sorted(years)),
                f"in-year release {d.name} ({';'.join(sorted(versions))})",
                len([m for m in months if 1 <= m <= 12]),
            ]
        )
    return rows


def _iter_r13(scan):
    from .extract import _cube_rows

    for ver, per, *_r in _cube_rows(scan):
        if ver == "R13":
            yield ver, per


def run(repo_root: Path, data_dir: Path, cache_dir: Path | None, extract_scans: list[dict], log=print) -> None:
    from .extract import AUDIT, PROFILE_DATA, write_csv

    scans = load_scans(data_dir, cache_dir, log)
    cube = returns_cube(extract_scans, scans)
    names = _names(extract_scans, scans)
    out = repo_root / PROFILE_DATA
    outputs = [
        (
            out / "mfo_return_month_totals.csv",
            [
                "fiscal_year",
                "return",
                "member",
                "period",
                "control_budget_detail",
                "economic_budget",
                "rows",
                "amount_gbp_thousand",
            ],
            return_month_totals(scans),
        ),
        (
            repo_root / AUDIT / "mfo_file_control_totals.csv",
            [
                "zip",
                "member",
                "fiscal_year",
                "return",
                "columns",
                "rows",
                "rows_wrong_width",
                "rows_rejoined",
                "rejoined_record_numbers",
                "amount_total_gbp_thousand",
                "months",
                "version_codes",
                "status_codes",
                "type_codes",
                "usage_codes",
                "keys_org_econcat_cb_eb_month",
            ],
            file_control_totals(scans),
        ),
        (
            out / "mfo_r13_vs_inyear.csv",
            [
                "fiscal_year",
                "inyear_release",
                "inyear_versions",
                "period",
                "control_budget_detail",
                "economic_budget",
                "mfo_r13_gbp_thousand",
                "inyear_gbp_thousand",
                "gap_gbp_thousand",
            ],
            r13_vs_inyear(scans, repo_root),
        ),
        (
            out / "mfo_revision_by_month_return.csv",
            [
                "fiscal_year",
                "source",
                "return",
                "period",
                "lag",
                "label_by_hmt_rule",
                "tdel_return_gbp_thousand",
                "tdel_final_gbp_thousand",
                "revision_gbp_thousand",
                "abs_revision_pct",
                "group_abs_revision_gbp_thousand",
                "group_abs_revision_pct",
                "top10_abs_revision_gbp_thousand",
                "top10_abs_revision_pct",
            ],
            revisions(cube),
        ),
        (
            out / "mfo_arrears_by_group.csv",
            [
                "fiscal_year",
                "department_group_code",
                "department_group_name",
                "tdel_final_gbp_thousand",
                "settled_pct_lag_minus1",
                "settled_pct_lag0",
                "settled_pct_lag1",
                "settled_pct_lag2",
                "verdict",
            ],
            arrears(cube, names),
        ),
        (
            out / "mfo_forecast_accuracy.csv",
            [
                "fiscal_year",
                "source",
                "scope",
                "return",
                "full_year_forecast_gbp_thousand",
                "final_gbp_thousand",
                "error_gbp_thousand",
                "error_pct",
                "group_abs_error_gbp_thousand",
                "group_wape_pct",
                "final_covered_pct",
                "groups_missing",
                "groups_scale_error",
                "like_for_like_error_gbp_thousand",
                "like_for_like_error_pct",
                "like_for_like_wape_pct",
            ],
            accuracy(cube),
        ),
        (
            out / "mfo_outturn_history.csv",
            ["fiscal_years", "source", "months_of_outturn"],
            history(extract_scans, repo_root),
        ),
    ]
    for path, header, rows in outputs:
        n = write_csv(path, header, rows)
        log(f"wrote {path.relative_to(repo_root).as_posix()} ({n} rows)")
