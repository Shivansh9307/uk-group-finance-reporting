# Profiling: organisation codes and department reorganisations

The plan keys `Dim Organisation` (Type 2, versioned by release) on a durable identity that should
survive department reorganisations, defaulting to the letter prefix of the organisation code with an
authored override table. This page tests that default against all 31 in-year releases and lists
the evidence for writing the overrides. Everything here comes from
`uv run --project pipeline ukfr profile inyear` (see [oscar-inyear.md](oscar-inyear.md) for the
run) and is **tested** unless marked otherwise.

## 10. Code history

[`org_code_history.csv`](data/org_code_history.csv) has every distinct (organisation code,
organisation name, department name) with first and last release, release count, rows and the amount
in its last release: 703 combinations of 301 codes and 274 prefixes.

Every code is three capital letters and three digits (`AAA999`, all 1,547,078 rows). Two facts about
the name columns matter more than the codes:

- **Department names are not stable labels.** The same department number is published under
  alternating names from one release to the next: UK Export Finance / Export Credits Guarantee
  Department changes 7 times, Department for (Digital,) Culture, Media and Sport 7 times (once for
  real, in September 2023), Welsh Government / Welsh Assembly Government 6, Department of Health
  (and Social Care) 5, Office for National Statistics / The Statistics Board 4, Ministry "of" /
  "for" Housing, Communities and Local Government 4. Of the 51 department label changes between
  consecutive releases in [`org_mog_events.csv`](data/org_mog_events.csv), 8 reflect a real
  change (question 12) and 43 are the same department under an alternate name.
- **The department number is.** In every release, each three-digit suffix appears under exactly one
  department name and each department name under exactly one suffix
  ([`org_department_numbers.csv`](data/org_department_numbers.csv),
  [`org_department_name_numbers.csv`](data/org_department_name_numbers.csv): zero releases with
  several names per number or several numbers per name).

Organisation names also alternate: BIS084 is published as "Department for Business, Innovation and
Skills" (the pre-2016 name) in 13 releases and as "Department for Business, Energy and Industrial
Strategy" in 5, interleaved, until it becomes DSIT.

## 11. Is the prefix a durable identity?

[`org_durable_key_candidates.csv`](data/org_durable_key_candidates.csv) holds 195 candidate rows,
each with the codes, names, departments and releases behind it, a proposed durable id and a
confidence flag. By finding:

| Finding | Rows | What it shows |
|---|---|---|
| `b0_suffix_change` | 46 (23 pairs) | The durable case: the body keeps its prefix and changes department number. ACAS `ACA084` → `ACA013` and 8 other bodies BEIS → DBT; 11 bodies BEIS → DESNZ (`NDA084` → `NDA066`, ...); `ICO048` → `ICO084` (DCMS → DSIT); `WFD027` → `WFD030` (FCO → FCDO); `EHR030` → `EHR010` |
| `a_prefix_collision` | 8 (4 cases) | Two codes share a prefix in the same release |
| `b_prefix_change` | 4 (2 cases) | Same body, different prefix |
| `c_code_reused` | 12 (6 transitions) | A code carries a different body after a change |
| `d_name_change` | 49 | Name changes under one code (renames, abbreviations expanded) |
| `d_name_alternates` | 40 | Two names that alternate under one code, i.e. aliases |
| `e_code_retired` | 36 | Codes not seen in the last four releases; 4 of them with their department number retired too |

(a) **Collisions** (prefix held by two bodies at once):

- `UKG084` UK Green Investment Platform Entity (BEIS) and `UKG087` UK Government Investments
  (HM Treasury), together in 17 releases, June 2019 to June 2023; then `UKG066` (DESNZ) and
  `UKG087` in June 2024. Different bodies: the durable id must be the full code.
- `DOH004` "DOHL" (Department for Transport) and `DOH033` Department of Health (NHS), together in 5
  releases, March 2020 to March 2021. Different bodies.
- `EHR030` (under DFID) and `EHR034` (Home Office), both Equality and Human Rights Commission, in
  June 2019 only: one body coded under two departments in one release, which looks like a coding
  error at source (EHRC then settles as `EHR010` under the Cabinet Office).

