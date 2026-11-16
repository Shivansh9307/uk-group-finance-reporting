"""Profile the plan sources (Estimates DEL tables, PESA Chapter 1, SR25), the Public Spending
Statistics cross-check and the deflators.

The BUD workbooks are read here only for their Spending Review group names and annual DEL totals,
with python-calamine (amounts in BUD are whole £000, so the float calamine returns is exact for
them; they are turned into Decimal straight away). The full BUD reader belongs to the in-year and
BUD profiling work.
"""

from __future__ import annotations

import re
from collections import defaultdict
from decimal import Decimal
from pathlib import Path

from ..readers import deflators as rd
from ..readers import plans as rp
from .extract import AUDIT, PROFILE_DATA, inyear_release_path, inyear_rows, pct, write_csv

BN_TO_K = Decimal(1_000_000)
M_TO_K = Decimal(1_000)
SUPPS_RANK = {"supps": 0, "oot-supps": 1, "mains": 2}


# ---------------------------------------------------------------- Estimates


def estimates_files(data_dir: Path) -> list[tuple[str, Path]]:
    out = []
    for d in sorted((data_dir / "estimates_del").iterdir()):
        for f in sorted(d.glob("*.xlsx")):
            out.append((d.name, f))
    return out


def _release_kind(release: str) -> str:
    return release.split("-", 2)[2]  # '2022-23-oot-supps' -> 'oot-supps'


def estimates(data_dir: Path) -> tuple[list[list], list[list], dict[str, str], list[dict]]:
    """Inventory rows, name/value rows, best release per plan year, and parsed line records."""
    inv, names, records = [], [], []
    years_by_release: dict[str, set] = defaultdict(set)
    for release, path in estimates_files(data_dir):
        for t in rp.read_tables(path):
            measure = rp.estimates_measure(t.title)
            lines = [r for r in t.rows if r.kind == "line"]
            totals = [r for r in t.rows if r.kind == "total"]
            memos = [r for r in t.rows if r.kind == "memo"]
            mult = rp.unit_multiplier_to_thousands(t.unit)
            for y in t.years:
                s = sum((r.values[y] or Decimal(0) for r in lines), Decimal(0))
                tot = totals[-1].values[y] if totals else None
                years_by_release[release].add(y)
                inv.append(
                    [
                        release,
                        path.name,
                        t.sheet,
                        measure,
                        t.title,
                        t.unit,
                        t.unit_row + 1,
                        t.year_row + 1,
                        (t.status_row + 1) if t.status_row is not None else None,
                        y,
                        t.statuses.get(y, ""),
                        len(lines),
                        len(memos),
                        ";".join(r.raw_name for r in memos) if memos else "",
                        totals[-1].raw_name if totals else "",
                        tot,
                        s,
                        (s - tot) if tot is not None else None,
                    ]
                )
                for r in t.rows:
                    v = r.values[y]
                    names.append(
                        [
                            release,
                            path.name,
                            t.sheet,
                            measure,
                            y,
                            r.row + 1,
                            r.raw_name,
                            r.name,
                            r.kind,
                            v,
                            v * mult if v is not None else None,
                        ]
                    )
                    if r.kind == "line" and v is not None:
                        records.append(
                            {
                                "release": release,
                                "measure": measure,
                                "year": y,
                                "name": r.name,
                                "raw": r.raw_name,
                                "gbp_k": v * mult,
                            }
                        )
    best: dict[str, str] = {}
    for release, years in years_by_release.items():
        for y in years:
            if release[:7] != y:
                continue
            cur = best.get(y)
            if cur is None or SUPPS_RANK[_release_kind(release)] < SUPPS_RANK[_release_kind(cur)]:
                best[y] = release
    for row in inv:
        row.append("yes" if best.get(row[9]) == row[0] else "no")
    return inv, names, best, records


# ---------------------------------------------------------------- PESA and SR25

PESA_DIRS = ["2022", "2023", "2024", "2025", "2026", "sr2025"]


def pesa_files(data_dir: Path) -> list[tuple[str, Path]]:
    out = []
    for d in PESA_DIRS:
        for f in sorted((data_dir / "pesa" / d).glob("*.xlsx")):
            label = d
            if "Dec" in f.name:
                label = "2025-12"
            elif d == "2025":
                label = "2025-07"
            out.append((label, f))
    return out


