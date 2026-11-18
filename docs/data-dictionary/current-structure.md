# Data dictionary: the current structure

Which department each in-year line belongs to in the structure of the latest release, and how I checked it
against an annual file that I did not use to build it. Built by `ukfr build --scope committed` from the 31
in-year releases and `authored/`; the hold-out needs the annual files and is built only by `--scope full`.
Every claim is labelled **tested** (command and result file) or **designed**.

The reader of the numbers needs one rule: a line has exactly one department. There is no weighting and no
share. A line that no evidence can place goes whole to an Unallocated member that is named after the
department it came from.

## Objects

| Object | Rows (committed build) | Grain | What it is |
|---|---|---|---|
| `stg.subsegment_label` | 58,524 | release x sub-segment code | the sub-segment name with its code removed, upper case, punctuation turned into spaces (`label_norm`); used to follow a name |
| `authored.current_structure_map`, `stg.current_structure_authored` | 20 | one decision | the authored rows (see below) |
| `dw.current_structure_department` | 76 | department period | whether it counts as a current department (`is_live`) and its current form |
| `dw.current_structure_organisation` | 278 | durable key | the department of its latest version, its home and its successor's department |
| `dw.current_structure_line` | 5,480 | organisation version x sub-segment | the result, with the evidence |
| `stg.current_structure_map` (view) | 5,480 | the same | the five columns the fact reads; the contract is unchanged |
| `audit.current_structure_coverage` | 542 | year x method x former department x current department | lines, rows, net and gross amount |
| `audit.current_structure_authored` | 20 | one authored row | what the row decides and whether it changes the answer |
| `audit.current_structure_code_rule_rejected` | 6 | line | lines where I did not follow the code (below) |
| `dw.bud_group_current_department`, `audit.current_structure_holdout` | full scope only | | the hold-out |

Row counts are from the committed build (`evidence/build/table_counts.csv` for the tables in it; the three
dw tables above were counted in the database). `gross` below is the sum, over lines, of the absolute value
of the line's total for a financial year, taken from the year-end release of the year (the June release with
periods 1 to 12), in GBP thousands; it is the profile's "gross".

## Definitions

- **Current department**: a `dim_department` period with `is_current = 1`, an Unallocated member, or the last
  period of a number that the latest year-end release (June 2026) reports. The third clause is there because
  the newest release, September 2026, is partial: National Audit Office (050), Crown Estate Office (014) and
  the Judicial Pensions Scheme (908) report in June and not in September, so `is_current` marks them closed.
  They are not closed, and I did not want their lines to become Unallocated. `dw.dim_department.is_current`
  is unchanged; the extra clause lives in `dw.current_structure_department.is_live`. If `is_current` is later
  defined on the latest year-end release, the clause becomes redundant.
- **Current form** of a department period: itself if it is a current department, otherwise the latest current
  period of the same number (DLUHC becomes MHCLG, the old DCMS name becomes DCMS). A number whose core code was
  reused for a different department (override reason `reused_code`: 013, 030, 084) gives its earlier period no
  current form: BEIS is not DSIT, DIT is not DBT, DFID is not FCDO.
- **Home**: the current form of the department of the latest version of the organisation's durable key.
  Nine durable keys have none: ARA, BIS.BEIS, DEU, DID.DFID, ELC, FCO, PSH, STS, UKT.DIT (the Unknown key has none either, and has no lines).

## Rules

The first rule that gives a department decides the line; `method` records which. **Tested**:
`sql/tests/450` (every line once, current department, allowed method), `241` (contract), `240` (coverage).

1. `authored line`: a row of `authored/current_structure_map.csv` for the durable key and sub-segment.
2. `authored organisation`: a row with a blank sub-segment, for an organisation that has a home.
   (The two next rules are only for an organisation without a home.)
3. `sub-segment code`: the code is still published after the organisation's last release. The department is the
   current form of the one that publishes it in the latest release that has it.
4. `sub-segment name`: the code stopped, but the same name is published under another code after the code's last
   release; the department is the one that publishes it in the latest such release, and only if there is one
   department (a name in two departments does not decide).
5. `authored organisation`, again, for an organisation without a home.
6. `organisation current department`: the home.
7. `organisation successor`: the current form of the department of the successor key's latest version
   (only FCO, into FCDO, has one in `organisation_key_override.csv`).
8. `unallocated former department`: the Unallocated member `U` + the former department's number.