(b) **Same body, new prefix**: Ofcom, `OFC048` (DCMS, to June 2023) then `OCM084` (DSIT, from
December 2023). The other pair the matcher raises, `CIT022` / `EIT022`, is two different
construction training boards (flagged `low`). Prefix changes are rare (1 real case) but they do
happen, so the override table cannot assume they never do.

(c) **Codes reused for a different body** (core departments):

- `BIS084`: BEIS core to June 2023, DSIT core from September 2023.
- `UKT013`: DIT core to June 2023, DBT core from September 2023.
- `DID030`: DFID core to September 2020; from December 2020 it is named "Foreign, Commonwealth
  and Development Office", and from September 2021 it also absorbs the Foreign Office core, whose
  code `FCO027` is never seen again (listed under `e_code_retired`).
- `PRR079`: Parliament Restoration and Renewal, then Parliamentary Works Grant from September 2023
  (`medium`: one-organisation department, more rename than reuse).
- `OSS907` is a false positive (the FCDO/DFID overseas superannuation scheme whose label
  alternates); its rows are flagged `medium` so the reviewer can drop them.

(d) **Names that change while the code stays**: 49 transitions, for example `HCA085` Homes and
Communities Agency → Homes England, `SHC004` Highways England → National Highways, `INB087` UK
Infrastructure Bank → National Wealth Fund, `RPC004` Rail Passenger Council → Transport Focus,
`SFG032` Single Financial Guidance Body → Money and Pensions Service. 30 are `high` (similar names,
or one is the abbreviation of the other), 19 `medium` (a genuine rename inside the same department;
I checked the ones above by hand and all are the same body). 40 further rows are aliases that
alternate (`d_name_alternates`).

The proposed durable id is the prefix wherever the evidence supports it, the full code for the two
collisions, and `<prefix>.<initials>` per period for reused core codes (for example `BIS.DSIT`).
Two proposals need a human: the BEIS-era `BIS084` run is labelled from the organisation name it
happened to carry (`BIS.DBIS`) and should simply be BEIS, and the FCO core merger into `DID030`
has no row of its own beyond the retired `FCO027`.

## 12. Reorganisations visible in the in-year series

[`org_mog_events.csv`](data/org_mog_events.csv) compares each release with the previous one:
organisations whose department changed, codes that changed (matched by prefix), and organisations
added or dropped, with amounts on both sides.
[`org_within_release_department_mix.csv`](data/org_within_release_department_mix.csv) is empty: in
every release each organisation sits under one department for all months. So **the first release
that shows a new structure relabels every month of its financial year, and earlier releases are
never relabelled** (they are snapshots).

| Change | First release showing it | Relabelled months | What moved |
|---|---|---|---|
| FCO + DFID → FCDO (Sep 2020) | Dec 2020: `DID030` renamed FCDO, department still DFID. Jun 2021: DFID's 3 organisations (`CSC030`, `DID030`, `ICA030`) labelled FCDO. Sep 2021: `FCO027` gone, `WFD027` → `WFD030` | All of FY2020-21 in Jun 2021; FCO and FCDO appear side by side in that release | DFID bodies by relabel; FCO core absorbed into `DID030`'s code |
| MHCLG → DLUHC (Sep 2021) | Dec 2021 | All of FY2021-22 | 9 organisations, codes unchanged |
| BEIS → DESNZ / DSIT / DBT, DIT → DBT, DCMS digital → DSIT (Feb 2023) | Sep 2023 (Mar and Jun 2023 still show BEIS and DIT for all of FY2022-23) | FY2023-24 onwards only; FY2022-23 is never restated in-year | 9 bodies to DBT and 11 to DESNZ with new department numbers; `BIS084`, `ARI084`, `SSC084`, `URI084` relabelled DSIT; `TRA013`, `UKT013` relabelled DBT; `ICO048` and `OFC048` dropped in Sep 2023 and reappear as `ICO084` and `OCM084` under DSIT in Dec 2023 |
| DLUHC → MHCLG (Jul 2024) | Sep 2024 | All of FY2024-25 | 9 organisations, codes unchanged |
| DExEU closed (Jan 2020) | `DEU077` last seen Mar 2020 | n/a | department number 077 retired |
| Parliament R&R → Parliamentary Works Grant | Sep 2023 | FY2023-24 | `PRR079` |