def _section_measure(title: str, section: str) -> str:
    t, s = title.lower(), section.lower()
    real = " (real terms)" if "real terms" in t else ""
    if "administration" in t:
        return ("ADMIN_EX_DEPN" if "excluding depreciation" in t else "ADMIN") + real
    if "resource departmental ame" in s or "resource ame" in s:
        return "RESOURCE_DEPT_AME" + real
    if "capital departmental ame" in s or "capital ame" in s:
        return "CAPITAL_DEPT_AME" + real
    if "excluding depreciation" in s or "excluding depreciation" in t:
        if "resource" in s or "resource" in t:
            return "RDEL_EX_DEPN" + real
    if "resource del" in s or ("resource" in t and "del" in s):
        return "RDEL" + real
    if "capital del" in s or "capital departmental expenditure limits" in t or "capital del" in t:
        return "CDEL" + real
    if "total del" in s or "total departmental expenditure limits" in t.replace("(del)", ""):
        return "TDEL" + real
    if "total managed expenditure by departmental group" in s:
        return "TME" + real
    if "financial transactions" in s:
        return "CDEL_FT" + real
    if "general capital" in s:
        return "CDEL_GENERAL" + real
    return ""


def _is_group_section(title: str, section: str) -> bool:
    s = section.lower()
    t = title.lower()
    return (
        "by departmental group" in s
        or "administration budgets" in t
        or (section == "" and ("departmental expenditure limits" in t or "(del)" in t))
    )


def pesa(data_dir: Path) -> tuple[list[list], list[dict]]:
    inv, records = [], []
    for release, path in pesa_files(data_dir):
        for t in rp.read_tables(path):
            m = re.search(r"Table\s+([\d.]+[a-z]?)", t.title)
            sections: dict[str, list] = defaultdict(list)
            for r in t.rows:
                if r.kind == "line":
                    sections[r.section].append(r)
            plan_years = [y for y in t.years if t.statuses.get(y, "").startswith("plan")]
            out_years = [y for y in t.years if t.statuses.get(y, "").startswith("outturn")]
            for sec, lines in sections.items():
                grp = _is_group_section(t.title, sec)
                measure = _section_measure(t.title, sec) if grp else ""
                inv.append(
                    [
                        release,
                        path.name,
                        t.sheet,
                        m.group(1) if m else "",
                        t.title,
                        t.unit,
                        t.year_row + 1,
                        t.years[0],
                        t.years[-1],
                        ";".join(out_years),
                        ";".join(plan_years),
                        sec,
                        len(lines),
                        "department group" if grp else "aggregate",
                        measure,
                    ]
                )
                if grp and measure:
                    mult = rp.unit_multiplier_to_thousands(t.unit) if t.unit else M_TO_K
                    for r in lines:
                        for y in t.years:
                            v = r.values[y]
                            if v is None:
                                continue
                            records.append(
                                {
                                    "release": release,
                                    "sheet": t.sheet,
                                    "measure": measure,
                                    "year": y,
                                    "status": t.statuses.get(y, ""),
                                    "name": r.name,
                                    "raw": r.raw_name,
                                    "gbp_k": v * mult,
                                }
                            )
    return inv, records


# ---------------------------------------------------------------- BUD Spending Review groups

BUD_DIR = Path("oscar_annual_bud") / "2025-11"


def _bud_rows(path: Path):
    from python_calamine import CalamineWorkbook

    wb = CalamineWorkbook.from_path(str(path))
    rows = wb.get_sheet_by_name(wb.sheet_names[0]).to_python()
    header = [str(c).strip() for c in rows[0]]
    return header, rows[1:]


def bud_sr_groups(data_dir: Path) -> tuple[str, dict[str, str], dict[str, set]]:
    """(file name, SR group long name -> SR group code, SR group -> department group names) from the
    latest BUD workbook."""
    files = sorted((data_dir / BUD_DIR).glob("BUD_*.xlsx"))
    latest = files[-1]
    header, rows = _bud_rows(latest)
    i_code, i_name = header.index("SR_GROUP_CODE"), header.index("SR_GROUP_LONG_NAME")
    i_dg = header.index("DEPARTMENT_GROUP_LONG_NAME")
    codes: dict[str, str] = {}
    groups: dict[str, set] = defaultdict(set)
    for r in rows:
        codes[str(r[i_name])] = str(r[i_code])
        groups[str(r[i_name])].add(str(r[i_dg]))
    return latest.name, codes, groups


