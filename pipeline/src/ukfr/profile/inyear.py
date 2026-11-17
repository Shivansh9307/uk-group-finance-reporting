"""`ukfr profile inyear`: profile the OSCAR in-year releases and the organisation codes in them.

Every output is regenerated from the committed files in one run and is deterministic: amounts are
summed as `Decimal` under a context that traps any rounding, rows are sorted, and nothing depends on
the clock or the machine. Outputs:

- `data/audit/inyear_file_control_totals.csv`: one row per in-year data file (the load control table)
- `data/audit/inyear_file_control_totals_by_budget.csv`: the same totals split by raw control budget
  and economic budget values
- `docs/profiling/data/inyear_*.csv`: header variants, value domains, time, grain, restatement,
  zero rows, signs, chart of accounts
- `docs/profiling/data/org_*.csv`: organisation code history, durable-key candidates,
  machinery-of-government events, BEIS sub-segment successor candidates
"""

from __future__ import annotations

import csv
import decimal
import re
import sys
import time
from collections import Counter, defaultdict
from collections.abc import Iterable, Sequence
from dataclasses import dataclass, field
from decimal import ROUND_HALF_UP, Decimal
from difflib import SequenceMatcher
from pathlib import Path

from ..readers.oscar_inyear import (
    AMOUNT_FORMS,
    HEADER_VARIANTS,
    InyearFile,
    InyearRow,
    ReadStats,
    list_inyear_files,
    parse_quarter,
    parse_year,
    read_inyear,
)

DOCS_DATA = Path("docs") / "profiling" / "data"
AUDIT = Path("data") / "audit"

ZERO = Decimal(0)
Q4 = Decimal("0.0001")
EXACT = decimal.Context(prec=200, traps=[decimal.Inexact, decimal.InvalidOperation, decimal.Overflow])
ROUNDING = decimal.Context(prec=200)  # only for the deliberate rounding to four places

# Expected year-to-date window of a release, by its month: last period present.
EXPECTED_LAST_PERIOD = {"09": 3, "12": 6, "03": 9, "06": 12}

CB_NORMAL = {"DEL": "DEL", "TOTAL DEL": "DEL", "AME": "AME", "TOTAL AME": "AME",
             "NON-BUDGET": "NON-BUDGET", "TOTAL NON-BUDGET": "NON-BUDGET"}  # fmt: skip
EB_NORMAL = {"RESOURCE": "RESOURCE", "CAPITAL": "CAPITAL", "NA": "N/A", "n/a": "N/A",
             "OTHER NON-BUDGET": "OTHER NON-BUDGET"}  # fmt: skip
FORM_NAMES = [name for name, _ in AMOUNT_FORMS] + ["blank"]

BEIS = "DEPARTMENT FOR BUSINESS ENERGY AND INDUSTRIAL STRATEGY"


# ----------------------------------------------------------------------------------------- helpers


def fmt(v) -> str:
    if v is None:
        return ""
    if isinstance(v, Decimal):
        s = format(v, "f")
        return "0" if s in ("-0", "0E-0") else s
    if isinstance(v, bool):
        return "Y" if v else "N"
    if isinstance(v, float):  # only ratios reach here; amounts are always Decimal
        return f"{v:.4f}"
    return str(v)