**Why the code and name rules are not applied to an organisation that has a home.** I computed the code rule for
every line first. For organisations with a home it differs from the organisation in six lines and I checked each
(`audit.current_structure_code_rule_rejected`): `X034A165` and `X034A166` (Equality and Human Rights Commission,
EHR034) last appear in June 2019 under the Home Office, while the body is under the Cabinet Office today; and
four Ofcom lines (`X048A064`, `065`, `067`, `068`, OFC048), whose codes are used by the British Film Institute
in DCMS in 2026 while Ofcom is under DSIT. In each the code's last publisher is a different body or a stale
record, so following the organisation is right. A seventh case, `X084A344`, is authored (below). **Tested**:
`pipeline/tests/test_current_structure.py` (no rejected line carries the code method). I looked for a line moving out of a department that still exists (the DCMS digital lines to DSIT in February 2023) and it is not in the data: no line of a
body that has a home has a code that now sits in another current department apart from these.

## The BEIS split

The 204 sub-segments that June 2023 reports under BEIS (department 084). **Tested**:
`sql/tests/454` (all 204 map to DSIT, DESNZ, DBT or `U084`), `pipeline/tests/test_current_structure.py`
(the split below).

By the rules alone, before the authored rows:

| Rule | Sub-segments | Profile |
|---|---|---|
| `sub-segment code` | 36 (all DSIT) | 36 by code |
| `sub-segment name` | 79 | 77 by name, plus 1 with two successors |
| `organisation current department` (bodies) | 81 | 81 (30 by code, 45 by name, 6 by prefix, which are the same bodies) |
| no rule (`unallocated former department`) | 8 | 9 unmatched |

Where I differ from the profile, and why (the profile looked only at the first financial year after the split;
the map takes the latest release that carries the code or name):

- `X084A010` British Shipbuilders DEL: the profile has two successors (DBT and DESNZ); the name sits in DESNZ
  (`X066A123`) from September 2023 and in DBT (`X013A027`) from December 2023, and in June 2026 only in DBT
  with 7,003. I map it to DBT. `X084A011`, the AME line, profile DESNZ, map DBT for the same reason.
- `X084A452` Post Office other AME: the profile found nothing; the name is in DBT (`X013A093`) from December 2024.
- `X084A344` British Business Bank: the profile sent it to DSIT by code, because `BTI084` (British Technology
  Investments, a different body) published the code once in March 2024. The bank's own organisation reports under
  DBT from September 2023. DBT.

Eight lines have no successor by rule (profile: nine). Of them I place three by judgement (below); five remain in
`U084`: `X084A067` Enemy property AME, `X084A118` HE miscellaneous, `X084A268` Ordnance Survey PSMA,
`X084A611` Keeping energy bills low, `X084A626` Clean growth fund AME (gross 5,114 together in 2022-23, GBP thousands).

## The review of the 15 disagreements

The November 2023 annual file (vintage 2023-11), restated by HM Treasury onto the new structure, disagrees with the
profile's in-year successor on 15 BEIS sub-segments (1.10bn gross). It is used only for this review.
`bud_beis_subsegment_crosscheck.csv` says which; each has a row in `authored/current_structure_map.csv`
(**tested**: `pipeline/tests/test_current_structure.py`, the 15 are derived from that file).

**Eight lines the in-year rule sends to DSIT and the annual file nets to zero.** The same amount reappears,
to the thousand, on a new code in another department's group (query on `raw.oscar_bud`, vintage 2023-11, year
2022-23, Closed rows excluded). The code stayed on in the DSIT core's account with small amounts, which is why the
code rule found it there (for example `X084A012`: 346,018 in June 2023, 5,023 in September 2023). Decision: follow
the annual file.

| Sub-segment | In-year rule | Decision | Where the amount reappears |
|---|---|---|---|
| `X084A002` Better regulation DEL | DSIT | DBT | `X013A026`, 28,993 |
| `X084A012` Business and enterprise misc DEL | DSIT | DBT | `X013A029`, 346,018 |
| `X084A154` Market frameworks misc DEL | DSIT | DBT | `X013A050`, 94,420 |
| `X084A233` UKAEA DEL | DSIT | DESNZ | `X066A151`, 2,954 |
| `X084A234` UKAEA AME | DSIT | DESNZ | `X066A152`, -69,240 |
| `X084A396` Access to finance DEL | DSIT | DBT | `X013A078`, 18,387 |
| `X084A511` New nuclear DEL | DSIT | DESNZ | `X066A011`, 38,982 |
| `X084A344` British Business Bank DEL (body BBB084) | DSIT in the profile | DBT | `X013A114`, 386,214 |