def bud_del_by_group(path: Path) -> dict[tuple[str, str], Decimal]:
    """{(SR group, measure) -> £000} for RDEL (all resource DEL), RDEL_EX_DEPN (resource DEL less the
    RINGFENCED economic ringfence) and CDEL, from one BUD workbook."""
    header, rows = _bud_rows(path)
    ix = {
        c: header.index(c)
        for c in (
            "SR_GROUP_LONG_NAME",
            "CONTROL_BUDGET_L1_LONG_NAME",
            "ECONOMIC_BUDGET_CODE",
            "ECONOMIC_RINGFENCE_CODE",
            "AMOUNT",
        )
    }
    out: dict[tuple[str, str], Decimal] = defaultdict(Decimal)
    for r in rows:
        if r[ix["CONTROL_BUDGET_L1_LONG_NAME"]] != "DEL":
            continue
        a = Decimal(int(r[ix["AMOUNT"]])) if float(r[ix["AMOUNT"]]).is_integer() else Decimal(str(r[ix["AMOUNT"]]))
        g = str(r[ix["SR_GROUP_LONG_NAME"]])
        if r[ix["ECONOMIC_BUDGET_CODE"]] == "RESOURCE":
            out[(g, "RDEL")] += a
            if r[ix["ECONOMIC_RINGFENCE_CODE"]] != "RINGFENCED":
                out[(g, "RDEL_EX_DEPN")] += a
        elif r[ix["ECONOMIC_BUDGET_CODE"]] == "CAPITAL":
            out[(g, "CDEL")] += a
    return out


# ---------------------------------------------------------------- name mapping

# Authored aliases: plan-table name key -> (SR group long name in BUD, confidence, note). Keys are
# rp.name_key() of the cleaned name. Anything not here is matched on the key alone.
ALIASES: dict[str, tuple[str | None, str, str]] = {
    "health and social care": ("Health (NHS)", "high", "SR group for DHSC is called Health (NHS) in OSCAR"),
    "dluhc levelling up housing and communities": ("CLG Communities", "high", "DLUHC renamed MHCLG in 2024"),
    "mhclg housing communities and local government": ("CLG Communities", "high", ""),
    "mhclg housing and communities": ("CLG Communities", "high", ""),
    "levelling up housing and communities": ("CLG Communities", "medium", "PESA 2022-2023 label"),
    "dluhc local government": ("CLG Local Government", "high", ""),
    "mhclg local government": ("CLG Local Government", "high", ""),
    "dluhc housing and communities": ("CLG Communities", "high", ""),
    "housing communities and local government": ("CLG Communities", "medium", "check: may include local government"),
    "local government": ("CLG Local Government", "medium", ""),
    "scottish government": ("Scotland", "high", "devolved administration"),
    "welsh government": ("Wales", "high", "devolved administration"),
    "northern ireland executive": ("Northern Ireland", "high", "devolved administration"),
    "hm revenue and customs": ("HM Revenue & Customs", "high", ""),
    "law officers departments": ("Law Officer's Departments", "high", "apostrophe differs"),
    "single intelligence account": (None, "none", "SIA is excluded from OSCAR transparency data: no outturn"),
    "business energy and industrial strategy": (
        None,
        "low",
        "split in February 2023 into Energy Security and Net Zero, Science, Innovation and Technology "
        "and Business and Trade; no one-to-one current group",
    ),
    "digital culture media and sport": (
        "Culture, Media and Sport",
        "low",
        "digital functions moved to Science, Innovation and Technology in 2023",
    ),
    "international trade": ("Business and Trade", "low", "merged into Business and Trade in 2023"),
    "reserves": (None, "n/a", "not a department: unallocated reserve"),
    "obr allowance shortfall": (None, "n/a", "not a department"),
    "adjustment budget exchange": (None, "n/a", "not a department"),
    "scottish government block grant adjustments": (None, "n/a", "memo adjustment, not a department"),
    "unallocated": (None, "n/a", "not a department"),
    # parts of one group published on two lines (no parent line in the same table): add them up
    "transport excl high speed 2": ("Transport", "high", "part of Transport: add the HS2 line"),
    "transport high speed 2": ("Transport", "high", "part of Transport: add the line excluding HS2"),
    "transport high speed 27": ("Transport", "high", "part of Transport; footnote 7 is stuck to 'High Speed 2'"),
    "energy security and net zero excl sizewell c": (
        "Energy Security and Net Zero",
        "high",
        "part of the group: add the Sizewell C line",
    ),
    "energy security and net zero sizewell c": (
        "Energy Security and Net Zero",
        "high",
        "part of the group: add the line excluding Sizewell C",
    ),
}