def write_csv(path: Path, columns: Sequence[str], rows: Iterable[Sequence]) -> int:
    path.parent.mkdir(parents=True, exist_ok=True)
    n = 0
    with open(path, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(columns)
        for r in rows:
            if len(r) != len(columns):
                raise ValueError(f"{path.name}: row has {len(r)} values, header has {len(columns)}")
            w.writerow([fmt(v) for v in r])
            n += 1
    return n


def core_name(s: str) -> str:
    """norm_name without upper-case bracketed tags: 'Ofcom (DCM048.GROUP)' and 'OFCOM (DCMS)' compare equal.

    Mixed-case brackets stay, because they can tell bodies apart: '(GenCo)' and '(HoldCo)'.
    """
    return norm_name(re.sub(r"\([A-Z0-9.]{2,}\)", " ", s))


def norm_name(s: str) -> str:
    """Upper case, '&' -> AND, punctuation dropped, spaces collapsed: for comparing names only."""
    s = s.upper().replace("&", " AND ")
    s = re.sub(r"[^A-Z0-9 ]+", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def strip_subsegment_code(name: str, code: str) -> str:
    """'X084A160-ACAS DEL ADMIN VOTED' -> 'ACAS DEL ADMIN VOTED'."""
    if name.upper().startswith(code.upper()):
        name = name[len(code) :].lstrip(" -")
    return name


def similarity(a: str, b: str) -> float:
    return SequenceMatcher(None, a, b).ratio()


def split_code(code: str) -> tuple[str, str]:
    m = re.match(r"^([A-Z]+)(\d+)$", code)
    return (m.group(1), m.group(2)) if m else (code, "")


def initials(name: str) -> str:
    words = [w for w in norm_name(name).split() if w not in ("AND", "FOR", "OF", "THE", "ON", "IN")]
    return "".join(w[0] for w in words)[:8]


def release_fy(release: str) -> str:
    """'2022-09' -> '2022-23'; '2023-06' -> '2022-23' (June releases close the previous year)."""
    y, m = int(release[:4]), release[5:7]
    start = y if m in ("09", "12") else y - 1
    return f"{start}-{(start + 1) % 100:02d}"


def q4(v: Decimal) -> Decimal:
    """Round to four decimal places, half away from zero (what DECIMAL(19,4) storage will hold)."""
    return v.quantize(Q4, rounding=ROUND_HALF_UP, context=ROUNDING)


def pct(a, b) -> float | str:
    return "" if not b else float(a) / float(b)


# ----------------------------------------------------------------------------------------- per file


@dataclass
class FileProfile:
    f: InyearFile
    primary: bool
    stats: ReadStats
    seconds: float = 0.0
    versions: Counter = field(default_factory=Counter)
    fys: Counter = field(default_factory=Counter)
    periods: Counter = field(default_factory=Counter)
    orgs: set = field(default_factory=set)
    depts: set = field(default_factory=set)
    subsegs: set = field(default_factory=set)
    econcats: set = field(default_factory=set)
    zero_rows: int = 0
    fraction_rows: int = 0
    over_4dp_rows: int = 0
    total: Decimal = ZERO
    total_q4: Decimal = ZERO
    by_cb: dict = field(default_factory=lambda: defaultdict(lambda: [0, ZERO]))
    by_eb: dict = field(default_factory=lambda: defaultdict(lambda: [0, ZERO]))
    by_cb_norm: dict = field(default_factory=lambda: defaultdict(lambda: ZERO))
    by_eb_norm: dict = field(default_factory=lambda: defaultdict(lambda: ZERO))
    row_digest: Counter = field(default_factory=Counter)  # only kept for files compared with a twin


def key_plan(r: InyearRow) -> tuple:
    return (r.organisation_code, r.sub_segment_code, r.economic_category_code, r.control_budget_detail_code, r.month)


def key_seg(r: InyearRow) -> tuple:
    return (r.sub_segment_code, r.economic_category_code, r.month)


def key_org_seg(r: InyearRow) -> tuple:
    return (r.organisation_code, r.sub_segment_code, r.economic_category_code, r.month)


def key_k0(r: InyearRow) -> tuple:
    return (r.organisation_code, r.control_budget_detail_code, r.sub_segment_code, r.economic_category_code,
            r.economic_budget_code, r.month)  # fmt: skip


def key_k1(r: InyearRow) -> tuple:
    return key_k0(r) + (r.control_budget_code,)


def key_k2(r: InyearRow) -> tuple:
    return key_k1(r) + (r.pesa_economic_group_code,)


def attrs(r: InyearRow) -> tuple:
    """Every non-amount column."""
    return tuple(r[2:18])


KEYS = (
    ("K_seg: sub-segment, econ category, month", key_seg),
    ("K_org_seg: org, sub-segment, econ category, month", key_org_seg),
    ("K_plan: org, sub-segment, econ category, control budget detail, month", key_plan),
    ("K0: K_plan + economic budget", key_k0),
    ("K1: K0 + control budget code", key_k1),
    ("K2: K1 + PESA economic group", key_k2),
    ("K_all: every non-amount column", attrs),
)


def profile_file(f: InyearFile, root: Path, primary: bool, keep_digest: bool) -> tuple[FileProfile, list[InyearRow]]:
    t0 = time.perf_counter()
    stats = ReadStats()
    p = FileProfile(f, primary, stats)
    rows = []
    for r in read_inyear(f, root, stats):
        rows.append(r)
        a = r.amount if r.amount is not None else ZERO
        p.versions[r.version] += 1
        p.fys[r.financial_year or f"(year {r.year})"] += 1
        p.periods[r.period] += 1
        p.orgs.add(r.organisation_code)
        p.depts.add(r.department_name)
        p.subsegs.add(r.sub_segment_code)
        p.econcats.add(r.economic_category_code)
        if a == 0:
            p.zero_rows += 1
        if a != a.to_integral_value():
            p.fraction_rows += 1
            if a != q4(a):
                p.over_4dp_rows += 1
        p.total += a
        p.total_q4 += q4(a)
        p.by_cb[r.control_budget_code][0] += 1
        p.by_cb[r.control_budget_code][1] += a
        p.by_eb[r.economic_budget_code][0] += 1
        p.by_eb[r.economic_budget_code][1] += a
        p.by_cb_norm[CB_NORMAL.get(r.control_budget_code, "OTHER")] += a
        p.by_eb_norm[EB_NORMAL.get(r.economic_budget_code, "OTHER")] += a
        if keep_digest:
            p.row_digest[attrs(r) + (r.amount_text,)] += 1
    p.seconds = time.perf_counter() - t0
    return p, rows


CONTROL_COLUMNS = (
    "release", "filename", "member", "container", "primary_for_release", "sha256", "header_variant", "sheet",
    "encoding", "high_bytes", "high_byte_values", "valid_utf8", "line_ending", "physical_lines",
    "line_breaks_in_fields",
    "total_rows", "blank_rows", "blank_rows_trailing", "data_rows", "stripped_fields", "versions", "financial_years",
    "periods", "n_organisations", "n_departments", "n_sub_segments", "n_economic_categories",
    "amount_cell_type", *[f"amount_form_{n}" for n in FORM_NAMES], "zero_rows", "fraction_rows", "over_4dp_rows",
    "amount_sum", "amount_sum_rounded_4dp", "amount_del", "amount_ame", "amount_non_budget", "amount_cb_other",
    "amount_resource", "amount_capital", "amount_eb_na", "amount_eb_other_non_budget", "amount_eb_other",
)  # fmt: skip


def control_row(p: FileProfile) -> list:
    s, f = p.stats, p.f
    forms = Counter()
    for k, v in s.amount_forms.items():
        forms[re.sub(r"^ods_[a-z]+_", "", k)] += v
    unknown = set(forms) - set(FORM_NAMES)
    if unknown:
        raise ValueError(f"{f.filename}: amount forms without a column: {unknown}")
    is_ods = f.container.endswith("ods")
    periods = sorted(p.periods)
    return [
        f.release, f.filename, f.member, f.container, p.primary, f.sha256, s.header_variant, s.sheet,
        "ods (xml, utf-8)" if is_ods else "cp1252",
        "" if is_ods else s.high_bytes, s.high_byte_values, "" if is_ods else s.utf8_valid,
        s.line_ending, "" if is_ods else s.physical_lines, "" if is_ods else s.bare_lf,
        s.total_rows, s.blank_rows, s.blank_rows_trailing, s.data_rows, s.stripped_fields,
        " ".join(sorted(p.versions)), " ".join(sorted(p.fys)), " ".join(str(x) for x in periods),
        len(p.orgs), len(p.depts), len(p.subsegs), len(p.econcats),
        "ods float cell" if is_ods else "csv text", *[forms.get(n, 0) for n in FORM_NAMES],
        p.zero_rows, p.fraction_rows, p.over_4dp_rows, p.total, p.total_q4,
        p.by_cb_norm.get("DEL", ZERO), p.by_cb_norm.get("AME", ZERO), p.by_cb_norm.get("NON-BUDGET", ZERO),
        p.by_cb_norm.get("OTHER", ZERO), p.by_eb_norm.get("RESOURCE", ZERO), p.by_eb_norm.get("CAPITAL", ZERO),
        p.by_eb_norm.get("N/A", ZERO), p.by_eb_norm.get("OTHER NON-BUDGET", ZERO), p.by_eb_norm.get("OTHER", ZERO),
    ]  # fmt: skip


# ----------------------------------------------------------------------------------------- analyses


@dataclass
class Collect:
    """Cross-release accumulators (small: distinct values, not rows)."""

    domains: dict = field(default_factory=lambda: defaultdict(lambda: [set(), 0]))  # (col, value) -> releases, rows
    time: dict = field(default_factory=lambda: defaultdict(lambda: [0, ZERO]))  # (release, year, q, month)
    accounts: dict = field(default_factory=lambda: defaultdict(lambda: [set(), 0]))
    signs: dict = field(default_factory=lambda: defaultdict(lambda: [0, 0, 0, ZERO, ZERO, set()]))
    org_hist: dict = field(default_factory=lambda: defaultdict(lambda: [set(), 0, {}]))
    # per release: org code -> {dept: amount}, sub-segment info
    org_dept: dict = field(default_factory=dict)
    org_name: dict = field(default_factory=dict)
    subseg: dict = field(default_factory=dict)  # release -> code -> [name, {(org, dept)}, amount]
    within_mix: list = field(default_factory=list)
    grain: list = field(default_factory=list)
    dup_examples: list = field(default_factory=list)
    zero: list = field(default_factory=list)
    windows: list = field(default_factory=list)


DOMAIN_COLUMNS = ("control_budget_code", "control_budget_detail_code", "economic_budget_code",
                  "pesa_economic_group_code", "pesa_economic_group_name", "version")  # fmt: skip


def collect_release(c: Collect, p: FileProfile, rows: list[InyearRow], final_for_fy: bool) -> None:
    rel = p.f.release
    org_dept: dict[str, dict[str, Decimal]] = defaultdict(lambda: defaultdict(lambda: ZERO))
    org_name: dict[str, set] = defaultdict(set)
    subseg: dict[str, list] = {}
    mix_org: dict[str, dict[str, set]] = defaultdict(lambda: defaultdict(set))
    for r in rows:
        a = r.amount if r.amount is not None else ZERO
        for col in DOMAIN_COLUMNS:
            d = c.domains[(col, getattr(r, col))]
            d[0].add(rel)
            d[1] += 1
        d = c.domains[("control_budget_code + control_budget_detail_code",
                       f"{r.control_budget_code} | {r.control_budget_detail_code}")]  # fmt: skip
        d[0].add(rel)
        d[1] += 1
        t = c.time[(rel, r.year, r.quarter, r.month, r.financial_year, r.period)]
        t[0] += 1
        t[1] += a
        acc = c.accounts[(r.economic_category_code, r.economic_category_name, r.pesa_economic_group_code,
                          r.pesa_economic_group_name, r.economic_budget_code)]  # fmt: skip
        acc[0].add(rel)
        acc[1] += 1
        if final_for_fy:
            s = c.signs[(r.pesa_economic_group_code, r.economic_category_code)]
            if a > 0:
                s[0] += 1
                s[3] += a
            elif a < 0:
                s[1] += 1
                s[4] += a
            else:
                s[2] += 1
            s[5].add(r.economic_category_name)
        h = c.org_hist[(r.organisation_code, r.organisation_name, r.department_name)]
        h[0].add(rel)
        h[1] += 1
        h[2][rel] = h[2].get(rel, ZERO) + a
        org_dept[r.organisation_code][norm_name(r.department_name)] += a
        org_name[r.organisation_code].add(r.organisation_name)
        ss = subseg.setdefault(r.sub_segment_code, [r.sub_segment_name, set(), ZERO])
        ss[1].add((r.organisation_code, norm_name(r.department_name)))
        ss[2] += a
        mix_org[r.organisation_code][norm_name(r.department_name)].add(r.period)
    c.org_dept[rel] = {k: dict(v) for k, v in org_dept.items()}
    c.org_name[rel] = {k: sorted(v) for k, v in org_name.items()}
    c.subseg[rel] = subseg
    for org, by_dept in mix_org.items():
        if len(by_dept) > 1:
            c.within_mix.append((rel, org, " | ".join(f"{d}: periods {min(ps)}-{max(ps)}"
                                                      for d, ps in sorted(by_dept.items()))))  # fmt: skip


def grain_release(c: Collect, rel: str, rows: list[InyearRow]) -> None:
    n = len(rows)
    for name, fn in KEYS:
        groups: dict[tuple, list[InyearRow]] = defaultdict(list)
        for r in rows:
            groups[fn(r)].append(r)
        dups = {k: g for k, g in groups.items() if len(g) > 1}
        exact = same_attrs = other = 0
        for g in dups.values():
            if len({attrs(r) + (r.amount_text,) for r in g}) == 1:
                exact += 1
            elif len({attrs(r) for r in g}) == 1:
                same_attrs += 1
            else:
                other += 1
        dup_rows = sum(len(g) for g in dups.values())
        dup_abs = sum((abs(r.amount or ZERO) for g in dups.values() for r in g), ZERO)
        c.grain.append((rel, n, name, len(groups), len(dups), dup_rows, exact, same_attrs, other, dup_abs))
        if name.startswith("K_plan") and dups:
            for k in sorted(dups)[:3]:
                for r in dups[k]:
                    c.dup_examples.append((rel, name.split(":")[0], r.line, *attrs(r), r.amount_text))


def zero_release(c: Collect, rel: str, rows: list[InyearRow]) -> None:
    lines = {key_plan(r)[:-1] for r in rows}
    months = {r.month for r in rows}
    zero = sum(1 for r in rows if not r.amount)
    nz_lines = {key_plan(r)[:-1] for r in rows if r.amount}
    c.zero.append((rel, len(rows), zero, pct(zero, len(rows)), len(lines), len(months),
                   pct(len(rows), len(lines) * len(months)), len(lines) - len(nz_lines)))  # fmt: skip


def window_release(c: Collect, p: FileProfile) -> None:
    rel = p.f.release
    exp_fy = release_fy(rel)
    exp_last = EXPECTED_LAST_PERIOD[rel[5:7]]
    months = sorted(x for x in p.periods if x)
    non_month = p.periods.get(0, 0)
    fys = sorted(x for x in p.fys)
    ok = fys == [exp_fy] and months == list(range(1, exp_last + 1))
    c.windows.append((rel, p.f.filename, exp_fy, f"1-{exp_last}", " ".join(fys),
                      " ".join(str(m) for m in months), non_month, "Y" if ok else "N"))  # fmt: skip


# ------------------------------------------------------------------------------------- restatement


@dataclass
class Restate:
    pairs: list = field(default_factory=list)
    by_month: list = field(default_factory=list)
    examples: list = field(default_factory=list)
    delta: list = field(default_factory=list)


def amounts_by_key(rows: list[InyearRow]) -> dict[tuple, Decimal]:
    out: dict[tuple, Decimal] = defaultdict(lambda: ZERO)
    for r in rows:
        out[key_plan(r)] += r.amount if r.amount is not None else ZERO
    return dict(out)


def restate_fy(res: Restate, fy: str, series: list[tuple[str, dict[tuple, Decimal], dict[tuple, int]]]) -> None:
    """series: [(release, key -> amount, key -> period)] in release order for one financial year."""
    prev_amounts: dict[tuple, Decimal] = {}
    periods_prev: dict[tuple, int] = {}
    prev_rel = ""
    for i, (rel, amounts, periods) in enumerate(series):
        stacked = len(amounts)
        first = changed = vanished = 0
        first_nz = changed_nz = vanished_nz = 0
        for k, a in amounts.items():
            if k not in prev_amounts:
                first += 1
                first_nz += a != 0
            elif prev_amounts[k] != a:
                changed += 1
                changed_nz += 1
        for k, a in prev_amounts.items():
            if k not in amounts:
                vanished += 1
                vanished_nz += a != 0
        res.delta.append((fy, rel, i, stacked, first, changed, vanished, first + changed + vanished,
                          first_nz + changed_nz + vanished_nz))  # fmt: skip
        if i:
            window = {periods_prev[k] for k in prev_amounts}
            by_period: dict[int, list] = defaultdict(lambda: [0, 0, 0, 0, ZERO, ZERO, ZERO, ZERO])
            moves = []
            for k in set(prev_amounts) | {k for k in amounts if periods[k] in window}:
                per = periods.get(k, periods_prev.get(k))
                b = by_period[per]
                before, after = prev_amounts.get(k), amounts.get(k)
                b[6] += before or ZERO
                b[7] += after or ZERO
                if before is None:
                    b[2] += 1
                elif after is None:
                    b[1] += 1
                elif before == after:
                    b[3] += 1
                    continue
                else:
                    b[0] += 1
                d = (after or ZERO) - (before or ZERO)
                if d:
                    b[4] += abs(d)
                    b[5] += d
                    moves.append((abs(d), k, before, after))
            tot = [sum(b[j] for b in by_period.values()) for j in range(4)]
            tot += [sum((b[j] for b in by_period.values()), ZERO) for j in range(4, 8)]
            res.pairs.append((fy, prev_rel, rel, len(window), *tot))
            for per in sorted(by_period):
                b = by_period[per]
                res.by_month.append((fy, prev_rel, rel, per, *b))
            moves.sort(key=lambda m: (-m[0], m[1]))
            for _abs, k, before, after in moves[:3]:
                res.examples.append((fy, prev_rel, rel, *k, before, after, (after or ZERO) - (before or ZERO)))
        prev_amounts, prev_rel, periods_prev = amounts, rel, periods


# --------------------------------------------------------------------------------- organisations


def org_outputs(c: Collect, releases: list[str], out: Path) -> dict:
    facts: dict = {}
    # 10. code history
    hist_rows = []
    for (code, name, dept), (rels, n, amt) in c.org_hist.items():
        rs = sorted(rels)
        hist_rows.append((code, *split_code(code), name, dept, rs[0], rs[-1], len(rs), n, amt.get(rs[-1], ZERO)))
    hist_rows.sort()
    write_csv(out / "org_code_history.csv",
              ("organisation_code", "prefix", "suffix", "organisation_name", "department_name", "first_release",
               "last_release", "n_releases", "rows", "amount_in_last_release"), hist_rows)  # fmt: skip

    # presence: code -> release -> (names, depts)
    presence: dict[str, dict[str, tuple]] = defaultdict(dict)
    for rel in releases:
        for code, depts in c.org_dept[rel].items():
            presence[code][rel] = (tuple(c.org_name[rel][code]), tuple(sorted(depts)), sum(depts.values(), ZERO))

    cands = []
    # (a) collisions: same prefix, different codes in the same release
    by_prefix_rel: dict[tuple, set] = defaultdict(set)
    for code, rels in presence.items():
        for rel in rels:
            by_prefix_rel[(split_code(code)[0], rel)].add(code)
    collisions: dict[tuple, list] = defaultdict(list)
    for (prefix, rel), codes in by_prefix_rel.items():
        if len(codes) > 1:
            collisions[(prefix, tuple(sorted(codes)))].append(rel)
    for (prefix, codes), rels in sorted(collisions.items()):
        rels.sort()
        names = {code: sorted({n for r in rels for n in presence[code][r][0]}) for code in codes}
        depts = {code: sorted({d for r in rels for d in presence[code][r][1]}) for code in codes}
        same_body = len({norm_name(n) for ns in names.values() for n in ns}) == 1
        for code in codes:
            cands.append(("a_prefix_collision", code, prefix, " / ".join(names[code]), " / ".join(depts[code]),
                          rels[0], rels[-1], len(rels),
                          code if not same_body else prefix,
                          f"prefix {prefix} held at once by {', '.join(codes)} in {len(rels)} release(s): "
                          + "; ".join(f"{k}={' / '.join(v)}" for k, v in names.items()),
                          "high" if not same_body else "medium"))  # fmt: skip

    # (b) same body, different prefix: identical or near-identical normalised names
    by_name: dict[str, set] = defaultdict(set)
    for code, rels in presence.items():
        for names, _d, _a in rels.values():
            for n in names:
                by_name[core_name(n)].add(code)
    seen_pairs = set()
    name_keys = sorted(by_name)
    for nm in name_keys:
        codes = sorted(by_name[nm])
        prefixes = {split_code(x)[0] for x in codes}
        if len(prefixes) > 1:
            seen_pairs.add(tuple(codes))
            _add_prefix_change(
                cands, presence, codes, f"identical name '{nm}' (upper-case bracketed tags ignored)", "high"
            )
    # near-identical names across different prefixes, codes not overlapping in time
    first_last = {code: (min(r), max(r)) for code, r in presence.items()}
    names_of = {code: sorted({core_name(n) for v in r.values() for n in v[0]}) for code, r in presence.items()}
    codes_all = sorted(presence)
    for i, a in enumerate(codes_all):
        for b in codes_all[i + 1 :]:
            if split_code(a)[0] == split_code(b)[0] or tuple(sorted((a, b))) in seen_pairs:
                continue
            best = 0.0
            for x in names_of[a]:
                for y in names_of[b]:
                    sm = SequenceMatcher(None, x, y)
                    if sm.real_quick_ratio() >= 0.9 and sm.quick_ratio() >= 0.9:
                        best = max(best, sm.ratio())
            if best >= 0.9:
                overlap = not (first_last[a][1] < first_last[b][0] or first_last[b][1] < first_last[a][0])
                _add_prefix_change(cands, presence, [a, b], f"near-identical names (similarity {best:.2f})"
                                   + ("; both present in the same release" if overlap else ""),
                                   "low" if overlap else "medium")  # fmt: skip

    # (c) code reused for a different body, (d) name change under one code.
    # The core organisation of a department in a release is the one whose name is closest to the
    # department's name. A core code whose name changes to a dissimilar name while its department
    # changes too is a code reused for a different body (a new department taking the old code).
    core_of: dict[str, set] = defaultdict(set)  # release -> core codes
    for rel in releases:
        best: dict[str, tuple] = {}
        for code, depts in c.org_dept[rel].items():
            for dept in depts:
                s = max(similarity(norm_name(n), dept) for n in c.org_name[rel][code])
                if dept not in best or (s, code) > best[dept]:
                    best[dept] = (s, code)
        core_of[rel] = {code for s, code in best.values() if s >= 0.5}
    dept_names = {d for rel in releases for v in c.org_dept[rel].values() for d in v}
    for code in codes_all:
        rels = presence[code]
        timeline = []  # runs of the same normalised name: [name, first, last, raw names, depts]
        for rel in sorted(rels):
            nm = " / ".join(sorted({norm_name(n) for n in rels[rel][0]}))
            if not timeline or timeline[-1][0] != nm:
                timeline.append([nm, rel, rel, rels[rel][0], rels[rel][1]])
            else:
                timeline[-1][2] = rel
                timeline[-1][4] = tuple(sorted(set(timeline[-1][4]) | set(rels[rel][1])))
        if len(timeline) < 2:
            continue
        runs_per_name = Counter(t[0] for t in timeline)
        prefix = split_code(code)[0]
        for prev, nxt in zip(timeline, timeline[1:], strict=False):
            sim = similarity(prev[0], nxt[0])
            contained = prev[0] in nxt[0] or nxt[0] in prev[0]
            evidence = (
                f"{code}: '{' / '.join(prev[3])}' ({' / '.join(prev[4])}) {prev[1]}..{prev[2]} -> "
                f"'{' / '.join(nxt[3])}' ({' / '.join(nxt[4])}) {nxt[1]}..{nxt[2]}; name similarity {sim:.2f}"
            )
            n_rel = _count_between(rels, prev[1], nxt[2])
            if runs_per_name[prev[0]] > 1 and runs_per_name[nxt[0]] > 1:
                cands.append(
                    (
                        "d_name_alternates",
                        code,
                        prefix,
                        " / ".join(nxt[3]),
                        " / ".join(nxt[4]),
                        prev[1],
                        nxt[2],
                        n_rel,
                        prefix,
                        evidence + "; both names recur, so they are aliases",
                        "high",
                    )
                )
                continue
            is_core = code in core_of[prev[2]]
            new_is_dept = any(similarity(nxt[0], d) >= 0.85 for d in dept_names)
            abbrev = is_abbreviation(prev[0], nxt[0])
            tsim = token_similarity(prev[0], nxt[0])
            if is_core and new_is_dept and tsim < 0.5 and not abbrev:
                siblings = sum(1 for o, ds in c.org_dept[prev[2]].items() if set(ds) & set(prev[4]))
                for run in (prev, nxt):
                    cands.append(("c_code_reused", code, prefix, " / ".join(run[3]), " / ".join(run[4]), run[1],
                                  run[2], _count_between(rels, run[1], run[2]), f"{prefix}.{initials(run[0])}",
                                  evidence + f"; token similarity {tsim:.2f}; core organisation of its department "
                                  f"({siblings} organisation(s) in it), new name is a department's name",
                                  "high" if siblings > 1 else "medium"))  # fmt: skip
                continue
            conf = "high" if sim >= 0.8 or contained or abbrev else "medium"
            why = "; abbreviation" if abbrev else ("" if conf == "high" else "; rename within the same department")
            cands.append(("d_name_change", code, prefix, " / ".join(nxt[3]), " / ".join(nxt[4]), prev[1], nxt[2],
                          n_rel, prefix, evidence + why, conf))  # fmt: skip
    # (b0) the durable case: the prefix survives while the department number changes;
    # (e) codes that stop being reported, with no later code under the same prefix.
    # "Retired" means absent from the last four releases, i.e. a whole year of releases.
    recent = set(releases[-4:])
    retired_numbers = {split_code(x)[1] for x in presence} - {
        split_code(x)[1] for x, r in presence.items() if recent & set(r)
    }
    by_prefix: dict[str, list[str]] = defaultdict(list)
    for code in codes_all:
        by_prefix[split_code(code)[0]].append(code)
    for prefix, codes in sorted(by_prefix.items()):
        codes = sorted(codes, key=lambda x: (min(presence[x]), x))
        for a, b in zip(codes, codes[1:], strict=False):
            if max(presence[a]) < min(presence[b]):
                na = sorted({n for v in presence[a].values() for n in v[0]})
                nb = sorted({n for v in presence[b].values() for n in v[0]})
                same = bool({norm_name(n) for n in na} & {norm_name(n) for n in nb})
                da = sorted({d for v in presence[a].values() for d in v[1]})
                db = sorted({d for v in presence[b].values() for d in v[1]})
                for x, names, depts in ((a, na, da), (b, nb, db)):
                    cands.append(("b0_suffix_change", x, prefix, " / ".join(names), " / ".join(depts),
                                  min(presence[x]), max(presence[x]), len(presence[x]), prefix,
                                  f"{a} last seen {max(presence[a])} ({' / '.join(da)}); {b} first seen "
                                  f"{min(presence[b])} ({' / '.join(db)}); "
                                  + ("same name" if same else "names differ: " + " | ".join(na + nb)),
                                  "high" if same else "medium"))  # fmt: skip
        last = codes[-1]
        if not recent & set(presence[last]):
            sfx = split_code(last)[1]
            names = sorted({n for v in presence[last].values() for n in v[0]})
            depts = sorted({d for v in presence[last].values() for d in v[1]})
            retired = sfx in retired_numbers
            cands.append(("e_code_retired", last, prefix, " / ".join(names), " / ".join(depts), min(presence[last]),
                          max(presence[last]), len(presence[last]), prefix,
                          f"last seen {max(presence[last])}; no later code with prefix {prefix}"
                          + (f"; department number {sfx} is not reported after it either (merger or closure: check)"
                             if retired else ""),
                          "low" if retired else "high"))  # fmt: skip
    cands = sorted(set(cands), key=lambda r: (r[0], r[2], r[1], r[5], r))  # full row breaks ties: sets are unordered
    write_csv(out / "org_durable_key_candidates.csv",
              ("finding", "organisation_code", "prefix", "organisation_name", "department_name", "first_release",
               "last_release", "n_releases", "proposed_durable_id", "evidence", "confidence"), cands)  # fmt: skip
    facts["candidates"] = Counter(r[0] for r in cands)
    facts["n_codes"] = len(presence)
    facts["n_prefixes"] = len({split_code(x)[0] for x in presence})

    # Department numbers: the three-digit suffix against the department names it appears under.
    suffix_dept: dict[str, dict[str, set]] = defaultdict(lambda: defaultdict(set))
    dept_suffix: dict[str, dict[str, set]] = defaultdict(lambda: defaultdict(set))
    suffix_codes: dict[str, set] = defaultdict(set)
    for rel in releases:
        for code, depts in c.org_dept[rel].items():
            sfx = split_code(code)[1]
            suffix_codes[sfx].add(code)
            for d in depts:
                suffix_dept[sfx][d].add(rel)
                dept_suffix[d][sfx].add(rel)
    srows = []
    for sfx in sorted(suffix_dept):
        allrel = sorted(set().union(*suffix_dept[sfx].values()))
        several = sum(1 for r in allrel if sum(1 for v in suffix_dept[sfx].values() if r in v) > 1)
        names = "; ".join(f"{d} ({min(v)}..{max(v)}, {len(v)})" for d, v in
                          sorted(suffix_dept[sfx].items(), key=lambda kv: (min(kv[1]), kv[0])))  # fmt: skip
        srows.append((sfx, allrel[0], allrel[-1], len(allrel), len(suffix_codes[sfx]), several, names))
    write_csv(out / "org_department_numbers.csv",
              ("department_number", "first_release", "last_release", "n_releases", "n_organisation_codes",
               "releases_with_several_department_names", "department_names"), srows)  # fmt: skip
    drows = []
    for d in sorted(dept_suffix):
        allrel = sorted(set().union(*dept_suffix[d].values()))
        several = sum(1 for r in allrel if sum(1 for v in dept_suffix[d].values() if r in v) > 1)
        nums = "; ".join(f"{s} ({min(v)}..{max(v)}, {len(v)})" for s, v in sorted(dept_suffix[d].items()))
        drows.append((d, allrel[0], allrel[-1], len(allrel), len(dept_suffix[d]), several, nums))
    write_csv(out / "org_department_name_numbers.csv",
              ("department_name_normalised", "first_release", "last_release", "n_releases", "n_department_numbers",
               "releases_with_several_numbers", "department_numbers"), drows)  # fmt: skip
    return facts


GENERIC = {"DEPARTMENT", "MINISTRY", "FOR", "OF", "AND", "THE", "ON", "IN"}


def token_similarity(a: str, b: str) -> float:
    """Jaccard similarity of the distinctive words of two normalised names."""
    ta, tb = set(a.split()) - GENERIC, set(b.split()) - GENERIC
    return len(ta & tb) / len(ta | tb) if ta | tb else 1.0


def is_abbreviation(a: str, b: str) -> bool:
    """True if one normalised name is the initials of the other (all words, or without small words)."""
    short, long_ = sorted((a.replace(" NET", ""), b.replace(" NET", "")), key=len)
    short = short.replace(" ", "")
    words = long_.split()
    every = "".join(w[0] for w in words)
    significant = "".join(w[0] for w in words if w not in ("AND", "FOR", "OF", "THE", "ON", "IN"))
    return len(short) >= 2 and (short in (every, significant) or every.startswith(short)
                                or significant.startswith(short))  # fmt: skip


def _count_between(rels: dict, a: str, b: str) -> int:
    return sum(1 for r in rels if a <= r <= b)


def _add_prefix_change(cands: list, presence: dict, codes: list[str], why: str, confidence: str) -> None:
    ordered = sorted(codes, key=lambda x: (min(presence[x]), x))
    durable = split_code(ordered[0])[0]
    trail = "; ".join(
        f"{x} {min(presence[x])}..{max(presence[x])} "
        f"({' / '.join(sorted({d for v in presence[x].values() for d in v[1]}))})"
        for x in ordered
    )
    for x in ordered:
        rels = presence[x]
        names = sorted({n for v in rels.values() for n in v[0]})
        depts = sorted({d for v in rels.values() for d in v[1]})
        cands.append(("b_prefix_change", x, split_code(x)[0], " / ".join(names), " / ".join(depts), min(rels),
                      max(rels), len(rels), durable, f"{why}: {trail}", confidence))  # fmt: skip


def mog_outputs(c: Collect, releases: list[str], out: Path) -> dict:
    """Department changes between consecutive releases, and the BEIS sub-segment successor map."""
    events = []
    for prev, nxt in zip(releases, releases[1:], strict=False):
        a, b = c.org_dept[prev], c.org_dept[nxt]
        moves: dict[tuple, list] = defaultdict(list)
        for code in sorted(set(a) | set(b)):
            if code in a and code in b:
                da, db = _main_dept(a[code]), _main_dept(b[code])
                if da != db:
                    moves[("department_changed", da, db)].append((code, code, a[code], b[code]))
        gone = sorted(set(a) - set(b))
        new = sorted(set(b) - set(a))
        new_by_prefix = defaultdict(list)
        for code in new:
            new_by_prefix[split_code(code)[0]].append(code)
        matched_new = set()
        for code in gone:
            succ = new_by_prefix.get(split_code(code)[0], [])
            if len(succ) == 1:
                matched_new.add(succ[0])
                moves[("code_changed", _main_dept(a[code]), _main_dept(b[succ[0]]))].append(
                    (code, succ[0], a[code], b[succ[0]])
                )
            else:
                moves[("organisation_dropped", _main_dept(a[code]), "")].append((code, "", a[code], {}))
        for code in new:
            if code not in matched_new:
                moves[("organisation_added", "", _main_dept(b[code]))].append(("", code, {}, b[code]))
        for (kind, da, db), items in sorted(moves.items()):
            amt_a = sum((sum(x[2].values(), ZERO) for x in items), ZERO)
            amt_b = sum((sum(x[3].values(), ZERO) for x in items), ZERO)
            codes = " ".join(f"{x[0]}->{x[1]}" if x[0] and x[1] and x[0] != x[1] else (x[0] or x[1]) for x in items)
            events.append((prev, nxt, release_fy(prev), release_fy(nxt), kind, da, db, len(items),
                           codes, amt_a, amt_b))  # fmt: skip
    write_csv(out / "org_mog_events.csv",
              ("release_before", "release_after", "fy_before", "fy_after", "change", "department_before",
               "department_after", "n_organisations", "organisation_codes", "amount_before", "amount_after"),
              events)  # fmt: skip
    write_csv(
        out / "org_within_release_department_mix.csv",
        ("release", "organisation_code", "departments_and_periods"),
        sorted(c.within_mix),
    )

    # BEIS split
    beis_columns = (
        "release",
        "sub_segment_code",
        "sub_segment_name",
        "organisation_codes",
        "organisation_names",
        "core_or_body",
        "amount_full_year",
        "match_method",
        "match_status",
        "successor_departments",
    )
    with_beis = [r for r in releases if any(BEIS in d for v in c.org_dept[r].values() for d in v)]
    if not with_beis or with_beis[-1] == releases[-1]:  # no split visible in this set of releases
        write_csv(out / "org_beis_subsegment_map_candidates.csv", beis_columns, [])
        return {"beis_release": "", "successor_releases": [], "beis_rows": []}
    beis_rel = with_beis[-1]
    first_after = releases[releases.index(beis_rel) + 1]
    succ_rels = [r for r in releases if r > beis_rel and release_fy(r) == release_fy(first_after)]
    by_code: dict[str, set] = defaultdict(set)
    by_name: dict[str, set] = defaultdict(set)
    org_succ: dict[str, set] = defaultdict(set)
    for r in succ_rels:
        for code, (name, pairs, _a) in c.subseg[r].items():
            for _org, dept in pairs:
                by_code[code].add(dept)
                by_name[norm_name(strip_subsegment_code(name, code))].add(dept)
        for org, depts in c.org_dept[r].items():
            org_succ[split_code(org)[0]].update(depts)
    beis_rows = []
    beis_orgs = [o for o, depts in c.org_dept[beis_rel].items() if BEIS in depts]
    core_org = max(beis_orgs, key=lambda o: (max(similarity(norm_name(n), BEIS) for n in c.org_name[beis_rel][o]), o))
    for code, (name, pairs, amount) in sorted(c.subseg[beis_rel].items()):
        beis_pairs = [(o, d) for o, d in pairs if BEIS in d]
        if not beis_pairs:
            continue
        orgs = sorted({o for o, _ in beis_pairs})
        org_names = sorted({n for o in orgs for n in c.org_name[beis_rel].get(o, [])})
        is_core = core_org in orgs
        method, depts = "none", set()
        if code in by_code:
            method, depts = "sub_segment_code", by_code[code]
        else:
            nm = norm_name(strip_subsegment_code(name, code))
            if nm in by_name:
                method, depts = "sub_segment_name", by_name[nm]
            else:
                prefixes = {split_code(o)[0] for o in orgs}
                cand = set().union(*(org_succ.get(p, set()) for p in prefixes))
                if cand and not is_core:
                    method, depts = "organisation_prefix", cand
        status = "unmatched" if not depts else ("one_successor" if len(depts) == 1 else "several_successors")
        beis_rows.append((beis_rel, code, name, " ".join(orgs), " / ".join(org_names), "core" if is_core else "body",
                          amount, method, status, " / ".join(sorted(depts))))  # fmt: skip
    write_csv(out / "org_beis_subsegment_map_candidates.csv", beis_columns, beis_rows)
    return {"beis_release": beis_rel, "successor_releases": succ_rels, "beis_rows": beis_rows}


def _main_dept(depts: dict[str, Decimal]) -> str:
    if len(depts) == 1:
        return next(iter(depts))
    return " + ".join(sorted(depts))


# ------------------------------------------------------------------------------------------- run


def run(root: Path, out_docs: Path | None = None, out_audit: Path | None = None, log=print) -> dict:
    out_docs = out_docs or root / DOCS_DATA
    out_audit = out_audit or root / AUDIT
    with decimal.localcontext(EXACT):
        return _run(root, out_docs, out_audit, log)


def _run(root: Path, out_docs: Path, out_audit: Path, log) -> dict:
    t0 = time.perf_counter()
    files = list_inyear_files(root)
    by_release: dict[str, list[InyearFile]] = defaultdict(list)
    for f in files:
        by_release[f.release].append(f)
    releases = sorted(by_release)
    by_fy: dict[str, list[str]] = defaultdict(list)
    for rel in releases:
        by_fy[release_fy(rel)].append(rel)

    c = Collect()
    res = Restate()
    profiles: list[FileProfile] = []
    twins = []
    by_budget = []
    for fy in sorted(by_fy):
        series = []
        for rel in by_fy[fy]:
            fs = sorted(by_release[rel], key=lambda f: (f.container != "zip-csv", f.container != "zip-ods", f.filename))
            primary, others = fs[0], fs[1:]
            p, rows = profile_file(primary, root, True, keep_digest=bool(others))
            profiles.append(p)
            log(f"  {rel} {primary.filename}: {p.stats.data_rows} rows, {p.seconds:.1f} s")
            for o in others:
                po, _ = profile_file(o, root, False, keep_digest=True)
                profiles.append(po)
                twins.append((rel, primary.filename, o.filename, p.stats.data_rows, po.stats.data_rows,
                              p.row_digest == po.row_digest, p.total == po.total))  # fmt: skip
                log(f"  {rel} {o.filename}: {po.stats.data_rows} rows, identical rows: {p.row_digest == po.row_digest}")
                p.row_digest = Counter()
            final = rel == by_fy[fy][-1]
            collect_release(c, p, rows, final)
            grain_release(c, rel, rows)
            zero_release(c, rel, rows)
            window_release(c, p)
            amounts = amounts_by_key(rows)
            periods = {key_plan(r): r.period for r in rows}
            series.append((rel, amounts, periods))
            del rows
        restate_fy(res, fy, series)

    for p in profiles:
        for dim, d in (("control_budget_code", p.by_cb), ("economic_budget_code", p.by_eb)):
            for value, (n, amt) in sorted(d.items()):
                by_budget.append((p.f.release, p.f.filename, dim, value, n, amt))

    profiles.sort(key=lambda p: (p.f.release, p.f.filename))
    write_csv(out_audit / "inyear_file_control_totals.csv", CONTROL_COLUMNS, [control_row(p) for p in profiles])
    write_csv(out_audit / "inyear_file_control_totals_by_budget.csv",
              ("release", "filename", "dimension", "value", "rows", "amount"), by_budget)  # fmt: skip

    # 2. header variants and value domains
    variant_releases = defaultdict(list)
    for p in profiles:
        variant_releases[p.stats.header_variant].append(p.f.release)
    hv = []
    for name, cols in HEADER_VARIANTS.items():
        rels = sorted(set(variant_releases.get(name, [])))
        for i, (src, canon) in enumerate(cols, start=1):
            hv.append((name, " ".join(rels), len(rels), i, src, canon))
    write_csv(
        out_docs / "inyear_header_variants.csv",
        ("variant", "releases", "n_releases", "position", "source_column", "canonical_column"),
        hv,
    )
    dom = []
    for (col, value), (rels, n) in sorted(c.domains.items()):
        rs = sorted(rels)
        if col == "pesa_economic_group_name" and value == "":
            pass
        norm = ""
        if col == "control_budget_code":
            norm = CB_NORMAL.get(value, "UNMAPPED")
        elif col == "economic_budget_code":
            norm = EB_NORMAL.get(value, "UNMAPPED")
        elif col.startswith("control_budget_code +"):
            cb, cbd = value.split(" | ")
            norm = f"{CB_NORMAL.get(cb, 'UNMAPPED')} | {cbd}"
        dom.append((col, value, norm, rs[0], rs[-1], len(rs), n))
    write_csv(
        out_docs / "inyear_value_domains.csv",
        ("column", "value", "normalised_value", "first_release", "last_release", "n_releases", "rows"),
        dom,
    )

    # 3. time
    trows = []
    for (rel, year, quarter, month, fy, per), (n, amt) in sorted(c.time.items()):
        qn, qfy = parse_quarter(quarter)
        flags = []
        if not per:
            flags.append("month_not_a_calendar_month")
        if parse_year(year) != year:
            flags.append("year_unparsed")
        if fy and year != fy:
            flags.append("year_disagrees_with_month")
        if not qn:
            flags.append("quarter_unparsed")
        elif per and (qfy != fy or qn != (per - 1) // 3 + 1):
            flags.append("quarter_disagrees_with_month")
        if per and fy != release_fy(rel):
            flags.append("month_outside_release_year")
        if per and per > EXPECTED_LAST_PERIOD[rel[5:7]]:
            flags.append("month_beyond_release_window")
        trows.append((rel, year, quarter, month, fy, per, n, amt, " ".join(flags)))
    write_csv(out_docs / "inyear_time_values.csv",
              ("release", "year", "quarter", "month", "financial_year_from_month", "period", "rows", "amount",
               "flags"), trows)  # fmt: skip
    write_csv(out_docs / "inyear_release_windows.csv",
              ("release", "filename", "expected_financial_year", "expected_periods", "financial_years_present",
               "periods_present", "rows_without_calendar_month", "matches_expected"), c.windows)  # fmt: skip

    # 4. grain
    write_csv(out_docs / "inyear_grain.csv",
              ("release", "rows", "key", "distinct_keys", "duplicate_groups", "rows_in_duplicate_groups",
               "groups_exact_repeat", "groups_same_attributes_different_amount", "groups_differing_in_other_columns",
               "abs_amount_in_duplicate_groups"), c.grain)  # fmt: skip
    write_csv(out_docs / "inyear_grain_duplicate_examples.csv",
              ("release", "key", "line", "organisation_code", "organisation_name", "control_budget_code",
               "control_budget_detail_code", "department_name", "sub_segment_code", "sub_segment_name",
               "economic_category_code", "economic_category_name", "economic_budget_code", "pesa_economic_group_code",
               "pesa_economic_group_name", "version", "year", "quarter", "month", "amount_text"),
              c.dup_examples)  # fmt: skip

    # 5. restatement
    write_csv(out_docs / "inyear_restatement_pairs.csv",
              ("financial_year", "release_before", "release_after", "periods_compared", "keys_changed",
               "keys_vanished", "keys_appeared", "keys_unchanged", "abs_movement", "net_movement",
               "total_before", "total_after"), res.pairs)  # fmt: skip
    write_csv(out_docs / "inyear_restatement_by_month.csv",
              ("financial_year", "release_before", "release_after", "period", "keys_changed", "keys_vanished",
               "keys_appeared", "keys_unchanged", "abs_movement", "net_movement", "total_before", "total_after"),
              res.by_month)  # fmt: skip
    write_csv(out_docs / "inyear_restatement_examples.csv",
              ("financial_year", "release_before", "release_after", "organisation_code", "sub_segment_code",
               "economic_category_code", "control_budget_detail_code", "month", "amount_before", "amount_after",
               "change"), res.examples)  # fmt: skip
    write_csv(out_docs / "inyear_delta_rowcount.csv",
              ("financial_year", "release", "release_no_in_year", "stacked_keys", "first_appearances",
               "changed", "vanished", "delta_rows_all", "delta_rows_non_zero"), res.delta)  # fmt: skip

    # 6. zero rows
    write_csv(out_docs / "inyear_zero_rows.csv",
              ("release", "rows", "zero_rows", "zero_share", "line_keys", "months", "grid_density",
               "line_keys_all_zero"), c.zero)  # fmt: skip

    # 7. signs (last release of each financial year only, so no row is counted twice)
    srows = []
    for (grp, cat), (pos, neg, zer, spos, sneg, names) in sorted(c.signs.items()):
        n = pos + neg
        srows.append((grp, cat, " / ".join(sorted(names)), pos, neg, zer, spos, sneg, spos + sneg,
                      pct(neg, n), "Y" if pos and neg else "N"))  # fmt: skip
    write_csv(out_docs / "inyear_sign_by_category.csv",
              ("pesa_economic_group_code", "economic_category_code", "economic_category_names", "rows_positive",
               "rows_negative", "rows_zero", "sum_positive", "sum_negative", "sum_net", "share_negative_rows",
               "mixed_signs"), srows)  # fmt: skip

    # 8. chart of accounts
    arows = []
    variants_per_code = Counter(k[0] for k in c.accounts)
    for (code, name, grp, grp_name, eb), (rels, n) in sorted(c.accounts.items()):
        rs = sorted(rels)
        arows.append((code, name, grp, grp_name, eb, rs[0], rs[-1], len(rs), n, variants_per_code[code]))
    write_csv(out_docs / "inyear_account_map.csv",
              ("economic_category_code", "economic_category_name", "pesa_economic_group_code",
               "pesa_economic_group_name", "economic_budget_code", "first_release", "last_release", "n_releases",
               "rows", "variants_for_code"), arows)  # fmt: skip

    write_csv(out_docs / "inyear_twin_files.csv",
              ("release", "primary_file", "other_file", "rows_primary", "rows_other", "rows_identical",
               "totals_equal"), twins)  # fmt: skip

    # 10-12. organisations
    primary_releases = releases
    facts = org_outputs(c, primary_releases, out_docs)
    facts.update(mog_outputs(c, primary_releases, out_docs))
    facts["seconds"] = time.perf_counter() - t0
    log(f"profile inyear: {len(profiles)} files, {len(releases)} releases, {facts['seconds']:.0f} s")
    return facts


def main(root: Path) -> int:
    run(root)
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main(Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()))