**Seven lines the in-year successor sends to DESNZ or DBT and the annual file still holds in the DSIT group.**
The file left small amounts of several bodies on their old 084 codes in that group while moving the rest of the
body to its new code (`BBB013`, `BPA013`, `OGA066`, `SAL066` are all in the file), so a leftover on the old code
is not evidence of the department. Decision: keep the in-year successor. The row is there to record the review.

| Sub-segment | Kept | Why |
|---|---|---|
| `X084A267` Ordnance Survey open data DEL | DBT | same name in DBT from June 2024 (`X013A064`) |
| `X084A306` Postal Services Act company (BPA084) | DBT | the body reports under BPA013 in DBT |
| `X084A323` Shareholder exec other AME | DESNZ | same name in DESNZ (`X066A131`) |
| `X084A346` British Business Bank non-budget (BBB084) | DBT | the body reports under BBB013 in DBT |
| `X084A524` Science and innovation DEL | DESNZ | same name in DESNZ (`X066A024`); weakest of the seven (generic name, 189) |
| `X084A616` Oil and Gas Authority non-budget (OGA084) | DESNZ | the body reports under OGA066 |
| `X084A621` Salix DEL admin (SAL084) | DESNZ | the body reports under SAL066 |

**Three lines estimated.** `X084A031`, `X084A254` (UK Innovation Fund AME, -20,700) and `X084A364` have no successor
by code, name or organisation, and the annual file holds a small amount on them in the DSIT group. It is the only
published placement, so I follow it, and I mark the three rows `is_estimated = 1`. The group holds leftovers
(see above), so this is weak; the lines are 21 million pounds gross together. These are the only estimated
lines (**tested**: `sql/tests/453`; 3 lines in `dw.current_structure_line` have `is_estimated = 1`).

**Two organisation rows.** DFID and DIT closed into FCDO and DBT and kept the same organisation code. Lines of
their cores that no code or name continues (9 of DFID, 2 of DIT) go to FCDO and DBT.

`audit.current_structure_authored` shows for each row how many lines it decides and how many it changes against
the rules alone: 10 rows change the rules' answer (the seven follow-the-file rows that move a line, and the three estimated); the other 10 record a review whose answer the rules already give, or place lines no rule reaches (the two organisation rows).

## Unallocated members

Four, added to `authored/department_name.csv` (the existing rows are unchanged): `U011` Electoral Commission
(last reported June 2025), `U035` Assets Recovery Agency, `U077` Department for Exiting the European Union and
`U084` BEIS "shared lines". Lines in them, 36 pairs. Gross by financial year, from
`audit.current_structure_coverage` (GBP thousands):

| Year | U011 | U035 | U077 | U084 |
|---|---|---|---|---|
| 2018-19 | 16,640 | | 84,012 | 652,961 |
| 2019-20 | 18,691 | 96 | | 182,786 |
| 2020-21 | 20,428 | 100 | | 10,994,258 |
| 2021-22 | 15,058 | | | 7,508 |
| 2022-23 | 26,800 | | | 5,114 |
| 2024-25 | 48,322 | | | |

The 2020-21 figure for `U084` is mostly one line: `X084A449` COVID business support grants. It ended in
2020-21 and no later code or name continues it, so there is nothing to follow. I did not guess that it is DBT's.
The 2018-19 and 2019-20 figures are the coal pensions and privatisation lines. **Tested**: `sql/tests/451` (an Unallocated
member is used only for its own former department, exists with `member_type = Unallocated`, is not empty).

## Rows per method

All 5,480 lines (`dw.current_structure_line`), and gross over the year-end releases of all years
(`audit.current_structure_coverage`, GBP thousands).

| Method | Lines | Gross, all years |
|---|---|---|
| `organisation current department` | 5,198 | 11,865,858,248 |
| `sub-segment name` | 91 | 142,371,855 |
| `sub-segment code` | 121 | 34,642,495 |
| `unallocated former department` | 36 | 12,072,774 |
| `authored line` | 18 | 5,364,331 |
| `organisation successor` | 5 | 3,707,530 |
| `authored organisation` | 11 | 102,621 |

Gross counts a line once for every year it reports, so a line that runs for eight years counts eight times.

## The fact

