"""Profile the OSCAR annual extracts (November 2022 release, FY2017-18 to FY2021-22).

One full streaming pass per file collects everything the questions need (`scan_extract`); the
pass result is cached as a pickle so the reports can be rebuilt without re-reading 3 GB. The
report functions only read the scan results.
"""

from __future__ import annotations

import pickle
import sys
import time
from collections import Counter, defaultdict
from decimal import Decimal
from pathlib import Path

from ..readers import oscar_extract as rx

SCAN_VERSION = 2
EMPTY = frozenset({"", " ", "n/a", "N/A"})


def scan_extract(path: Path) -> dict:
    """Stream one extract and aggregate it. Every row is counted; amounts are summed as Decimal."""
    t0 = time.perf_counter()
    intern = sys.intern
    cube: dict[tuple, list] = {}
    grain: dict[tuple, Decimal] = {}
    fill: dict[str, list[int]] = {}
    vrows: Counter = Counter()
    coa: dict[str, set] = defaultdict(set)
    cat_group: Counter = Counter()
    names: Counter = Counter()
    org_group: Counter = Counter()
    dates: dict[str, list[str]] = {}
    years: Counter = Counter()
    bad_width = 0
    rows_total = 0
    amount_total = Decimal(0)
    with rx.open_extract(path) as (header, ix, rows):
        i_year = ix["YEAR_SHORT_NAME"]
        i_month = ix["MONTH_SHORT_NAME"]
        i_dgc = ix["DEPARTMENT_GROUP_CODE"]
        i_dgn = ix["DEPARTMENT_GROUP_LONG_NAME"]
        i_org = ix["ORGANISATION_CODE"]
        i_src = ix["SR_GROUP_CODE"]
        i_srn = ix["SR_GROUP_LONG_NAME"]
        i_pgn = ix["PESA_GROUP_LONG_NAME"]
        i_seg = ix["SEGMENT_L4_CODE"]
        i_cb0 = ix["CONTROL_BUDGET_L0_LONG_NAME"]
        i_cb1 = ix["CONTROL_BUDGET_L1_LONG_NAME"]
        i_acc = ix["ACCOUNTS_LONG_NAME"]
        i_coa = ix["CHART_OF_ACCOUNTS_L5_CODE"]
        i_eb = ix["ECONOMIC_BUDGET_CODE"]
        i_eg = ix["ECONOMIC_GROUP_CODE"]
        i_ec = ix["ECONOMIC_CATEGORY_CODE"]
        i_use = ix["USAGE_CODE"]
        i_st = ix["STATUS_CODE"]
        i_ty = ix["TYPE_CODE"]
        i_ver = ix["VERSION_CODE"]
        i_amt = ix["AMOUNT"]
        i_dt = ix["DATA_EFFECTIVE_DATETIME"]
        ncol = len(header)
        for row in rows:
            rows_total += 1
            if len(row) != ncol:
                bad_width += 1
                continue
            amt = rx.parse_amount(row[i_amt])
            amount_total += amt
            ver = intern(row[i_ver])
            st = intern(row[i_st])
            month = intern(row[i_month])
            cb1 = intern(row[i_cb1])
            eb = intern(row[i_eb])
            dgc = intern(row[i_dgc])
            key = (
                ver,
                month,
                st,
                intern(row[i_ty]),
                intern(row[i_use]),
                intern(row[i_acc]),
                intern(row[i_cb0]),
                cb1,
                eb,
                dgc,
            )
            c = cube.get(key)
            if c is None:
                cube[key] = [1, amt]
            else:
                c[0] += 1
                c[1] += amt
            ec = intern(row[i_ec])
            gk = (ver, st, intern(row[i_org]), intern(row[i_seg]), ec, cb1, eb, month)
            grain[gk] = grain.get(gk, 0) + amt
            f = fill.get(ver)
            if f is None:
                f = fill[ver] = [0] * ncol
            for j, v in enumerate(row):
                if v not in EMPTY:
                    f[j] += 1
            vrows[ver] += 1
            coa[ver].add(intern(row[i_coa]))
            cat_group[(ec, intern(row[i_eg]))] += 1
            names[(dgc, intern(row[i_dgn]), intern(row[i_src]), intern(row[i_srn]), intern(row[i_pgn]))] += 1
            years[row[i_year]] += 1
            org_group[(gk[2], dgc)] += 1
            dt = row[i_dt]
            d = dates.get(ver)
            if d is None:
                dates[ver] = [dt, dt]
            else:
                if dt < d[0]:
                    d[0] = dt
                if dt > d[1]:
                    d[1] = dt
    return {
        "scan_version": SCAN_VERSION,
        "file": path.name,
        "bytes_zip": path.stat().st_size,
        "member": rx.member_name(path),
        "header": header,
        "rows": rows_total,
        "bad_width": bad_width,
        "amount_total": amount_total,
        "seconds": round(time.perf_counter() - t0, 1),
        "cube": cube,
        "grain": grain,
        "fill": fill,
        "vrows": dict(vrows),
        "coa": {k: set(v) for k, v in coa.items()},
        "cat_group": dict(cat_group),
        "names": dict(names),
        "org_group": dict(org_group),
        "dates": dates,
        "years": dict(years),
    }