The FCDO row is the only change that appears inside a financial year without a new year's first
release, and even there the relabel waits for the June release, so the in-year series shows FCO and
DFID separately for three releases after FCDO existed.

**BEIS split: can each BEIS sub-segment be matched to one successor?** I took every sub-segment
under BEIS in the last BEIS release (June 2023, FY2022-23 in full) and looked for it in the
FY2023-24 releases (September 2023 to June 2024): first by sub-segment code, then by its name with
the code prefix removed, then (bodies only) by organisation prefix.
[`org_beis_subsegment_map_candidates.csv`](data/org_beis_subsegment_map_candidates.csv) has all
204 rows with the method and the successor department.

| Sub-segments | Count | Gross £ (FY2022-23) | Net £ |
|---|---|---|---|
| Matched to exactly one successor | 194 | £185.79bn | -£46.81bn |
| Matched to two successors (DBT and DESNZ) | 1 | £7.7m | £7.7m |
| Unmatched (all BEIS core) | 9 | £35.4m | -£29.6m |

Of the 123 BEIS-core sub-segments, 113 match one successor (36 to DSIT by code, 35 to DBT and 42
to DESNZ by name; £56.23bn gross), 1 matches two and 9 do not (£35.4m gross, 0.06% of core). Of the
81 arm's-length-body sub-segments, all match one successor (30 by code, 45 by name, 6 by
organisation prefix). By value, 99.98% of the BEIS gross amount maps deterministically.

As an independent check I looked the same codes up in the November 2023 BUD file for 2022-23,
which HM Treasury restated onto the new structure (`bud_beis_subsegment_crosscheck.csv`, produced by
`ukfr profile bud`). For 178 of 204 sub-segments (£184.69bn of £185.79bn gross) the BUD agrees:
codes I map to DSIT still carry value in the DSIT group, and codes I map to DESNZ or DBT net to zero
in the BUD because their spending moved to new codes. It disagrees for 15 (£1.10bn gross): 7 that I
map to DESNZ or DBT still hold value under DSIT in the BUD (£117.7m), and 8 that I map to DSIT net to
zero there (£985.2m). Those 15 are the list a reviewer should look at first. Using the BUD to build
the map would break the plan's rule that the split is reconciled against a restated release not
used to derive it, so I keep it as a check only.

## Decisions this supports

- **GO with overrides** on "prefix = durable identity": 23 bodies moved department and kept their
  prefix; against that, 4 collisions (2 that need the full code), 1 genuine prefix change (Ofcom),
  3 core-department codes reused for a new department (BEIS → DSIT, DIT → DBT, DFID → FCDO) and
  one merger into a reused code (FCO core into `DID030`). The prefixes `UKG` and `DOH` need the
  full code; `EHR` in June 2019 is a coding error. That is about ten authored rows, all listed with
  evidence.
- **NO-GO** on department name as a key or even a label: 43 of 51 department label changes between
  releases are the same department under an alternate name; use the department number (suffix),
  which maps one-to-one to a department name in every release.
- **GO** on deterministic "current structure" mapping for the BEIS split: 194 of 204 sub-segments
  (99.98% of gross value) match exactly one successor by code, name or prefix; a stated driver is
  needed for 10 sub-segments worth £43m gross.
- **GO** on relabelling being whole-year: 0 organisations sit under two departments inside any
  release, so a reorganisation always shows as a change between releases, never within one.

## What I would change in the design

- Key the department on the three-digit department number, with an authored name per number and
  period (084 = BEIS to June 2023, DSIT after; 013 = DIT then DBT; 030 = DFID then FCDO), instead of
  on the department name in the file.
- Version organisation names on the code but treat alternating names as aliases: a Type 2 change
  every time HM Treasury flips between two published names would add history rows with no meaning
  (40 alias transitions found).
- Make the durable key `prefix` by default and the full code for the collision list, and let the
  override table also carry period-bounded mappings for reused core codes; the default alone would
  merge BEIS core history into DSIT and DIT into DBT.
- For "current structure", map BEIS lines by sub-segment first as planned; the evidence says the
  stated-driver residual is small (£43m gross), so it can be a single "unallocated BEIS core" line
  rather than a driver-based split.