`dw.fact_outturn.current_department_key` reads the view. For every release the as-at total by current department
equals the total by reported department and the release's snapshot total, and by current department it equals
the snapshot sent through the map. **Tested**: `sql/tests/452`, with `311` unchanged (the current department
follows the map). `241` I rewrote, because its old body asserted the first rule (only two methods, the latest
version's department); the new body asserts the new contract. `240` and `311` are unchanged and pass.

## The hold-out against the 2025 annual file

Full scope only (**tested**: `ukfr build --scope full --recreate --yes`, `evidence/full/current_structure_holdout.csv`,
566 lines). The 2025-11 vintage was not used to build the map or to review it. For each financial year it holds
(2020-21 to 2024-25), level (DEL, total) and current department: the in-year amount from the year-end release on
the current structure, against the annual amount with each organisation sent to the department of its
department group (`dw.bud_group_current_department`: the group's code is its lead organisation; the department
number if it is a current department, else the lead organisation's home or successor, else the Unallocated
member, else none). I did not need an authored mapping. **Tested**: `sql/tests/455` (the table adds up to
`audit.bud_vs_inyear_del` for the vintage, DEL and total; every group has a row).

Residual = in-year minus annual, GBP thousands. Nothing fails on it: before 2024-25 the annual file is a
control for DEL in total only.

DEL, the three departments the split created:

| Year | DSIT in-year | DSIT annual | DSIT residual | DESNZ residual | DBT residual |
|---|---|---|---|---|---|
| 2020-21 | 12,074,572 | 10,927,477 | 1,147,095 (+10.5%) | -257,660 (-2.5%) | 2,164,221 (+9.5%) |
| 2021-22 | 10,357,694 | 10,461,370 | -103,676 (-1.0%) | -1,349,227 (-10.2%) | -140,213 (-2.0%) |
| 2022-23 | 11,368,921 | 11,551,088 | -182,167 (-1.6%) | 605,596 (+3.1%) | -288,003 (-17.3%) |
| 2023-24 | 12,964,282 | 13,242,549 | -278,267 (-2.1%) | 403,162 (+6.2%) | 82,940 (+2.9%) |
| 2024-25 | 13,985,957 | 14,021,927 | -35,970 (-0.3%) | 260,270 (+3.9%) | -87,278 (-3.4%) |

Total (all budgets), same departments:

| Year | DSIT | DESNZ | DBT |
|---|---|---|---|
| 2020-21 | +1,087,937 (+5.4%) | +328,431 (+2.1%) | +12,287,660 (+36.9%) |
| 2021-22 | -8,658,941 (-45.2%) | -4,589,863 (-3.5%) | -573,465 (-14.2%) |
| 2022-23 | -226,593 (-1.9%) | +11,245,532 (-15.4%, the base is net income) | +423,642 (+11.6%) |
| 2023-24 | -10,533,264 (-44.5%) | -5,694,233 (+293%, small net base) | -283,385 (-8.2%) |
| 2024-25 | +17,697 (+0.1%) | -16,440,714 (-74.4%) | +763,651 (+28.6%) |

Reading. At DEL, the three departments are within about 10% in every year but one (DBT 2022-23, 17% of a small
base, 288m). The largest DEL residuals in the whole table are not in departments the map touched: DfE 2023-24
(+7.9bn, +8.2%), MHCLG 2021-22 (+7.8bn, +34.5%) and 2023-24 (+5.5bn), the Home Office 2024-25 (+4.5bn, +30%).
Their lines are decided by `organisation current department` (one zero-value DfE line by name), so the residual
is not the map. I did not take it apart; possible causes (designed, not tested) are that the in-year file is the
June snapshot and the annual file carries later adjustments, and that the two scope a department group differently.
At total level the annual file holds AME and non-budget items that the in-year file does not, which
`audit.bud_vs_inyear_del` already records for the whole of government as boundary differences. DSIT 2021-22 and
2023-24 (-45%) are the largest total residuals among the three and I do not have a tested explanation. The `NONE` rows are the annual groups that have no
department in the in-year series (local government, central exchequer): 181bn to 225bn a year in the annual total.
The Unallocated members: `U084` is outside the annual file in every year, as expected, and `U011` agrees with the
annual file within 14% in the years the Electoral Commission reports, and is 0 in 2023-24, a year in which the
June 2024 release has no row for it.

## Not done

- The residual above is published, not explained line by line.
- I did not use the 2024-11 annual vintage for anything.
- A line of the DSIT core that was not recoded (small residual amounts on codes that moved) stays DSIT: it is a line
  of the DSIT version of the core, which has its own durable key.
- The mapping is of in-year lines to departments; it does not map plans or annual lines.