# ---------------------------------------------------------------- in-year comparison (inline, not a reader)

INYEAR_DIR = Path("data") / "committed" / "oscar_inyear"


def _inyear_amount(s: str) -> Decimal:
    s = s.strip().replace(",", "")
    return Decimal(s) if s else Decimal(0)


def inyear_rows(path: Path):
    """Rows of one committed in-year release (zip holding a CSV, or a bare CSV), as tuples
    (org code, department, control budget detail, economic budget, PESA economic group, version, year,
    period, amount). Every layout from March 2019 to September 2026 has these in the same positions:
    columns 0, 4, 3, 9, 10 and the last five (version, year, quarter, month, amount). The March 2026
    release (an ODS only) is not read. This is a profiling helper, not the in-year reader."""
    import csv
    import io
    import zipfile

    if path.suffix.lower() == ".zip":
        z = zipfile.ZipFile(path)
        names = [n for n in z.namelist() if n.lower().endswith(".csv")]
        if not names:
            return
        fh = io.TextIOWrapper(z.open(names[0]), encoding="cp1252", newline="")
    else:
        fh = open(path, encoding="cp1252", newline="")
    with fh:
        r = csv.reader(fh)
        next(r)
        for row in r:
            if not row or not row[0].strip():
                continue
            yield (
                row[0],
                row[4],
                row[3],
                row[9],
                row[10],
                row[-5],
                row[-4],
                rx.month_period(row[-2]),
                _inyear_amount(row[-1]),
            )


def inyear_release_path(repo_root: Path, release: str) -> Path | None:
    d = repo_root / INYEAR_DIR / release
    if not d.is_dir():
        return None
    files = sorted(p for p in d.iterdir() if p.suffix.lower() in (".zip", ".csv"))
    return files[0] if files else None


def cached_scan(path: Path, cache_dir: Path | None) -> dict:
    """Scan, or load the scan of the same zip (name and size) from `cache_dir`."""
    if cache_dir is None:
        return scan_extract(path)
    cache = cache_dir / f"{path.stem}.scan.pkl"
    if cache.is_file():
        with open(cache, "rb") as f:
            res = pickle.load(f)
        if res.get("scan_version") == SCAN_VERSION and res.get("bytes_zip") == path.stat().st_size:
            return res
    res = scan_extract(path)
    cache_dir.mkdir(parents=True, exist_ok=True)
    with open(cache, "wb") as f:
        pickle.dump(res, f, protocol=pickle.HIGHEST_PROTOCOL)
    return res


# ---------------------------------------------------------------- output helpers (shared by the profile modules)

EXTRACT_SUBDIR = Path("oscar_annual_extract") / "2022-11"
PROFILE_DATA = Path("docs") / "profiling" / "data"
AUDIT = Path("data") / "audit"