# Lines inside department-group sections that are not departments (reserves, unallocated funds,
# accounting adjustments, memo lines). Keys as name_key() gives them, apostrophes removed.
NOT_DEPARTMENTS = {
    "accounting adjustments",
    "administration budgets as a percentage total managed expenditure",
    "budget measures not yet allocated to departments",
    "central government gross debt interest",
    "funding leases reclassification exercise ifrs16",
    "growth mission fund",
    "ifrs16 adjustments to be allocated",
    "levelling up fund",
    "locally financed expenditure",
    "net expenditure transfers to eu",
    "oda unallocated provision to hit 0 7 gni",
    "provision intra governmental ifrs16 leasing non fiscal",
    "provision intra governmental leases",
    "public corporations own financed capital expenditure",
    "public sector depreciation",
    "reform and innovation fund",
    "reserve excluding retained budget exchanges",
    "scape funding",
    "transformation fund",
    "uk shared prosperity fund",
    "capital del excl fts",
    "remove cdel financial transactions ft",
}


def map_name(clean: str, bud_names: list[str]) -> tuple[str | None, str, str]:
    key = rp.name_key(clean).replace("'", "")
    if key in ALIASES:
        return ALIASES[key]
    if key in NOT_DEPARTMENTS or key.startswith("memo "):
        return None, "n/a", "not a department: central or memo line"
    for b in bud_names:
        if rp.name_key(b).replace("'", "") == key:
            return b, "high", "same name" if b == clean else "same name after normalising"
    return None, "none", "no candidate"


def _keyclean(s: str) -> str:
    return rp.name_key(s).replace("'", "")


def name_map(est_records, pesa_records, pss_names, bud_file, bud_codes) -> list[list]:
    bud_names = sorted(bud_codes)
    seen: dict[tuple, dict] = {}

    def add(source, release, raw, clean):
        k = (source, clean)
        d = seen.setdefault(k, {"releases": set(), "raw": set()})
        d["releases"].add(release)
        d["raw"].add(raw)

    for r in est_records:
        add("Estimates", r["release"], r["raw"], r["name"])
    for r in pesa_records:
        add("SR25" if r["release"] == "sr2025" else "PESA", r["release"], r["raw"], r["name"])
    for n in pss_names:
        add("PSS 2026", "2026-07", n, n)
    for n in bud_names:
        add(f"BUD {bud_file}", "2025-11", n, n)
    rows = []
    for (source, clean), d in sorted(seen.items(), key=lambda x: (x[0][0], _keyclean(x[0][1]))):
        target, conf, note = map_name(clean, bud_names)
        rows.append(
            [
                source,
                ";".join(sorted(d["releases"])),
                " | ".join(sorted(d["raw"])),
                clean,
                bud_codes.get(target, "") if target else "",
                target or "",
                conf,
                note,
            ]
        )
    return rows


# ---------------------------------------------------------------- PSS

PSS_FILE = Path("pss") / "2026-07" / "PSS_Database_2026.xlsx"
PSS_INYEAR = {
    "2021-22": "2022-06",
    "2022-23": "2023-06",
    "2023-24": "2024-06",
    "2024-25": "2025-06",
    "2025-26": "2026-06",
}


def read_pss(path: Path) -> tuple[list[str], list[list]]:
    sheet = rp.read_workbook(path, only={"Database"})["Database"]
    header = [str(c) for c in sheet[0]]
    return header, sheet[1:]


def pss_profile(data_dir: Path, repo_root: Path):
    header, rows = read_pss(data_dir / PSS_FILE)
    ix = {c: i for i, c in enumerate(header)}
    tot: dict[tuple, list] = defaultdict(lambda: [0, Decimal(0)])
    grp: dict[tuple, Decimal] = defaultdict(Decimal)
    names = set()
    ringfences = set()
    bud_names = sorted(bud_sr_groups(data_dir)[1])
    mapped: dict[str, str] = {}
    for r in rows:
        y, eb, cbd = r[ix["Year"]], r[ix["Economic Budget Code"]], r[ix["Control Budget Detail Code"]]
        a = r[ix["Amount"]] or Decimal(0)
        tot[(y, cbd, eb)][0] += 1
        tot[(y, cbd, eb)][1] += a
        raw = r[ix["SR Group Long Name"]]
        names.add(raw)
        ringfences.add(r[ix["Economic Ringfence Code"]])
        if raw not in mapped:
            mapped[raw] = map_name(raw, bud_names)[0] or f"[{raw}]"
        g = mapped[raw]
        if cbd in ("DEL PROG", "DEL ADMIN"):
            grp[(y, g, "RDEL" if eb == "RESOURCE" else "CDEL")] += a
            if eb == "RESOURCE" and not str(r[ix["Economic Ringfence Code"]]).startswith("RINGFENCED"):
                grp[(y, g, "RDEL_EX_DEPN")] += a
    # against the June in-year release for the same year
    cmp_rows = []
    for y, rel in PSS_INYEAR.items():
        path = inyear_release_path(repo_root, rel)
        iy: dict[tuple, Decimal] = defaultdict(Decimal)
        iy_ex: dict[tuple, Decimal] = defaultdict(Decimal)
        if path is not None:
            for _org, _dept, cbd, eb, pg, _v, yy, _per, a in inyear_rows(path):
                if yy == y:
                    k = (cbd, "n/a" if eb in ("NA", "n/a") else eb)
                    iy[k] += a
                    if pg != "DEPRECIATION":
                        iy_ex[k] += a
        keys = {(c, e) for (yy, c, e) in tot if yy == y} | set(iy)
        for cbd, eb in sorted(keys):
            n, p = tot.get((y, cbd, eb), [0, Decimal(0)])
            i = iy.get((cbd, eb))
            ie = iy_ex.get((cbd, eb))
            cmp_rows.append(
                [
                    y,
                    cbd,
                    eb,
                    n,
                    p,
                    rel if path else "",
                    i,
                    (p - i) if i is not None else None,
                    pct(p - i, abs(i)) if i else None,
                    ie,
                    (p - ie) if ie is not None else None,
                    pct(p - ie, abs(ie)) if ie else None,
                ]
            )
    # against BUD by SR group, for the years the 2025-11 BUD files cover
    bud_rows = []
    for f in sorted((data_dir / BUD_DIR).glob("BUD_*.xlsx")):
        m = re.search(r"BUD_(\d\d)-(\d\d)", f.name)
        y = f"20{m.group(1)}-{m.group(2)}"
        if not any(k[0] == y for k in grp):
            continue
        b = bud_del_by_group(f)
        groups = sorted({k[1] for k in grp if k[0] == y} | {k[0] for k in b})
        for g in groups:
            for meas in ("RDEL", "RDEL_EX_DEPN", "CDEL"):
                p, q = grp.get((y, g, meas)), b.get((g, meas))
                if p is None and q is None:
                    continue
                bud_rows.append(
                    [y, g, meas, p, f.name, q, (p or 0) - (q or 0) if p is not None and q is not None else None]
                )
    return header, len(rows), cmp_rows, bud_rows, sorted(names), sorted(ringfences)


# ---------------------------------------------------------------- consistency check (Q13)