def fmt(v) -> str:
    """Decimal -> plain text with no exponent and no trailing zeros; None -> ''."""
    if v is None:
        return ""
    if isinstance(v, Decimal):
        if v == 0:
            return "0"
        return format(v.normalize(), "f")
    return str(v)


def pct(num: Decimal, den: Decimal, places: int = 2) -> Decimal | None:
    if den == 0:
        return None
    return (Decimal(100) * num / den).quantize(Decimal(1).scaleb(-places))


def write_csv(path: Path, header: list[str], rows) -> int:
    import csv

    path.parent.mkdir(parents=True, exist_ok=True)
    n = 0
    with open(path, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(header)
        for r in rows:
            w.writerow([fmt(v) for v in r])
            n += 1
    return n


def version_order(v: str) -> int:
    if v == "PLANS":
        return -1
    if v.startswith("R") and v[1:].isdigit():
        return int(v[1:])
    return 99


def fiscal_year(scan: dict) -> str:
    years = list(scan["years"])
    if len(years) != 1:
        raise ValueError(f"{scan['file']}: more than one YEAR_SHORT_NAME: {years}")
    return years[0]


def extract_paths(data_dir: Path) -> list[Path]:
    return sorted((data_dir / EXTRACT_SUBDIR).glob("2022_OSCAR_Extract_*.zip"))


def load_scans(data_dir: Path, cache_dir: Path | None, log=print) -> list[dict]:
    scans = []
    for p in extract_paths(data_dir):
        t0 = time.perf_counter()
        s = cached_scan(p, cache_dir)
        log(
            f"extract {p.name}: {s['rows']:,} rows, full stream {s['seconds']} s "
            f"(this call {time.perf_counter() - t0:.1f} s)"
        )
        scans.append(s)
    return scans


# ---------------------------------------------------------------- reports

RETURN_VERSIONS = [f"R{i}" for i in range(14)]


def _cube_rows(scan: dict):
    """(version, period, status, type, usage, accounts, cb_l0, cb detail, economic budget, group code, n, amount)."""
    for (ver, month, st, ty, use, acc, cb0, cb1, eb, dgc), (n, a) in scan["cube"].items():
        yield ver, rx.month_period(month), st, ty, use, acc, cb0, rx.control_budget_detail(cb1), eb, dgc, n, a


def version_period_status(scans: list[dict]) -> list[list]:
    agg: dict[tuple, list] = defaultdict(lambda: [0, Decimal(0)])
    for s in scans:
        fy = fiscal_year(s)
        for ver, per, st, *_rest, n, a in _cube_rows(s):
            x = agg[(fy, ver, per, st)]
            x[0] += n
            x[1] += a
    keys = sorted(agg, key=lambda k: (k[0], version_order(k[1]), k[2], k[3]))
    return [[*k, agg[k][0], agg[k][1]] for k in keys]


def control_totals(scans: list[dict], data_dir: Path) -> list[list]:
    out = []
    for s in scans:
        p = data_dir / EXTRACT_SUBDIR / s["file"]
        info = next(i for i in rx.zipstream.members(p) if i.filename == s["member"])
        vr = s["vrows"]
        out.append(
            [
                s["file"],
                s["member"],
                fiscal_year(s),
                s["bytes_zip"],
                info.file_size,
                rx.zipstream.METHOD_NAMES.get(info.compress_type, info.compress_type),
                len(s["header"]),
                s["rows"],
                s["bad_width"],
                s["amount_total"],
                len(vr),
                vr.get("PLANS", 0),
                vr.get("R13", 0),
                sum(vr.get(v, 0) for v in RETURN_VERSIONS[:13]),
            ]
        )
    return out


def return_completeness(scans: list[dict]) -> list[list]:
    rows = []
    for s in scans:
        fy = fiscal_year(s)
        months: dict[str, set] = defaultdict(set)
        status: dict[str, Counter] = defaultdict(Counter)
        types: dict[str, set] = defaultdict(set)
        for ver, per, st, ty, *_rest, n, _a in _cube_rows(s):
            months[ver].add(per)
            status[ver][st] += n
            types[ver].add(ty)
        for ver in sorted(months, key=version_order):
            ms = sorted(months[ver])
            rows.append(
                [
                    fy,
                    ver,
                    len([m for m in ms if 1 <= m <= 12]),
                    "yes" if 0 in ms else "no",
                    ";".join(f"{k}={v}" for k, v in sorted(status[ver].items())),
                    s["vrows"][ver],
                    s["dates"][ver][0],
                    s["dates"][ver][1],
                    ";".join(sorted(types[ver])),
                ]
            )
    return rows


def layers(scans: list[dict]) -> list[list]:
    """Rows and amounts by version class x period class x status x type x usage x accounts x control budget."""
    agg: dict[tuple, list] = defaultdict(lambda: [0, Decimal(0)])
    for s in scans:
        fy = fiscal_year(s)
        for ver, per, st, ty, use, acc, _cb0, cbd, _eb, _dgc, n, a in _cube_rows(s):
            vc = ver if ver in ("PLANS", "R13") else "R0-R12"
            x = agg[(fy, vc, "0" if per == 0 else "1-12", st, ty, use, acc, cbd)]
            x[0] += n
            x[1] += a
    return [[*k, v[0], v[1]] for k, v in sorted(agg.items())]


# The June in-year release that carries each extract year's year-end return.
INYEAR_COMPARE = [
    ("2018-19", "R13", "2019-06"),
    ("2019-20", "R12", "2020-06"),
    ("2019-20", "R13", "2020-06"),
    ("2020-21", "R13", "2021-06"),
    ("2021-22", "R13", "2022-06"),
]


def monthly_return_layer(per: int) -> bool:
    """The layer that reproduces the in-year releases: periods 1-12 of a return, every status, both
    TRIAL BALANCE and ADDITIONAL INFORMATION accounts. Period 0 holds budget-type adjustments only."""
    return 1 <= per <= 12


def _org_group(scan: dict) -> dict[str, str]:
    og: dict[str, str] = {}
    for (org, dgc), _n in sorted(scan["org_group"].items(), key=lambda x: (-x[1], x[0])):
        og.setdefault(org, dgc)
    return og


def group_names(scan: dict) -> dict[str, str]:
    out: dict[str, Counter] = defaultdict(Counter)
    for (dgc, dgn, _src, _srn, _pgn), n in scan["names"].items():
        out[dgc][dgn] += n
    return {k: sorted(v.items(), key=lambda x: (-x[1], x[0]))[0][0] for k, v in out.items()}


def r13_vs_inyear(scans: list[dict], repo_root: Path) -> tuple[list[list], list[list]]:
    by = {fiscal_year(s): s for s in scans}
    rows, groups = [], []
    for fy, ver, rel in INYEAR_COMPARE:
        s = by.get(fy)
        path = inyear_release_path(repo_root, rel)
        if s is None or path is None:
            continue
        ex: dict[tuple, Decimal] = defaultdict(Decimal)
        for v, per, _st, _ty, _use, _acc, _cb0, cbd, eb, _dgc, _n, a in _cube_rows(s):
            if v == ver and monthly_return_layer(per):
                ex[(per, cbd, eb)] += a
        iy: dict[tuple, Decimal] = defaultdict(Decimal)
        iy_org: dict[str, Decimal] = defaultdict(Decimal)
        versions = set()
        for org, _dept, cbd, eb, _pg, v, _y, per, a in inyear_rows(path):
            eb = "n/a" if eb in ("NA", "n/a") else eb
            iy[(per, cbd, eb)] += a
            if cbd in ("DEL PROG", "DEL ADMIN"):
                iy_org[org] += a
            versions.add(v)
        for k in sorted(set(ex) | set(iy)):
            e, i = ex.get(k, Decimal(0)), iy.get(k, Decimal(0))
            rows.append([fy, ver, rel, ";".join(sorted(versions)), *k, e, i, e - i])
        og = _org_group(s)
        ex_org: dict[str, Decimal] = defaultdict(Decimal)
        for (v, _st, org, _seg, _ec, cb1, _eb, month), a in s["grain"].items():
            if (
                v == ver
                and monthly_return_layer(rx.month_period(month))
                and rx.control_budget_detail(cb1) in ("DEL PROG", "DEL ADMIN")
            ):
                ex_org[org] += a
        g: dict[str, list] = defaultdict(lambda: [Decimal(0), Decimal(0)])
        for org in set(ex_org) | set(iy_org):
            dgc = og.get(org, "(organisation not in extract)")
            g[dgc][0] += ex_org.get(org, Decimal(0))
            g[dgc][1] += iy_org.get(org, Decimal(0))
        names = group_names(s)
        for dgc, (a, b) in sorted(g.items(), key=lambda x: (-abs(x[1][0] - x[1][1]), x[0])):
            groups.append([fy, ver, rel, dgc, names.get(dgc, ""), a, b, a - b])
    return rows, groups


def plan_totals(scans: list[dict]) -> list[list]:
    rows = []
    for s in scans:
        fy = fiscal_year(s)
        names = group_names(s)
        agg: dict[tuple, list] = defaultdict(lambda: [Decimal(0), Decimal(0), Decimal(0), 0])
        for ver, per, _st, _ty, _use, _acc, _cb0, cbd, eb, dgc, n, a in _cube_rows(s):
            k = (dgc, cbd, eb)
            if ver == "PLANS":
                agg[k][0] += a
                agg[k][3] += n
            elif ver == "R13":
                agg[k][1 if per >= 1 else 2] += a
        for (dgc, cbd, eb), (p, o, o0, n) in sorted(agg.items()):
            rows.append([fy, dgc, names.get(dgc, ""), cbd, eb, n, p, o, o0, o + o0, p - o])
    return rows


GRAIN_COLUMNS = [
    "ORGANISATION_CODE",
    "SEGMENT_L4_CODE",
    "ECONOMIC_GROUP_CODE",
    "ECONOMIC_CATEGORY_CODE",
    "CHART_OF_ACCOUNTS_L5_CODE",
]


def _econ_group_map(scan: dict) -> dict[str, str]:
    m: dict[str, Counter] = defaultdict(Counter)
    for (ec, eg), n in scan["cat_group"].items():
        m[ec][eg] += n
    return {k: sorted(v.items(), key=lambda x: (-x[1], x[0]))[0][0] for k, v in m.items()}


def fill_rates(scans: list[dict]) -> list[list]:
    rows = []
    for s in scans:
        fy = fiscal_year(s)
        eg = _econ_group_map(s)
        distinct: dict[str, dict[str, set]] = {v: defaultdict(set) for v in ("PLANS", "R13")}
        for ver, _st, org, seg, ec, _cb1, _eb, _m in s["grain"]:
            if ver in distinct:
                d = distinct[ver]
                d["ORGANISATION_CODE"].add(org)
                d["SEGMENT_L4_CODE"].add(seg)
                d["ECONOMIC_CATEGORY_CODE"].add(ec)
                d["ECONOMIC_GROUP_CODE"].add(eg.get(ec, ec))
        for ver in distinct:
            distinct[ver]["CHART_OF_ACCOUNTS_L5_CODE"] = s["coa"].get(ver, set())
        np_, nr = s["vrows"].get("PLANS", 0), s["vrows"].get("R13", 0)
        fp, fr = s["fill"].get("PLANS"), s["fill"].get("R13")
        for j, col in enumerate(s["header"]):
            dp = len(distinct["PLANS"][col]) if col in GRAIN_COLUMNS else None
            dr = len(distinct["R13"][col]) if col in GRAIN_COLUMNS else None
            rows.append(
                [
                    fy,
                    j + 1,
                    col,
                    np_,
                    fp[j] if fp else 0,
                    pct(Decimal(fp[j]), Decimal(np_)) if fp else None,
                    nr,
                    fr[j] if fr else 0,
                    pct(Decimal(fr[j]), Decimal(nr)) if fr else None,
                    dp,
                    dr,
                ]
            )
    return rows


# Grains to test Plans against Outturn, coarse to fine: (name, key function of
# group, organisation, sub-segment, economic category, economic group, control budget detail, economic budget).
GRAINS = [
    ("group x control budget", lambda g, org, seg, ec, eg, cbd, eb: (g, cbd)),
    ("group x control budget x economic budget", lambda g, org, seg, ec, eg, cbd, eb: (g, cbd, eb)),
    ("organisation x control budget x economic budget", lambda g, org, seg, ec, eg, cbd, eb: (org, cbd, eb)),
    ("organisation x control budget x economic group", lambda g, org, seg, ec, eg, cbd, eb: (org, cbd, eb, eg)),
    ("organisation x control budget x economic category", lambda g, org, seg, ec, eg, cbd, eb: (org, cbd, eb, ec)),
    ("organisation x sub-segment x economic category", lambda g, org, seg, ec, eg, cbd, eb: (org, seg, cbd, eb, ec)),
]


def grain_match(scans: list[dict]) -> list[list]:
    """For each grain, DEL only, absolute values: how much Outturn (R13, all periods) sits on keys that
    also carry a Plan, how much Plan sits on keys with Outturn, and the sum of absolute variances as a
    share of absolute outturn (the noise a variance report at that grain would show)."""
    rows = []
    for s in scans:
        fy = fiscal_year(s)
        eg = _econ_group_map(s)
        og = _org_group(s)
        for name, f in GRAINS:
            plan: dict[tuple, Decimal] = defaultdict(Decimal)
            out: dict[tuple, Decimal] = defaultdict(Decimal)
            for (ver, _st, org, seg, ec, cb1, eb, _m), a in s["grain"].items():
                cbd = rx.control_budget_detail(cb1)
                if cbd not in ("DEL PROG", "DEL ADMIN") or ver not in ("PLANS", "R13"):
                    continue
                k = f(og.get(org, ""), org, seg, ec, eg.get(ec, ec), cbd, eb)
                (plan if ver == "PLANS" else out)[k] += a
            pk = {k for k, v in plan.items() if v != 0}
            ok = {k for k, v in out.items() if v != 0}
            out_abs = sum((abs(v) for v in out.values()), Decimal(0))
            plan_abs = sum((abs(v) for v in plan.values()), Decimal(0))
            out_cov = sum((abs(out[k]) for k in ok & pk), Decimal(0))
            plan_cov = sum((abs(plan[k]) for k in ok & pk), Decimal(0))
            var_abs = sum((abs(plan.get(k, Decimal(0)) - out.get(k, Decimal(0))) for k in pk | ok), Decimal(0))
            rows.append(
                [
                    fy,
                    name,
                    len(pk),
                    len(ok),
                    len(pk & ok),
                    pct(out_cov, out_abs),
                    pct(plan_cov, plan_abs),
                    pct(var_abs, out_abs),
                ]
            )
    return rows


def load_row_counts(scans: list[dict]) -> list[list]:
    """Rows a load would hold at version x organisation x economic category x control budget detail x
    economic budget x month (Plans at period 0; returns at periods 1-12)."""
    rows = []
    for s in scans:
        fy = fiscal_year(s)
        keys: dict[str, dict[tuple, Decimal]] = defaultdict(lambda: defaultdict(Decimal))
        for (ver, _st, org, _seg, ec, cb1, eb, month), a in s["grain"].items():
            per = rx.month_period(month)
            if ver != "PLANS" and not monthly_return_layer(per):
                continue
            keys[ver][(org, ec, rx.control_budget_detail(cb1), eb, per)] += a
        for ver in sorted(keys, key=version_order):
            k = keys[ver]
            rows.append([fy, ver, s["vrows"][ver], len(k), sum(1 for v in k.values() if v != 0)])
    return rows


def run(repo_root: Path, data_dir: Path, cache_dir: Path | None, log=print) -> list[dict]:
    scans = load_scans(data_dir, cache_dir, log)
    out = repo_root / PROFILE_DATA
    audit = repo_root / AUDIT
    cmp_rows, cmp_groups = r13_vs_inyear(scans, repo_root)
    outputs = [
        (
            out / "extract_version_period_status.csv",
            ["fiscal_year", "version_code", "period", "status_code", "rows", "amount_gbp_thousand"],
            version_period_status(scans),
        ),
        (
            audit / "extract_file_control_totals.csv",
            [
                "file",
                "member",
                "fiscal_year",
                "zip_bytes",
                "member_bytes",
                "zip_method",
                "columns",
                "rows",
                "rows_wrong_width",
                "amount_total_gbp_thousand",
                "versions",
                "plans_rows",
                "r13_rows",
                "r0_r12_rows",
            ],
            control_totals(scans, data_dir),
        ),
        (
            out / "extract_return_completeness.csv",
            [
                "fiscal_year",
                "version_code",
                "months_1_12_present",
                "period_0_present",
                "rows_by_status",
                "rows",
                "first_data_effective",
                "last_data_effective",
                "type_codes",
            ],
            return_completeness(scans),
        ),
        (
            out / "extract_layers.csv",
            [
                "fiscal_year",
                "version_class",
                "periods",
                "status_code",
                "type_code",
                "usage_code",
                "accounts",
                "control_budget_detail",
                "rows",
                "amount_gbp_thousand",
            ],
            layers(scans),
        ),
        (
            out / "extract_r13_vs_inyear.csv",
            [
                "fiscal_year",
                "version_code",
                "inyear_release",
                "inyear_versions",
                "period",
                "control_budget_detail",
                "economic_budget",
                "extract_gbp_thousand",
                "inyear_gbp_thousand",
                "gap_gbp_thousand",
            ],
            cmp_rows,
        ),
        (
            out / "extract_r13_vs_inyear_del_by_group.csv",
            [
                "fiscal_year",
                "version_code",
                "inyear_release",
                "department_group_code",
                "department_group_name",
                "extract_del_gbp_thousand",
                "inyear_del_gbp_thousand",
                "gap_gbp_thousand",
            ],
            cmp_groups,
        ),
        (
            out / "plan_oscar_totals.csv",
            [
                "fiscal_year",
                "department_group_code",
                "department_group_name",
                "control_budget_detail",
                "economic_budget",
                "plans_rows",
                "plans_gbp_thousand",
                "r13_periods_1_12_gbp_thousand",
                "r13_period_0_gbp_thousand",
                "r13_all_gbp_thousand",
                "plans_minus_r13_months_gbp_thousand",
            ],
            plan_totals(scans),
        ),
        (
            out / "plan_oscar_grain_fill_rates.csv",
            [
                "fiscal_year",
                "column_no",
                "column",
                "plans_rows",
                "plans_populated",
                "plans_fill_pct",
                "r13_rows",
                "r13_populated",
                "r13_fill_pct",
                "plans_distinct",
                "r13_distinct",
            ],
            fill_rates(scans),
        ),
        (
            out / "plan_oscar_grain_match.csv",
            [
                "fiscal_year",
                "grain",
                "plan_keys",
                "outturn_keys",
                "keys_in_both",
                "outturn_on_planned_keys_pct",
                "plan_on_outturn_keys_pct",
                "abs_variance_pct_of_abs_outturn",
            ],
            grain_match(scans),
        ),
        (
            out / "extract_load_row_counts.csv",
            ["fiscal_year", "version_code", "source_rows", "keys_at_load_grain", "nonzero_keys_at_load_grain"],
            load_row_counts(scans),
        ),
    ]
    for path, header, rows in outputs:
        n = write_csv(path, header, rows)
        log(f"wrote {path.relative_to(repo_root).as_posix()} ({n} rows)")
    return scans