def consistency(est_records, pesa_records, best, data_dir: Path, year: str = "2023-24") -> list[list]:
    """One year, every department group: the final Estimates plan, the PESA plan published before the
    year, the PESA outturn published after it, and BUD outturn, all mapped to the SR group and in £000."""
    bud_names = sorted(bud_sr_groups(data_dir)[1])
    vals: dict[tuple, Decimal] = defaultdict(Decimal)
    labels = []

    def put(label, name, measure, v):
        target, _conf, _note = map_name(name, bud_names)
        vals[(label, target or f"[{name}]", measure)] += v

    rel = best.get(year)
    lab_e = f"Estimates {rel}"
    labels.append(lab_e)
    for r in est_records:
        if r["release"] == rel and r["year"] == year:
            put(lab_e, r["name"], r["measure"], r["gbp_k"])
    for prel, want in (("2023", "plans"), ("2024", "outturn")):
        lab = f"PESA {prel} ({want})"
        labels.append(lab)
        for r in pesa_records:
            if (
                r["release"] == prel
                and r["year"] == year
                and r["status"].startswith(want)
                and r["measure"] in ("RDEL", "RDEL_EX_DEPN", "CDEL")
            ):
                put(lab, r["name"], r["measure"], r["gbp_k"])
    bf = data_dir / BUD_DIR / f"BUD_{year[2:4]}-{year[5:7]}.xlsx"
    lab_b = f"BUD {bf.name} (outturn)"
    labels.append(lab_b)
    for (g, meas), v in bud_del_by_group(bf).items():
        vals[(lab_b, g, meas)] += v
    groups = sorted({k[1] for k in vals})
    rows = []
    for g in groups:
        for meas in ("RDEL", "RDEL_EX_DEPN", "CDEL"):
            line = [year, g, meas] + [vals.get((lab, g, meas)) for lab in labels]
            if any(v is not None for v in line[3:]):
                rows.append(line)
    for meas in ("RDEL", "RDEL_EX_DEPN", "CDEL"):
        rows.append(
            [year, "TOTAL (mapped groups)", meas]
            + [
                sum(
                    (v for (lab2, g, m), v in vals.items() if lab2 == lab and m == meas and not g.startswith("[")),
                    Decimal(0),
                )
                for lab in labels
            ]
        )
    return [["fiscal_year", "sr_group", "measure", *[f"{lab} gbp_thousand" for lab in labels]], *rows]


# ---------------------------------------------------------------- deflators

GDP_DIRS = ["2026-06-quarterly-national-accounts", "2026-09-quarterly-national-accounts", "2026-10-budget"]


def deflator_rows(data_dir: Path) -> tuple[list[list], list[dict]]:
    rows, summary = [], []
    for d in GDP_DIRS:
        f = next((data_dir / "gdp_deflator" / d).glob("*.xlsx"))
        g = rd.read_gdp_deflator(f)
        chained = rd.chained_index(g)
        summary.append(
            {
                "vintage": d,
                "file": f.name,
                "sheet": g.sheet,
                "base": g.base,
                "header_row": g.header_row + 1,
                "last_outturn": g.last_outturn,
                "first_forecast": g.first_forecast,
                "last_year": g.years[-1].year,
                "notes": g.notes,
            }
        )
        for y in g.years:
            rows.append(
                [
                    d,
                    f.name,
                    g.sheet,
                    g.base,
                    y.year,
                    "forecast" if y.forecast else "outturn",
                    y.index,
                    y.pct_change,
                    chained[y.year],
                    y.money_gdp_nsa,
                    y.row + 1,
                ]
            )
    return rows, summary


def cpi_summary(data_dir: Path) -> list[dict]:
    out = []
    for f in sorted((data_dir / "ons_cpi" / "latest").glob("*.csv")):
        s = rd.read_ons_series(f)
        out.append(
            {
                "file": f.name,
                "cdid": s.meta.get("CDID"),
                "title": s.meta.get("Title"),
                "release_date": s.meta.get("Release date"),
                "meta_lines": s.first_data_line - 1,
                "starts": s.block_starts,
                "annual": (s.annual[0][0], s.annual[-1][0], len(s.annual)),
                "quarterly": (s.quarterly[0][0], s.quarterly[-1][0], len(s.quarterly)),
                "monthly": (s.monthly[0][0], s.monthly[-1][0], len(s.monthly)),
                "latest": s.monthly[-1],
            }
        )
    return out


# ---------------------------------------------------------------- run


def run(repo_root: Path, data_dir: Path, log=print) -> dict:
    out = repo_root / PROFILE_DATA
    inv, names, best, est_records = estimates(data_dir)
    pinv, pesa_records = pesa(data_dir)
    bud_file, bud_codes, bud_groups = bud_sr_groups(data_dir)
    pss_header, pss_n, pss_cmp, pss_bud, pss_names, pss_ringfences = pss_profile(data_dir, repo_root)
    log(f"pss economic ringfence codes: {pss_ringfences}")
    cons = consistency(est_records, pesa_records, best, data_dir)
    drows, dsummary = deflator_rows(data_dir)
    outputs = [
        (
            out / "plan_estimates_inventory.csv",
            [
                "release",
                "file",
                "sheet",
                "measure",
                "title",
                "unit",
                "unit_row",
                "year_row",
                "status_row",
                "year",
                "status",
                "line_rows",
                "memo_rows",
                "memo_labels",
                "total_label",
                "total_published",
                "sum_of_lines",
                "sum_minus_total",
                "best_final_plan_for_year",
            ],
            inv,
        ),
        (
            out / "plan_estimates_names.csv",
            [
                "release",
                "file",
                "sheet",
                "measure",
                "year",
                "row",
                "raw_name",
                "clean_name",
                "kind",
                "value_as_published",
                "value_gbp_thousand",
            ],
            names,
        ),
        (
            out / "plan_pesa_inventory.csv",
            [
                "release",
                "file",
                "sheet",
                "table",
                "title",
                "unit",
                "year_row",
                "first_year",
                "last_year",
                "outturn_years",
                "plan_years",
                "section",
                "line_rows",
                "grain",
                "measure",
            ],
            pinv,
        ),
        (
            out / "plan_pesa_values.csv",
            ["release", "sheet", "measure", "year", "status", "raw_name", "clean_name", "value_gbp_thousand"],
            [
                [r["release"], r["sheet"], r["measure"], r["year"], r["status"], r["raw"], r["name"], r["gbp_k"]]
                for r in pesa_records
            ],
        ),
        (
            out / "plan_name_map_candidates.csv",
            [
                "source",
                "releases",
                "raw_names",
                "clean_name",
                "bud_sr_group_code",
                "bud_sr_group_long_name",
                "confidence",
                "note",
            ],
            name_map(est_records, pesa_records, pss_names, bud_file, bud_codes),
        ),
        (out / "plan_consistency_2023_24.csv", cons[0], cons[1:]),
        (
            out / "pss_vs_inyear.csv",
            [
                "fiscal_year",
                "control_budget_detail",
                "economic_budget",
                "pss_rows",
                "pss_gbp_thousand",
                "inyear_release",
                "inyear_gbp_thousand",
                "gap_gbp_thousand",
                "gap_pct",
                "inyear_excl_depreciation_gbp_thousand",
                "gap_excl_depreciation_gbp_thousand",
                "gap_excl_depreciation_pct",
            ],
            pss_cmp,
        ),
        (
            out / "pss_vs_bud_by_group.csv",
            [
                "fiscal_year",
                "sr_group",
                "measure",
                "pss_gbp_thousand",
                "bud_file",
                "bud_gbp_thousand",
                "gap_gbp_thousand",
            ],
            pss_bud,
        ),
        (
            repo_root / AUDIT / "pss_file_control_totals.csv",
            ["file", "sheet", "columns", "rows", "fiscal_year", "amount_total_gbp_thousand"],
            _pss_totals(pss_header, pss_n, pss_cmp),
        ),
        (
            out / "deflator_vintages.csv",
            [
                "vintage",
                "file",
                "sheet",
                "base",
                "fiscal_year",
                "status",
                "index_published",
                "pct_change",
                "index_chained",
                "money_gdp_nsa_gbp_million",
                "sheet_row",
            ],
            drows,
        ),
    ]
    for path, header, rows in outputs:
        n = write_csv(path, header, rows)
        log(f"wrote {path.relative_to(repo_root).as_posix()} ({n} rows)")
    log(f"best final plan per year: {best}")
    for s in dsummary:
        log(
            f"deflator {s['vintage']}: base {s['base']}, header row {s['header_row']}, outturn to "
            f"{s['last_outturn']}, forecast {s['first_forecast']} to {s['last_year']}"
        )
    for c in cpi_summary(data_dir):
        log(f"cpi {c}")
    return {"best": best, "bud_groups": bud_groups}


def _pss_totals(header, n, cmp_rows) -> list[list]:
    by: dict[str, Decimal] = defaultdict(Decimal)
    for y, _c, _e, _n, p, *_r in cmp_rows:
        by[y] += p
    return [[PSS_FILE.name, "Database", len(header), n, y, v] for y, v in sorted(by.items())]
