# The semantic model

One Power BI semantic model, `model/UKGroupFinance.pbip` (PBIP: TMDL for the model, PBIR for the report), on the star
schema that `ukfr build` writes to SQL Server. This page says what is in it, where each table comes from, how the
tables relate, what the measures and the three calculation groups do, and what I left out and why. The group income and
expenditure statement has its own section below. The restatement measures, the department-structure measures and a rank have their own sections below. Row-level and object-level security, with its synthetic user map, is described in
[security.md](security.md). Every claim is labelled
**tested** (with the command and the result file) or **designed**.

The complete list of tables, columns, measures with their expressions, relationships, roles, perspectives, calculation items
and functions is generated from the running model and not written by hand: [model-reference.md](model-reference.md). It is
produced from the INFO functions by `ukfr model-docs`, and `ukfr ledger check` fails when the model has changed since it was
generated ([evidence.md](evidence.md)).

## Decisions

- **Import mode, compatibility level 1702**, hand-written TMDL (**tested**: Desktop opens the project, and
  `tools/run_dax_tests.ps1` queries it; Tabular Editor 2's Best Practice Analyzer runs on the folder in CI with the project rule
  file, see "Scripts, rules and perspectives" below). Import because the largest table is 658,554 rows and refreshes in seconds
  (**tested**: below); DirectQuery would add latency for no gain.
- **The model reads views, not tables.** Each of the 16 SQL tables is one partition that navigates to one view,
  `dw.v_model_<table>` (`sql/dw/700` to `705`), with the `Server` and `Database` parameters. A view is a plain select
  of the columns the model needs under stable snake_case names; the business names live in the TMDL. The only logic is
  the join that exposes a key (below). **Tested**: `sql/tests/700` (every view has the rows of its base table or the
  documented subset), `701` (the fact views keep every amount), `702`, `703`, `706`.
- **Every SQL query folds.** A partition is a bare navigation, so the whole table is one `SELECT` of named columns
  from the view. **Tested**: an Extended Events session recorded the statement of each of the 16 partitions during a
  refresh, every one a single `select ... from [dw].[v_model_...] as [$Table]` sent by the Mashup Engine with no
  filter, join or local step ([evidence/model/partition_queries.csv](../evidence/model/partition_queries.csv)).
- **No `RangeStart` or `RangeEnd`, no refresh policy.** Those belong to the scale model. **Tested**:
  `pipeline/tests/test_model_files.py::test_the_model_has_no_refresh_policy_no_range_parameters_and_no_date_table`.
- **Fiscal time is `dw.dim_period`.** `Fiscal Period` is one row per financial year and period, 0 to 12; period 0
  holds the 71 June 2019 rows that the source does not allocate to a month, and counts in year totals. There is no
  calendar date table, and auto date/time is off (`annotation __PBI_TimeIntelligenceEnabled = 0`; **tested** by the
  same pytest file). Implicit measures are discouraged: every column is `summarizeBy: none`.
- **Real, derived and authored stay apart.** `Fact Outturn` and `Fact Plan` are real. `Fact Plan Phased (derived)` is
  labelled in its name, its description (which starts DERIVED) and a `Derived` display folder on every visible
  column, and carries `Is Derived` and the method on every row. The Spending Review Group, Plan Source and Plan
  Grain tables are authored names and descriptions with no amount. **Tested**: `sql/tests/706` (only the model's
  phased view reads the phased plan, and no view reads the phasing profile), `sql/tests/558` (nothing derived reaches
  a real total), `pipeline/tests/test_model_files.py::test_derived_and_real_tables_are_labelled`.

## The tables

Row counts are from `tests/results/700_row_counts.csv`, which the model returned and `ukfr dax-compare` matched to
the warehouse (**tested**: `evidence/model/dax_tests.csv`, test 700). SQL counts are from the full-scope database.

| Model table | Source | Rows | Class | What it is |
|---|---|---:|---|---|
| Fact Outturn | `dw.v_model_fact_outturn` | 658,554 | real | revision deltas of the 31 in-year releases |
| Fact Plan | `dw.v_model_fact_plan` | 5,372 | real | published plans at the grain of their source |
| Fact Plan Phased (derived) | `dw.v_model_fact_plan_phased` | 53,688 | **derived** | the plan spread over months by a stated rule |
| Fiscal Year | `dw.v_model_fiscal_year` | 12 | real | financial years 2017-18 to 2028-29; 2017-18 has plans and no outturn |
| Fiscal Period | `dw.v_model_fiscal_period` | 143 | real | year and period 0 to 12 |
| Release | `dw.v_model_release` | 31 | real | the OSCAR in-year releases |
| Scenario | `dw.v_model_scenario` | 5 | authored | Outturn, Plan, Plan (phased), Departments' forecast, Own forecast |
| Account | `dw.v_model_account` | 128 | real, with an authored flow and statement line | economic categories (127 and Unknown), each with the statement line it is added to |
| Control Budget | `dw.v_model_control_budget` | 6 | real | DEL, AME, Non-budget and the five detail codes |
| Sub-Segment | `dw.v_model_segment` | 3,766 | real | OSCAR sub-segments (3,765 and Unknown) |
| Organisation (as reported) | `dw.v_model_organisation` | 409 | real, authored keys | Type 2 organisation versions (408 and Unknown) |
| Department (current structure) | `dw.v_model_department` | 63 | real, authored names | live departments and the four Unallocated members |
| Spending Review Group | `dw.v_model_sr_group` | 32 | authored | the groups plans are published by |
| Plan Source | `dw.v_model_plan_source` | 17 | authored | each plan source and edition |
| Plan Grain | `dw.v_model_plan_grain` | 4 | authored | the four grains a plan is published at |
| Data Quality Issue | `dw.v_model_data_quality` | 10 | real findings | nine findings and the "No issue flagged" member |
| Statement Line | `dw.v_model_statement_line` | 39 | authored | the 39 lines of the group income and expenditure statement; no amount |
| Statement Measure | field parameter (calculated table) | 4 | authored | Outturn, Plan, Variance and Variance % of the statement amount; points at four measures |
| Time Intelligence | calculation group | 8 items | | Current, MTD, QTD, YTD, PY, YoY, YoY %, Rolling 12 months |
| Scenario Comparison | calculation group | 5 items | | Actual, Plan, Variance, Variance %, Favourable/Adverse |
| Display Unit | calculation group | 3 items | | GBP thousands, millions and billions |
| Deflator | web, see below | 229 | real | GDP deflators, three vintages, index and chained index |
| Deflator Quarantine | web | 0 | | deflator rows that failed to parse |
| CPI | web | 918 to September 2026; the web copy also held October 2026 on 18 November 2026 | real | ONS D7BT and D7G7, monthly |
| CPI Quarantine | web | 0 | | CPI rows that failed to parse |
| User Department (synthetic) | `dw.v_model_user_department` | 11 | **synthetic** | hidden: invented users and the departments each may see; the security roles read it, see [security.md](security.md) |
| User Plan Group (synthetic) | `dw.v_model_user_plan_group` | 10 | **synthetic** | hidden: the Spending Review groups whose plan each invented user may see, see [security.md](security.md) |

Subsets, each tested by `sql/tests/700` and DAX test 700: Fiscal Year is one row per financial year of
`dw.dim_period` and of the plan (FY2017-18 has OSCAR Plans and no calendar: the in-year releases start at FY2018-19); Department (current structure) is the 63 live members of `dw.dim_department` (a closed naming period,
13 of the 76, never receives a line in the current structure: `sql/tests/702`, `sql/tests/450`); Data Quality Issue is
`dw.dq_issue` plus the member with key 0. Department and organisation names are described in
[data-dictionary/organisation.md](data-dictionary/organisation.md) and
[data-dictionary/current-structure.md](data-dictionary/current-structure.md).

### What is hidden

Every surrogate key, every relationship column, the amount columns (`Amount Delta`, `Plan Amount`, `Phased Amount`),
the sort-key columns (`Year Start`, `Scenario Sort Order`, `Vintage Order`) and `Source Codes` are hidden
(**tested**: `test_keys_and_technical_columns_are_hidden`). A visible column always has a description. Sort-by columns:
`Financial Year` by `Year Start`, `Period` and `Month` by `Period Number`, `Release` and `Release Label` by
`Release Sequence`, `Scenario` by `Scenario Sort Order`, `Vintage` by `Vintage Order`. `Account` has a user hierarchy
(Economic Budget, PESA Economic Group, Economic Category).

### What I left out of the model, and why

| Warehouse table | Left out because | Which later page may need it |
|---|---|---|
| `dw.fact_outturn_annual` (97,250 rows, full scope only) | it is the restated annual file I use to check the current-structure mapping and the in-year totals; a model built on the committed scope could not load it | the restatements page and the data controls page, if they show the annual cross-check |
| `dw.outturn_plan_basis_inyear` (34,048) and `dw.outturn_plan_line` (101,675) | both regroup `Fact Outturn` to the plan's measures; the model can do the same with `Account[PESA Economic Group]`, `Control Budget` and `Spending Review Group`, and a second copy of the outturn would be a second source of the number (`sql/tests/556` proves the regrouping equals the fact) | none, unless a measure proves too slow |
| `dw.outturn_plan_basis_annual` (1,020, full scope only) | exact basis (ringfence column) exists only in the annual files | the plan variance page, if it wants the exact basis for year-end |
| `dw.plan_phasing_profile` (53,688) | the shares and the method are carried on every row of the phased plan | none |
| `dw.plan_coverage`, `dw.plan_measure_selection`, `dw.bud_group_current_department` | reference tables for the build and its audits | the coverage matrix of the data controls page |
| `dw.outturn_sr_group_bridge` | folded into `Fact Outturn` as `Spending Review Group Key` (one bridge row per organisation version and sub-segment, so no fact row is added or lost: `sql/tests/701`) | none |

## Relationships

23 relationships, all active, all many-to-one, all single direction (the one side filters the many side). There are
no inactive relationships and no bidirectional ones (**tested**:
`test_every_relationship_joins_existing_columns_and_is_active_single_direction_many_to_one`), the one side is always
a key column of a dimension (`test_the_one_side_of_every_relationship_is_a_key_column_of_a_dimension`), and no row of
the many side meets a blank member (**tested**: DAX test 701, 21 relationships, 0 rows without a member in each; the 22nd, Account to Statement Line, is
tested by `sql/tests/740`, which shows every account has one line, and by DAX test 741, whose statement total equals Outturn; the 23rd, File Control to Release, by `sql/tests/780` and DAX test 780).

| Many side | One side | Via |
|---|---|---|
| Fact Outturn | Release | release key |
| Fact Outturn | Organisation (as reported) | surrogate key of the version the release used |
| Fact Outturn | Department (current structure) | `current_department_key`, written in the warehouse |
| Fact Outturn | Sub-Segment | segment key |
| Fact Outturn | Account | account key |
| Fact Outturn | Control Budget | control budget key |
| Fact Outturn | Fiscal Period | period key (yyyypp) |
| Fact Outturn | Scenario | scenario key (always 1, Outturn) |
| Fact Outturn | Spending Review Group | key from the outturn-to-group bridge |
| Fact Outturn | Data Quality Issue | key of the finding, 0 for none |
| Fact Plan | Plan Source | plan source key |
| Fact Plan | Fiscal Year | financial year (text, 2024-25) |
| Fact Plan | Spending Review Group | group key |
| Fact Plan | Scenario | key of Plan |
| Fact Plan | Plan Grain | grain code |
| Fact Plan Phased (derived) | Fiscal Period | period key |
| Fact Plan Phased (derived) | Plan Source | plan source key |
| Fact Plan Phased (derived) | Spending Review Group | group key |
| Fact Plan Phased (derived) | Scenario | key of Plan (phased) |
| Fact Plan Phased (derived) | Plan Grain | grain code |
| Fiscal Period | Fiscal Year | financial year |
| Account | Statement Line | statement line key: the detail line of the statement the category is added to |
| File Control | Release | release key: one control row per release file |

The two role-playing organisation dimensions are both active on `Fact Outturn`: `Organisation (as reported)` on the
version the release used (so a department move or rename shows as it was reported), and `Department (current
structure)` on the department each line belongs to today. A line has exactly one current department; there is no
weighting. A plan is related only on the keys it has, which are coarser than an outturn line: group, source,
grain and year (or period for the phased plan). Outturn and plan share `Spending Review Group`, `Scenario` and the
year, so a comparison at group level needs no extra relationship. I did not relate `Fact Plan` to the organisation
dimensions, because a plan row of grain A carries an organisation code and an organisation version is not a code
(see below).

### What was awkward in the star schema

These are the places where the warehouse tables did not relate as they stood. I changed the view, not the
warehouse, in each case, and a later model task builds on the answer.

1. **Outturn had no Spending Review group.** The plan is published by group and the outturn has organisation and
   sub-segment, so a plan-to-outturn comparison needs one conformed group. `dw.outturn_sr_group_bridge` already maps
   each (organisation version, sub-segment) pair to a group; the view joins it and exposes `sr_group_key`. The group
   follows the line's current department, so a group comparison is on the current structure.
2. **The plan is published by financial year, outturn by period.** `Fact Plan.financial_year` is text; `dw.dim_period`
   has one row per period. I added `Fiscal Year` (one row per year, from `dw.dim_period`), related from both
   `Fiscal Period` and `Fact Plan`, so a year slicer filters outturn, plan and phased plan. The first version of the
   view held only the years of `dw.dim_period`, so the 898 OSCAR Plans rows of FY2017-18 had no year and sat under a
   blank member; test 701 reported it (`rows_without_member` 898) and passed because its expected value was computed
   the same way. The view now adds the years that only the plan has, and test 701 expects none.
3. **`fact_plan` has no scenario key.** The view adds the key of the `Plan` scenario by joining `dw.dim_scenario` on
   its name.
4. **`dq_issue_id` is nullable.** A nullable key adds a blank member to the relationship. The view writes
   NULL as 0 and `Data Quality Issue` has a member 0, "No issue flagged". **Tested**: `sql/tests/703`.
5. **Plan grain A carries an organisation code, not a version.** `Fact Plan[Plan Organisation Code]` is an OSCAR code
   (grain A only, to FY2021-22), and a code can belong to two durable keys over time (BIS084 is BEIS and then DSIT), so it
   cannot relate to the Type 2 `Organisation (as reported)`. It stays as an attribute of the plan; a grain-A comparison
   with outturn goes through the code and the guard that blanks a plan below its grain (`Plan.RowsInScope` and
   `Grain.BelowGrain`, below).
6. **`Fact Outturn.department_key` is not exposed.** The department as the release reports it is carried by the
   organisation version (one row, EHR030 in June 2019, is reported under a different department from its version's;
   it is the only difference). The department of a version is the column `Department (as reported)`.
7. **Closed department periods are not in `Department (current structure)`.** 13 of the 76 rows of `dw.dim_department`
   are closed naming periods that never receive a line; showing them would add members that are always empty.
8. **The deflator history is wider than the fiscal calendar** (1955-56 onwards against 2018-19 to 2028-29), and the
   ONS series reach back to 1988. A relationship to `Fiscal Year` or `Fiscal Period` would add a blank member, so
   neither is related; measures will reach them with `TREATAS`. **Tested**:
   `test_the_deflator_and_cpi_tables_are_not_related_to_anything`.

## Measures

Six base measures (the statement, restatement, structure and real-terms measures have their own sections), three calculation groups and twenty DAX
functions. They are written in TMDL (`functions.tmdl` and the
fact and calculation-group table files) and tested by DAX tests 720 to 737, each against a query over the `dw` base
tables (`docs/model-testing.md`). Amounts are GBP thousands, spending positive and income negative. Display folders:
`Base`, `Plan`, `Plan\Derived`, `Plan\Ranking`, `Restatement`, `Restatement\Excluding flagged rows`, `Current Structure` and `Real Terms`. Every measure has a description and a format string (**tested**:
`pipeline/tests/test_model_measures.py`).

**Where the measures live.** I put each measure on the fact table it sums, not on a measure-only table. A measure table
would be one more table with a placeholder partition, which the model's own file test (every SQL table reads one view,
the only other tables being the four web tables and the calculation groups) would have to make an exception for, and
it would add nothing the display folders do not. `Outturn` and the measures built on it are on `Fact Outturn`, the
plan measures on `Fact Plan`, and the one derived measure on the table that is labelled derived.

| Measure | Home | What it returns | Tested by |
|---|---|---|---|
| `Outturn` | Fact Outturn | the sum of the revision deltas of every release in context: the latest view of each financial year. It never filters releases, so a view as at a release is a selection on `Release`. All control budgets and economic categories | 720, 721, 727, 728 |
| `Plan` | Fact Plan | the published plan, summed over the plan rows in context, BLANK below the grain of the plan (the guard, below) | 722, 723, 724, 734 |
| `Plan (phased)` | Fact Plan Phased (derived) | **derived**: the same plan rows spread over periods 1 to 12 by the prior year's outturn; the only plan measure allowed at month grain; BLANK below the group grain and for FY2017-18 | 724, 725, 733 |
| `Outturn (plan basis)` | Fact Outturn | outturn on the basis of the plan rows in context (below); defined at every grain, including months | 726, 735, 736 |
| `Comparison Amount` | Fact Outturn | `Outturn (plan basis)`; the measure that the Scenario Comparison items act on | 729, 730, 731 |
| `Plan Below Grain` | Fact Plan | 1 where `Plan` is BLANK because of the guard, otherwise 0, so that a visual can say "not published at this level" | 723 |

`Plan (phased)` reads the plan rows that `Plan` adds up (it takes their `Plan Fact Key`s from the same function,
`Plan.RowsInScope`), so the twelve months add up to the published plan by construction. **Tested**: test 724 (year x
group, 270 cells, the phased sum equals `Plan`; FY2017-18 has `Plan` and no phased plan) and 725 (every month equals the
phased fact, and `Plan` is BLANK in all of them). Nothing derived reaches a real total: `Plan (phased)` is the only
measure that names `Fact Plan Phased (derived)` (`test_the_derived_phased_plan_is_read_by_one_measure_and_by_no_other`),
and test 733 shows `Outturn` and `Plan` equal to the sums of their own facts with the phased fact loaded, and BLANK under
the scenario `Plan (phased)`.

### The plan grain guard

`Grain.BelowGrain(allowMonth)` is written once. `Plan` calls it with `FALSE`, `Plan (phased)` with `TRUE` (a month is its
grain). A plan row is published at one of four grains (`Plan Grain`): A, OSCAR Plans to FY2021-22, by organisation x
control budget detail x economic budget x year; B, the Estimates from FY2023-24, by Spending Review group x resource DEL
excluding depreciation or capital DEL x year; C, FY2022-23 Estimates, the same with BEIS, DCMS and DIT as one group; D,
PESA departmental AME and administration, by group x measure x year. The guard returns BLANK when the filter context is
finer than that, or has a selection the plan cannot be cut by:

| Selection in the filter context | Plan |
|---|---|
| fewer fiscal periods than the years in context have (a month, a quarter, a window), or a rolling window | BLANK (`Plan (phased)` is allowed) |
| any Sub-Segment, Data Quality Issue or Department (current structure) | BLANK: the plan has no such key |
| any Account attribute finer than Economic Budget (category, PESA group, income or expenditure) | BLANK |
| any Organisation attribute finer than Organisation Code and Durable Key (the version name, department as reported) | BLANK: the plan is published by code, and a code can have more than one version in a year |
| Organisation Code, Control Budget (any column) or Account[Economic Budget], and every plan row in context is grain A | shown, and the plan rows are narrowed to the same codes (`Plan.RowsInScope`) |
| the same selections when any plan row in context is grain B, C or D | BLANK: those sources have no organisation, and carry no control budget or economic budget below `Plan Measure` |
| Release, Scenario, Plan Source, Spending Review Group, Fiscal Year, Plan Grain, and any column of Fact Plan | not a guard matter: they reach the plan, or do not change it |

A selection of every member does not count as a selection (`Grain.IsNarrowed` compares row counts), so a slicer with
"select all" does not blank the plan (**designed**: by construction of the row count, no test selects every member). Administration rows of grain D are part of resource DEL, so `Plan` leaves them out
unless a plan measure has been chosen; choosing `ADMIN` or `ADMIN_EX_DEPN` shows them on their own.

**Tested** (`tests/results/723_plan_grain_guard.csv`, matched to `tests/expected/723_plan_grain_guard.csv`): for 2019-20
(grain A) and 2024-25 (grains B and D) the number of non-blank cells of `Plan` is 0 at a month, a sub-segment, an economic
category, an organisation version, a department and a data quality issue in both years, and also at an organisation code,
a control budget detail and an economic budget in 2024-25; at its own grain it is the number of keys the plan has (237
organisation codes, 5 control budget details and 4 economic budgets in 2019-20). Test 734 compares all 881 cells of `Plan`
by organisation code x control budget detail x economic budget for 2019-20 with the plan fact.

### Outturn on the plan's basis

`Outturn (plan basis)` takes, for each (financial year, plan measure) that has a plan row in context, the outturn of the
lines that measure is made of, and adds them. Administration measures are left out unless chosen, as in `Plan`. The rules
(`Basis.OutturnFor`) are the seven of `dw.plan_measure_selection` and three of mine for the measures OSCAR Plans has
and that table does not define:

| Plan measure | Control budget detail | Economic budget | Depreciation |
|---|---|---|---|
| `RDEL` | DEL PROG, DEL ADMIN | RESOURCE | in |
| `RDEL_EX_DEPN` | DEL PROG, DEL ADMIN | RESOURCE | PESA economic group DEPRECIATION left out |
| `CDEL` | DEL PROG, DEL ADMIN | CAPITAL | n/a |
| `RAME`, `CAME` | DEPT AME | RESOURCE, CAPITAL | in |
| `ADMIN`, `ADMIN_EX_DEPN` | DEL ADMIN | RESOURCE | in; DEPRECIATION left out |
| `NON_DEPT_AME` (mine) | NON-DEPT AME | any | n/a |
| `NON_BUDGET` (mine) | NON-BUDGET | any | n/a |
| `UNCLASSIFIED` (mine) | DEL PROG, DEL ADMIN, DEPT AME | neither RESOURCE nor CAPITAL | n/a |

A selection already in the filter context on those columns is kept (`KEEPFILTERS`), so a slicer can only narrow the basis.
**Tested**: 726 compares 844 (year, group, measure) cells of the first seven measures with `dw.outturn_plan_basis_inyear`
at the closing release of the year; 735 compares 69 cells of my three with the outturn fact joined to its dimensions; 736
compares 88 (year, group) cells with no measure chosen with the same table summed over the measures present, administration
left out.

**Where the basis and the plan do not match.** The in-year files have no ringfence column, so `RDEL_EX_DEPN` drops only the
economic group DEPRECIATION and other non-cash items stay in. The exact basis is in the annual files, which the model does
not load (`dw.outturn_plan_basis_annual`, full build only). The gap between the model's in-year figure at the year end and the
latest annual figure, at total level (GBP thousands, `audit.plan_basis_inyear_vs_annual`, full build):

| Year | Measure | In-year (the model) | Annual | Gap | Published plan |
|---|---|---:|---:|---:|---:|
| 2023-24 | RDEL excluding depreciation | 447,002,390 | 447,960,340 | -957,950 (-0.21%) | 449,138,946 |
| 2023-24 | CDEL | 105,453,523 | 104,115,801 | 1,337,722 (1.28%) | 110,658,280 |
| 2024-25 | RDEL excluding depreciation | 485,030,362 | 479,535,153 | 5,495,209 (1.15%) | 487,520,000 |
| 2024-25 | CDEL | 109,421,673 | 108,965,819 | 455,854 (0.42%) | 114,587,000 |

By group the gaps are larger. They are now traced (`audit.plan_variance_reconciliation`, section 9 of `docs/reconciliation.md`): the
"about 1% of non-cash items" I first wrote is not non-cash. The ringfenced categories all sit in the DEPRECIATION group, which the model drops, so the ringfence
basis is reproduced; the 5.5bn gap from 2024-25 is Home Office fee income (category T302) that the in-year files lack, and Scotland's 11.0bn in
2022-23 and 2023-24 is the block grant adjustment (the in-year files are net of it). The model does not test equality with the annual table because the two are different
vintages of different files: the test I can make is that the model equals the in-year table exactly, and the gap above is
reported, not hidden.

**The plan variance and what it is compared with.** A plan variance in the headline is for resource DEL excluding depreciation and capital DEL, the voted limits; the report
filters `Fact Plan[Plan Measure]` to those two. Departmental AME is a forecast (PESA), the in-year outturn of AME is a first look without the year-end provisions,
impairments and pension entries, and PESA 2026 puts the ringfenced depreciation in AME, so an AME variance is not an underspend: it is reconciled in `Plan Variance Check`, not
added to the headline. The headline variance moved from -8.5% to -1.3% in 2025-26 (**tested**: DAX tests 788 and 801). For FY2022-23 the plan is published for BEIS, DCMS
and DIT as one group, so `Fact Outturn[Spending Review Group]` for the outturn of the departments 013, 048 and 084 as reported in that year is the combined group
(`dw.plan_group_rule`, `sql/tests/800`); in every other year it is the current-structure group of the bridge.

At grain A the plan is published by OSCAR group names, and the outturn reaches a group through the current department. A
comparison by group in FY2017-18 to FY2021-22 therefore mixes two structures; the comparison that is on one structure is by
organisation code (tests 729 to 731 are cells of that kind).

## Calculation groups

Three groups, each a table with one column. Precedence is **Display Unit 30 > Time Intelligence 20 > Scenario Comparison
10**, a higher number being the outer wrapper. So a unit is applied last to whatever the time item gives; the time item
wraps the comparison item; and "Variance % of YTD" is the variance of the year-to-date amounts as a percentage of the
year-to-date plan, not a year to date of percentages. The reverse order cannot work: a comparison item that reads `[Plan]`
by name is not wrapped by an item of a lower-precedence group. **Tested** with every combination of the other two groups
(tests 730 and 737).

### Time Intelligence

Windows are sets of Fiscal Period rows (`Window.*`); there is no date table and no calendar function (**tested**:
`test_the_calendar_time_intelligence_functions_are_not_used_anywhere`). Period 0 holds amounts the source does not
allocate to a month; it counts in the year, the year to date and the previous year, and is never a month.

| Item | What it does |
|---|---|
| Current | the measure in the period context of the visual |
| MTD | the latest allocated month (period 1 to 12) in context, in each year in context; BLANK with only period 0 |
| QTD | the months of that month's fiscal quarter up to it (April to June is quarter 1, derived from the month) |
| YTD | period 0 to the latest period in context, in each year; at period 12 it is the year total |
| PY | the same periods one financial year earlier (the year selection moves too, so the plan moves with it) |
| YoY | current less PY; BLANK without a previous year |
| YoY % | YoY over the absolute PY |
| Rolling 12 months | the 12 allocated months ending at the latest allocated month in context, crossing financial years; period 0 is not a month and is not in it |

Each window is evaluated once over the periods of every year in context, so a ratio is computed from summed parts at a
total. This assumes that the years in context have the same period selection; a visual that selects different periods in
different years is not designed for and I did not test it. **Tested**: test 727 (three years, two departments, year grain, 42
cells; 2018-19 has period 0 and no previous year) and 728 (the same at month grain, 504 cells, period 0 as a row of its
own, the rolling window across the year boundary) match T-SQL window functions over a grid of every period.

### Scenario Comparison

The items act on `Comparison Amount` only; any other measure passes through unchanged.

| Item | What it does |
|---|---|
| Actual | `Outturn (plan basis)`. I chose it over `Outturn` so that Actual, Plan and Variance in one row are on one basis: Variance would not equal Actual less Plan if Actual held every control budget and Plan only DEL |
| Plan | `Plan` (BLANK below its grain) |
| Variance | Actual less Plan; BLANK when either is BLANK |
| Variance % | Variance over the absolute Plan; BLANK when the plan is zero or either is BLANK |
| Favourable/Adverse | a signed indicator: 1 favourable, -1 adverse, 0 on plan, BLANK without a variance |

**The sign convention.** OSCAR has spending positive and income negative, so Actual less Plan below zero is favourable for
both: spending under plan is below zero, and more income than planned is more negative. The percentage divides by the
absolute plan so that it keeps the sign of the variance. Favourable/Adverse is a number, not text, so that a report can
colour by rule and so that the column does not mix types; its format string prints the words. **Tested**: the four cases,
each a real OSCAR Plans cell found by `sql/tests/720` (full build), by DAX test 729:

| Case | Cell (year, organisation code, resource DEL) | Plan | Actual | Variance | Variance % | Indicator |
|---|---|---:|---:|---:|---:|---:|
| spending under plan | 2019-20, DFE022 (Department for Education) | 79,321,161 | 68,962,049 | -10,359,112 | -13.06% | 1 |
| spending over plan | 2019-20, HOF034 | 11,253,637 | 11,418,321 | 164,684 | 1.46% | -1 |
| income above plan | 2019-20, XXX022 (DfE Grants to Academies Offset, a body whose plan is income) | -22,845,405 | -22,888,692 | -43,287 | -0.19% | 1 |
| income below plan | 2020-21, XXX022 | -25,298,822 | -25,244,273 | 54,549 | 0.22% | -1 |

**Combinations.** Test 730 evaluates all 40 combinations of the time items and the comparison items for the 2020-21
DFE022 cell and compares each with a rule written out in SQL. The rules it proves: at a whole year Current and YTD give the
year and PY the year before, with Plan, Variance, Variance % and the indicator present; MTD, QTD and Rolling 12 months give
Actual and BLANK for everything that needs a plan (a window is never a published plan period; the year to date at period 12
is the whole year, so it has one); YoY and YoY % are differences of Actual, Plan and Variance and are BLANK for Variance %
and Favourable/Adverse, where a difference or a percentage change of two ratios or two indicators means nothing. 16 of the
40 cells are BLANK on purpose.

### Display Unit

The data is in GBP thousands, and a number format that scales with commas prints a wrong number on the canvas in this Desktop
build, so I scale the value: `£k` (no change), `£m` (divided by 1,000), `£bn` (divided by 1,000,000), each with a dynamic
format string carrying the suffix (`£1,234k`, `£1,234.5m`, `£1.23bn`, negative with the sign before the pound). The unit
acts on the five amount measures and not on a percentage or an indicator (`Format.ValueKind`). The scaled value is held at
four decimals, so `£bn` resolves to GBP 100,000. When a unit is selected its format string is the one in force, so it also
gives Variance %, YoY % and Favourable/Adverse their formats (a percentage with one decimal; the words Favourable, Adverse
and On plan); with no unit selected the format strings of the comparison and time items apply.

**Tested.** The values: test 731 (every comparison item under all three units for one cell) and 737 (every time item under
all three units). The format string expressions: test 732 compares what `Format.ForUnit` returns for all 40 combinations and
three units with the rule. **The engine applies them**: `tools/run_mdx.ps1` ran `tests/mdx/format_strings.mdx` against the
open model and wrote what the engine formatted, for 100 cells (every comparison item, five time items, all three units and no
unit): [evidence/model/format_strings.csv](../evidence/model/format_strings.csv) (pound signs written as GBP). For example
`GBP m | PY | Plan` is `GBP 79,321.2m`, `GBP bn | YoY % | Variance` is `6.9%` and every `Favourable/Adverse` cell reads
`Favourable`. I did not look at these on a report canvas, because there are no report pages yet.

### Functions

| Function | Used by |
|---|---|
| `Grain.IsNarrowed`, `Grain.BelowGrain` | the guard, in `Plan`, `Plan (phased)` and `Plan Below Grain` |
| `Plan.RowsInScope` | the plan rows `Plan` and `Plan (phased)` add up |
| `Basis.OutturnFor`, `Basis.HasRule` | `Outturn (plan basis)` |
| `Window.OverPeriods`, `Window.Mtd`, `Window.Qtd`, `Window.Ytd`, `Window.PriorYear`, `Window.Rolling12` | the Time Intelligence items |
| `Format.ValueKind`, `Format.Scale`, `Format.ForUnit` | the Display Unit items |
| `Pnl.SignFactor`, `Pnl.LineAmount`, `Pnl.AtPlanScope` | the statement measures (the namespace is `Pnl` because `Statement` is rejected by the DAX parser, below) |
| `Restate.Unflagged` | the excluding-flagged-rows variants of the gross restatement measures, and the stated pattern for any other measure |
| `Real.IndexTable`, `Real.Deflate` | the seven real-terms measures (above) |

A function name with a dot must be quoted in `functions.tmdl` (`function 'Grain.BelowGrain' =`); unquoted, Desktop reads
the dot as a namespace and the function loses its prefix, and every call fails to resolve (**tested**:
`test_every_function_name_is_quoted_in_the_file`). They are called unquoted in DAX.

### Query timings

`dscmd benchmark` on the open model, 3 cold and 3 warm runs of the test queries, average total duration in milliseconds
(printed by `tools/run_dax.ps1 -Benchmark -Cold 3 -Warm 3`; the output is not committed): test 722 (387 cells of `Plan`)
18.3 cold and 12.7 warm; test 726 (844 cells of `Outturn (plan basis)`) 82.3 and 48.0; test 728 (504 time-intelligence
cells) 105.7 and 86.7; test 723 (the guard at 26 cells, 136 storage-engine queries) 232.7 and 198.3; test 730 (the 40 combinations of
one cell: 1,025 storage-engine queries) 3,177 and 3,168, of which about 2.9 s is formula engine, so roughly 80 ms for a
combination that needs a plan. That is the cost to watch on a matrix of comparison items, and the guard (about a dozen
row counts per call) is where I would look first; I have not profiled a page or tried to reduce it. These are the test
queries only.


## Real terms

Seven measures give an amount in 2025-26 prices. Each is the nominal measure with `(real terms)` after its name, in the same
table and in the display folder `Real Terms`, and each is one line, `Real.Deflate ( [<name>] )`. The seven are `Outturn`,
`Plan`, `Plan (phased)`, `Outturn (plan basis)`, `Outturn (current structure)`, `Statement Amount` and `Statement Plan`. They are
written by `te/scripts/real_terms_measures.csx` from a list at the top of the script, so a new one is one name added to the
list. The phased twin starts its description with DERIVED, because the phased plan is my allocation.

**The rule.** `Real.Deflate ( m )` takes the financial years in context (`'Fiscal Year'[Financial Year]`), evaluates `m` for each
year, multiplies each year's amount by the index of 2025-26 divided by the index of that year, and adds the years. The index is
the `Chained Index` of the default vintage of the `Deflator` table (October 2026 Budget): the published index for an outturn
year, and for a forecast year the level chained from that one vintage, so two vintages are never mixed. `Real.IndexTable` finds
the indices; `Deflator` is related to nothing and stays that way, so the years are matched with `TREATAS`. A month takes the
index of its financial year (there is no monthly deflator). A year that has an amount and no index makes the result BLANK,
never the nominal figure, and so does a total over several years that includes such a year, because a partial sum in real terms
would be wrong. Every financial year of the model (2017-18 to 2028-29) has an index in the default vintage and in the other two
(they run to 2030-31), so BLANK happens only when I make a gap, which test 776 does.

**What the calculation groups do with them.** Display Unit lists the seven measures in its items by name, so £k, £m and £bn scale
them like their nominal twins (**tested**: test 775). Time Intelligence acts on them like any amount: `PY` is the same period of
the previous financial year in 2025-26 prices (each year deflated with its own index), `YoY` is the real change, `YoY %` the real
growth rate. For the Department of Health and Social Care, period 6 of 2023-24, test 775 gives a real amount of 15,625,102.8
(thousands of pounds) against 17,640,143.6 for the same period of 2022-23, a real change of -2,015,040.8 and a real growth of
-11.4%. Scenario Comparison does not act on the real-terms measures (it acts on `Comparison Amount` and `Statement Amount` only),
so there is no real-terms variance item; two real-terms measures can be subtracted in a visual.

**Tested** (`tests/results/770_*.csv` to `776_*.csv` against `tests/expected/`, written independently by `tests/expected/77x_*.py`:
the amounts through SQL over `dw`, the index from the pinned October 2026 Budget workbook through `ukfr.readers.deflators`):

| Test | What it proves | Rows | Largest difference |
|---|---|---:|---:|
| 770 `real_terms_outturn_by_year` | `Outturn (real terms)` by year, with the nominal figure and the index the model read over the web | 12 | 0.000049 |
| 771 `real_terms_plan_by_year_source` | `Plan (real terms)` by year and plan source | 17 | 0.000050 |
| 772 `real_terms_outturn_by_year_department` | `Outturn (real terms)` by year and department, every cell | 537 | 0.000050 |
| 773 `real_terms_2025_26_is_nominal` | in 2025-26 all seven twins equal their nominal measure exactly (difference 0) and none is blank | 7 | 0 |
| 774 `real_terms_statement_total_equals_outturn` | the total line of the statement in real terms equals `Outturn (real terms)` in all nine years | 9 | 0.000049 |
| 775 `real_terms_under_time_and_unit` | Current, YTD, PY, YoY, YoY % under £k, £m and £bn, one department and period | 15 | 0.000052 |
| 776 `real_terms_year_without_index_is_blank` | a year with an amount and no index gives BLANK, and so does a total that contains it | 4 | 0.000030 |

The differences are the four-decimal rounding of the measure's result (a fixed decimal), against an exact Decimal calculation in
Python. Three years of test 770 (thousands of pounds; the index is 2025-26 = 100):

| Year | Nominal | Index | Real in the model | Expected | Difference |
|---|---:|---:|---:|---:|---:|
| 2018-19 | 749,955,441 | 76.2884 | 983,053,047.3834 | 983,053,047.3833505 | 0.0000495 |
| 2023-24 | 1,160,485,035.6297 | 93.1026 | 1,246,458,246.7404 | 1,246,458,246.7403703 | 0.0000297 |
| 2025-26 | 1,293,643,283.2744 | 100 | 1,293,643,283.2744 | 1,293,643,283.2744 | 0 |

Test 776 makes its gap with a filter on `Deflator[Financial Year]` that removes 2024-25. `Real.IndexTable` honours a filter on that
column and ignores every other filter on `Deflator`, so the vintage stays the default one; a slicer on the year of `Deflator` on a
report would therefore blank the real-terms measures for the years it hides, which I would not put on a page. A query-scoped
`DEFINE FUNCTION` that redefines `Real.IndexTable` was accepted by the engine and ignored by the model's measures, so I did not use it.

**Cost.** `dscmd benchmark`, five cold and five warm runs on the open model (`evidence/perf/real_terms/summary.csv`, written by
`tools/summarise_benchmarks.py`): `Outturn` by year and department (537 cells) 10 ms cold and 7 ms warm; the same cells of
`Outturn (real terms)` 18 ms cold and 17 ms warm, with 7 storage-engine queries against 1, because each of the twelve years is
evaluated on its own; `Outturn (plan basis)` by group and measure (844 cells) 77 and 47 ms; test 775 (the time items with three units)
378 and 373 ms. These are the test queries, not a page.

## The group income and expenditure statement

The statement treats central government as one group: income, expenditure by kind, net expenditure for resource and for
capital, and a total that equals the outturn. The layout and the rules that map an account to a line are authored files
(`authored/statement_line.csv`, `authored/statement_account_rule.csv`), described with the judgements the account dimension
forced in [data-dictionary/statement.md](data-dictionary/statement.md). A line is a row of `Statement Line` (39 rows: 28
detail lines, 7 subtotals, 1 total, 3 spacers); `Account` is related to it, so a detail line filters the accounts it adds
up and, through them, the outturn.

### Measures

| Measure | Home | What it returns | Tested by |
|---|---|---|---|
| `Statement Amount` | Fact Outturn | the outturn of the statement line in context, in the sign the line is presented in; BLANK for a spacer and when more than one line is in context | 740 to 745, 746 to 749, 751, 752 |
| `Statement Plan` | Fact Plan | the plan of the line, only on the net resource, net capital and total lines and only where the source publishes a plan at that level | 740, 744, 745, 751 |
| `Statement Amount (plan basis)` | Fact Outturn | where the line has a plan, the outturn on the plan's basis within the line's economic budget; BLANK otherwise | 740, 744 |
| `Statement Variance`, `Statement Variance %` | Fact Outturn | the basis amount less the plan, and over the absolute plan | 744, 745, 751 |
| `Statement Amount PY (OFFSET)` | Fact Outturn | the amount of the previous row of `Fiscal Year`, by `OFFSET` | 746 |
| `Statement Amount Running (WINDOW)` | Fact Outturn | the amount from period 0 to the period in context within each year, by `WINDOW` | 747 |
| `Statement Amount Moving 3 Months (WINDOW)` | Fact Outturn | the month and the two before it, across years, by `WINDOW`; period 0 is BLANK | 748 |
| `Department Rank (Statement Amount)` | Fact Outturn | the rank of the department among those with an amount, by `RANK` | 749 |

Display folders: `Statement` and `Statement\Windows`. Every measure has a description and a format string
(**tested**: `pipeline/tests/test_model_measures.py`).

### How a line is evaluated

`Pnl.LineAmount(m)` takes the one statement line in context and the hidden column `Detail Line Keys` (the detail lines it
adds up, written `|3|4|5|`, resolved in SQL), removes the filter on `Statement Line`, filters it to those detail lines
with `TREATAS`, evaluates `m` (the outturn), and multiplies by the sign the line is presented in. So a detail line sums
its accounts and a subtotal or total sums the detail lines under the lines it lists: a total equals the sum of its
members by construction, a line is never built from other presented numbers, and a spacer, or a context with several
lines, has no single line and gives BLANK. I put the list of detail lines on the line itself and not in a member table:
one table, one relationship, and the list is built and checked in SQL (`dw.statement_line_member`, whose `path_count` is
1 everywhere, so no amount is added twice).

**Tested.** Test 740 compares `Statement Amount`, `Statement Plan` and `Statement Amount (plan basis)` for every line and
every year (329 rows, largest difference 0). Test 741 shows the total line, `Outturn` and the sum of the detail lines (each
sign undone) are the same number in all 9 years with outturn. Test 742 splits six lines by control budget (DEL, AME,
Non-budget), 2019-20 and 2024-25 (34 cells).

### The plan on a statement line

The published plan has no account, so only the lines that coincide with what a plan is published on carry one: net
resource expenditure (the economic budget RESOURCE), net capital expenditure (CAPITAL) and the total (every account).
`Pnl.AtPlanScope(m)` sets the economic budget as a direct filter on `Account`, so the existing grain guard sees a
selection at its grain: it leaves the plan in place in an OSCAR Plans year (published by economic budget) and blanks it in
a year whose source (Estimates, PESA) has no economic budget. The plan measures compared are the five voted budgets only
(RDEL, RDEL excluding depreciation, CDEL, departmental AME resource and capital); administration, non-departmental AME,
non-budget and unclassified are left out, because the OSCAR non-budget plan is gross and the outturn is net (the reason
and the figures are in the data dictionary). A statement line with no plan is BLANK in `Statement Plan`, not zero.

### Calculation groups on the statement

`Scenario Comparison` acts on `Comparison Amount` and now also on `Statement Amount`; every other measure passes
through. On `Statement Amount` the items are:

| Item | What it gives |
|---|---|
| Actual | the amount on the plan's basis where the line has a plan, the statement amount itself everywhere else |
| Plan | `Statement Plan` |
| Variance, Variance % | `Statement Variance`, `Statement Variance %` |
| Favourable/Adverse | 1 below zero, -1 above, 0 at zero, on the variance with the presentation sign taken off |

`Time Intelligence` acts on any measure, so YTD, PY, YoY and the rest work on `Statement Amount` unchanged, and
`Display Unit` scales the statement measures that are amounts (not `Statement Variance %`). **Tested**: test 743
(Current, YTD, PY and YoY on four lines, two years, every period, equal to T-SQL window functions; 384 cells), test 744
(the five comparison items with Current, YTD and PY, four lines, two years; 72 cells), test 745 (three units; 33 cells).

### Window functions and rank

- `Statement Amount PY (OFFSET)` takes the previous row of `Fiscal Year` in order of year start, whatever a slicer selects;
  it is for year grain. The time item PY does the same through a different route and also moves the plan.
- `Statement Amount Running (WINDOW)` and `Statement Amount Moving 3 Months (WINDOW)` need `Fiscal Year[Financial Year]` and
  `Fiscal Period[Period Number]` on the visual. The running total restarts every year and includes period 0; the moving
  window is over the allocated months of every year in order, so April of a year takes in the last two months of the year
  before, and period 0 is BLANK and in nobody's window.
- `Department Rank (Statement Amount)` ranks over `ALLSELECTED` of the whole `Department (current structure)` table.
  My first version ranked over `ALLSELECTED` of the key column only and every department came out first: a group-by
  on another column of the same table (the number) stays in the context of `ALLSELECTED` on a column, so the relation had
  one row (found by test 749, which returned 1 where SQL had ranks such as 10, 12 and 23). Over the whole table it matches `RANK()` in T-SQL.

**Tested**: tests 746 (40 cells), 747 (50), 748 (74), 749 (171) equal `LAG`, `SUM() OVER`, a three-row moving
`SUM() OVER` and `RANK() OVER` in T-SQL (`tests/expected/746` to `749`, largest difference 0).

### The field parameter

`Statement Measure` is a calculated table of four rows (Outturn, Plan, Variance, Variance %) with `NAMEOF` references to
`Statement Amount`, `Statement Plan`, `Statement Variance` and `Statement Variance %`, and the metadata (`ParameterMetadata`
version 3, kind 2) that makes Desktop treat it as a field parameter. **Tested**: test 750 (the four rows, the measure each
points at and the order, equal to the intended rows) and test 751 (each of the four values returns its measure on two
real cells, switching on the parameter's own order column; 8 cells equal SQL). **Not tested**: a visual that uses the
parameter. `pbir` 0.9.33 cannot put a field parameter on a visual (it writes a plain column), so a report that wants
it needs one manual step in Desktop (remove the field from the visual and drag the parameter back in, Save, review the
diff). I would rather the report page use the `Scenario Comparison` items, which need no manual step.

### Two names the DAX parser refuses

- A function called `Statement.SignFactor` is a syntax error ("The syntax for 'Statement' is incorrect") from a query
  and from a measure, and the model then fails to refresh; `Statement` is not usable as a namespace on this engine. The
  functions are `Pnl.*`. A call to a function that does not exist
  gives "Failed to resolve name" instead, so the name itself is the problem; renaming the namespace to `Pnl` cleared it. I
  did not look for the reserved word in the language reference.
- A variable called `Path` is a syntax error in a function body (`PATH` is a function). I called it `KeyList`.

### Tests

| Test | What it proves | Rows | Expected values from |
|---|---|---:|---|
| 740 `statement_by_line_year` | `Statement Amount`, `Statement Plan`, `Statement Amount (plan basis)`, every line and year | 329 | `dw.v_statement_pnl` |
| 741 `statement_total_equals_outturn` | the total line, `Outturn` and the sum of the detail lines are one number per year | 9 | `dw.fact_outturn` |
| 742 `statement_by_control_budget` | six lines split into DEL, AME, Non-budget | 34 | the fact through the statement tables |
| 743 `statement_time_intelligence` | Current, YTD, PY, YoY at month grain | 384 | T-SQL window functions |
| 744 `statement_comparison_and_time` | the five comparison items with Current, YTD, PY | 72 | `dw.v_statement_pnl`, `LAG` |
| 745 `statement_display_unit` | three units against the comparison items | 33 | `dw.v_statement_pnl` |
| 746 `statement_previous_year_offset` | `OFFSET` | 40 | `LAG` |
| 747 `statement_running_total_window` | `WINDOW`, running total | 50 | `SUM() OVER` |
| 748 `statement_moving_three_months_window` | `WINDOW`, three months across years | 74 | `SUM() OVER` |
| 749 `statement_department_rank` | `RANK` | 171 | `RANK() OVER` |
| 750 `statement_measure_parameter_rows` | the field parameter's rows and targets | 4 | the intended rows (Python) |
| 751 `statement_measure_parameter_values` | what each parameter value returns | 8 | `dw.v_statement_pnl` |
| 752 `statement_spacers_and_labels` | a spacer is BLANK and its label is distinct | 39 | the layout table |

**Timings** (`tools/run_dax.ps1 -Benchmark -Cold 3 -Warm 3` on the open model, average total duration in milliseconds,
cold then warm; the tool's output is not committed, these are the figures it printed): test 740 (329 cells, all lines and
years) 302.3 and 250.0; 741 (9 cells) 52.3 and 56.3; 742 (34 cells) 43.7 and 33.0; 743 (384 cells of Time Intelligence on
four lines) 211.3 and 131.7. I benchmarked only these four, and the warm figure is not always the smaller one, so I read
them as "a few hundred milliseconds for the whole statement" and not as a measurement of caching. I did not profile the
`WINDOW`, `OFFSET` or `RANK` measures or a report page.

## Restatement: how a figure changed from release to release

`Fact Outturn` holds the change each release made to each line and month (the revision delta). `Outturn` is a plain sum of
those deltas, so with nothing selected on `Release` it is the latest view of every year, and with one release selected it is
only that release's delta, not the figure as at it. The restatement measures add what a restatement page needs: the figure
as a release stated it, the figure as first reported, the difference, and the part of a release's change that restates
what an earlier release had already reported. They live on `Fact Outturn` in the display folder `Restatement`.

### The as-at rule

**The as-at release is the highest `Release Sequence` in context, or the latest release when none is selected.** The
measures `Outturn as at Release`, `Outturn as First Reported`, `Revision since First Reported` and `Revision %` all use it.
`Outturn as at Release` is the sum of the deltas of every release up to and including that one, for every financial year
in context. So for the release of December 2023 the year 2023-24 is what that release reported (and equals its file total),
the earlier years are the last figure known at that release, and the years after it are BLANK. It is written as
`CALCULATE ( [Outturn], REMOVEFILTERS ( 'Release' ), 'Release'[Release Sequence] <= AsAt )`. The form a report author would
write first, `CALCULATE ( [Outturn], FILTER ( ALL ( 'Release' ), 'Release'[Release Sequence] <= AsAt ) )`, is kept as the hidden
measure `Outturn as at Release (naive)` in the display folder `Performance\Naive`, so that the comparison in
`docs/performance.md` can be rerun; the two return the same figures (tests 810 to 812).

**Tested** (`tests/dax/760_as_at_release_equals_file_total.dax`, result
[tests/results/760_as_at_release_equals_file_total.csv](../tests/results/760_as_at_release_equals_file_total.csv)): for each
of the 31 releases, on that release's own financial year, `Outturn as at Release` equals the four-decimal total of the
release's file in `audit.file_control` (the control totals loaded from `data/audit/inyear_file_control_totals.csv`), with a
largest absolute difference of 0 (`evidence/model/dax_tests.csv`). The expected side reads `audit.file_control` and not
`dw.fact_outturn`. The same check by department of the current structure at four releases (237 cells, test 761) equals
`SUM` of the deltas in T-SQL.

### The measures

| Measure | What it returns | Tested by |
|---|---|---|
| `Outturn as at Release` | the figure the as-at release stated (above) | 760, 761, 762, 769 |
| `Outturn as First Reported` | the deltas with `Revision Number` 0 up to the as-at release: each line and month at the amount of the release that first reported it. A line first reported later counts at its first amount, so this is not the total of the first release of the year | 762, 769 |
| `Revision since First Reported` | as at less first reported, which is the sum of the deltas with `Revision Number` above 0 up to the as-at release. BLANK when neither side has a value, 0 when nothing was restated | 762, 769 |
| `Revision %` | the revision over the absolute first-reported amount; BLANK when that is 0 | 762, 769 |
| `Revision in Release` | the change the release or releases in context made to the year-to-date outturn: the sum of their deltas, which is what `Outturn` shows with `Release` on rows. It mixes months reported for the first time with restatements | 762 |
| `Restatement in Release` | the part of it that changes a figure an earlier release had already reported: the deltas with `Revision Number` above 0 | 762 |
| `Gross Revision in Release`, `Gross Restatement in Release` | the sum of the absolute deltas of the same two sets, so that increases and decreases do not net off | 762, 763 |
| `Gross Revision in Release (excl. flagged)`, `Gross Restatement in Release (excl. flagged)` | the two gross measures with the rows flagged in `Data Quality Issue` left out (below) | 763 |

Two judgements. First, `Revision in Release` is the movement measure I set out to build (a plain sum named so that it cannot be mistaken for
a total), but on its own it is not a restatement: a delta with `Revision Number` 0 is a month or line reported for the first
time, and in the first release of a year everything is. In the 31 releases the first release of each year has 0 rows with a
revision number above 0 and 14,565 to 47,258 rows with 0 (query on `dw.fact_outturn`). A restatement page should therefore
show `Restatement in Release` and `Gross Restatement in Release`, and use `Revision in Release` for the movement of the
year-to-date total. Second, the as-first-reported figure is a sum of first amounts by line and month, not "the first
release's total", because a line can first appear in any release of the year; the revision is therefore the part that was
reported and later changed, and it is the same whichever release first reported a line.

**Tested**: test 762 (six releases at their own financial years by department, 356 cells, largest difference 0.000001)
compares eight measures with T-SQL window functions (`SUM() OVER` over a grid of every release, with `revision_no = 0` for
first reported). For the Department of Health and Social Care (033), the results file shows for the year-end release of
June 2026 (2025-26): as at 229.2bn, first reported 229.1bn, a revision of +85m (+0.04%); for December 2023, 97.47bn against
97.46bn first reported (`tests/results/762_revisions_by_release_department.csv`).

### Rows flagged in Data Quality Issue

`dw.dq_issue` flags thirteen fact rows: the delta rows of three line-months of the NHS Pension Scheme line `NHP903 X903A002`
(April and May 2023, reported in September 2023 and corrected in December 2023, and April 2025, reported in September 2025
and corrected in March 2026), which a release reported about 1,000 times too large and a later release corrected (six rows), and
of the same three line-months of its offsetting line `X903A003` (seven rows). `Restate.Unflagged ( m )` is the stated pattern for leaving
them out: it evaluates a measure with `KEEPFILTERS ( 'Fact Outturn'[Data Quality Issue Key] = 0 )`, where key 0 is the member
"No issue flagged". Test 763 shows it removes exactly the thirteen rows' amounts: the as-at figure falls by the flagged deltas up
to the release and the gross measures by the flagged absolute deltas of the release, in every one of the 31 releases (largest
difference 0).

**The offsetting line.** The scheme records a transaction on two lines of opposite sign, so the error is on both: in
September 2023 `X903A002` held `4,100,000,000` and `X903A003` held `-4,101,533,695` for April 2023. The first rule flagged only
`X903A002`, because the amount `X903A003` keeps after the correction is a factor of 125, 722 and 833 below the amount it was
reported at, and the rule looks for 900 to 1,100. Rule a now also flags a line of the same organisation, economic category, control
budget and month whose change between the same two releases is the opposite of a flagged line's change, within 1% of its size
(issue type "unit error (offsetting line)"). **Tested**: `sql/tests/762_the_unit_error_and_its_offsetting_line_are_both_flagged.sql`
(each unit error has an offsetting-line finding in the same pair and month, with the opposite change within 1%; thirteen flagged
rows, six on `X903A002` and seven on `X903A003`) and `sql/tests/309` (three findings on each line, in two release pairs, and nothing
else). Which rows are flagged also changed: a flagged line-month now has every delta row from the one that set the wrong amount (the
delta row of largest absolute size at or before the first release of the pair) to the one that corrected it. That adds one row, the
small revision of `X903A003` for April 2025 in December 2025, which sits between the row that set the amount and the row that corrected
it. No amount in the warehouse moved: flags annotate and remove nothing (`evidence/expected/real_fact_totals.csv` is unchanged).

What that gives, in `tests/results/763_data_quality_exclusion_by_release.csv` (GBP thousands):

- **Net measures need no exclusion.** The flagged line and its offsetting line net to a small amount, so `Revision since First
  Reported` and `Outturn as at Release` are not distorted by the error, and the as-at figure with both lines left out differs
  from the unfiltered figure only by the genuine amounts the offsetting line carried (`removed_as_at` of -3,033,648 in September 2023,
  -1,347,585 in December 2025). That is why there are no excluding variants of the net measures and why the pattern is a function and not
  a set of measures.
- **Gross measures are inflated by both lines, and the excluding variant now removes both.** The gross restatement of December 2023 is
  8,645,154,822, and 13,885,737 when the flagged rows are left out; with both lines left out by sub-segment (the column
  `gross_restatement_without_pair` of the same file) it is 13,849,824, in line with the neighbouring releases. The difference is the
  genuine small amounts of the offsetting line in the flagged months. March 2026 is 12,622,996,178, 18,100,140 and 18,090,682
  in the same three forms. Before the rule flagged the offsetting line the middle figures were 4,329,474,822 and 6,320,549,121.

### Calculation groups and the restatement measures

| Combination | Meaningful? | What it returns |
|---|---|---|
| Time Intelligence Current, MTD, QTD, YTD, Rolling 12 months | yes, for every amount measure | the measure over the window, as at the same release; `Revision %` over a window is the ratio of the summed parts |
| Time Intelligence PY | yes | the previous year's figure as at the same release (a closed year: its final figure known then) |
| Time Intelligence YoY, YoY % | yes for amounts; BLANK for `Revision %` and `Estimated Mapping Share` | the difference of two percentages means nothing, so the two items return BLANK for the share measures |
| Scenario Comparison (all five items) | not meaningful | the restatement measures are not `Comparison Amount`, so the items pass them through unchanged: `Plan` shows the revision, not a plan. Do not put the restatement measures and the comparison items on one visual |
| Display Unit £k, £m, £bn | yes for every amount; no effect on `Revision %` and `Estimated Mapping Share` | the value divided by 1, 1,000 or 1,000,000, with the unit's format string |

**Tested** (test 769, 24 cells, largest difference 0.00005): at two releases (December 2021 and December 2024), period 6 of
their own years, the five revision measures under Current, YTD, PY and YoY and the three units equal T-SQL; `Revision %`
(the model measure) is BLANK under YoY while the same ratio in parts per million written as a test measure is the difference.
Not tested: MTD, QTD and Rolling 12 months on these measures (the items are the same functions as in tests 727 and 728), and
a restatement measure on a visual with a release on one axis and a time item on the other.

## Department structures: as reported and current

A department of the current structure (`Department (current structure)`, 63 members) and the department as a release
reported it (`Organisation (as reported)[Department Number (as reported)]`) are both related to `Fact Outturn` and both
active. A reorganisation always shows between releases and never inside one, so "as reported" means "as the release in
view reports it". The measures live in the display folder `Current Structure`.

| Measure | What it returns | Tested by |
|---|---|---|
| `Outturn (current structure)` | the outturn of the lines that belong to the department in context today. Equal to `Outturn` with `Department (current structure)` on rows; named so that a matrix with both structures says which is which | 764 to 766 |
| `Outturn (as reported structure)` | the outturn of the lines the releases in context reported under the row's department number, whatever department they belong to today | 764 to 766 |
| `Machinery of Government Transfer` | current less as reported: what the change of structure moved into the department (positive) or out of it (negative) | 764 to 766 |
| `Outturn (estimated mapping)`, `Estimated Mapping Share` | the part of the department's outturn that is there through an estimated mapping, and its share of the department's net outturn | 767 |

**The rule that finds a department's counterpart.** Never the name: 43 of 51 name changes between consecutive releases are the
same department under an alternating label. Each department of the current structure carries a hidden column `Reported
Department Numbers`, written `|030|027|`, built in SQL (`dw.department_reported_number`, `sql/dw/760`), and the as-reported
measure takes the numbers of the departments in context from it and keeps the lines reported under them (`TREATAS` on
`Department Number (as reported)`). A number is answered for by the first of three:

1. **own number**: a live department of type Department carries it. 59 numbers.
2. **Unallocated member**: no live department carries it and the member `U` + the number exists (`U011` the Electoral
   Commission, `U035` the Assets Recovery Agency, `U077` Exiting the EU): 3 numbers.
3. **largest receiver**: neither. One number, `027`, the Foreign and Commonwealth Office (last reported in June 2021), whose lines go to the
   Foreign, Commonwealth and Development Office (FCDO) in the current structure; it is answered for by the live department that receives most of its lines (by absolute net amount), which is
   FCDO. This is my rule, not a published one. `Unallocated: former BEIS shared lines` (`U084`) answers for no number: its
   lines were reported under 084, which the live Department for Science, Innovation and Technology carries.

Every number maps to exactly one department, so the as-reported figures added over the departments add back to the total,
and the transfers sum to zero. **Tested**: `sql/tests/760_every_reported_department_number_has_exactly_one_current_department.sql`
(every number mapped once, the four non-own numbers are exactly 011, 027, 035 and 077, the numbers in the view's lists are
the table's), and DAX tests 764 (by year, nine rows) and 765 (by release, 31 rows): the sum over departments of the current
structure, of the as-reported structure and of the transfer, against the total, are equal and 0 in every year and every
release (`tests/results/764_structure_totals_by_year.csv`). Test 766 compares all 537 department-year cells with T-SQL
that places each line by `dw.current_structure_line` and finds the answering department by the three rules written out
again. For 2022-23 the transfers are, in GBP thousands: DSIT (084) +58,273,954, DBT (013) +3,503,791, DESNZ (066)
-61,750,818 (it did not exist as a number in that year's releases), DCMS (048) -27,509, `U084` +582, and every other
department 0. In 2023-24 and later every transfer is 0: the releases already report the new structure.

**`Estimated Mapping Share`.** Three BEIS lines (`X084A031`, `X084A254`, `X084A364`) are placed in the Department for
Science, Innovation and Technology by judgement (`is_estimated` in `authored/current_structure_map.csv`). The flag travels
on the fact (the hidden column `Mapping Is Estimated`, from `stg.current_structure_map` in `dw.v_model_fact_outturn`; 22 fact
rows; **tested**: `sql/tests/761_the_estimated_mapping_flag_on_the_model_fact_is_the_flag_of_the_line.sql`). The share is on net
amounts, so it can exceed 100% or be negative where a department's net outturn is small; in 2022-23 it is -20,672 of 11,441,606
for DSIT, that is -0.18% (`tests/results/767_estimated_mapping_share.csv`), and it is 0 for every other department with outturn.

## Rank of the year-to-date variance %

`Department Group Rank (YTD Variance %)` ranks the Spending Review groups by the Variance % item of Scenario Comparison under
the YTD item of Time Intelligence, largest first (1 is the biggest overspend against plan), and returns BLANK where the group has no
variance %. It is slow measure 2. It works out each group's value once, in `ADDCOLUMNS` over the groups, and ranks that column
with `RANKX`; the plain form, with both calculation items written out three times inside `RANKX`, is kept as the hidden measure
`Department Group Rank (YTD Variance %) (naive)`, and both are timed in `docs/performance.md`. It ranks groups, not departments, because the plan has no department. Ties share a rank and the next
rank is skipped, as T-SQL `RANK()` does; a group with no plan or a plan of zero has no variance % and so no rank, and does not
count in the others' ranks. Use it with no Time Intelligence or Scenario Comparison item selected: both are set inside the
measure, and an item from outside would apply to the rank itself. **Tested**: test 768 (69 cells, three years, largest
difference 0.000001 parts per million) equals `RANK() OVER` over the year-end variance % computed in T-SQL from
`dw.outturn_plan_basis_inyear` and `dw.fact_plan`. A year to date before period 12 has no plan, so the rank is BLANK there.

## Data controls and the measures the report needs

The report's data-controls page shows the checks that the build already writes, so the model holds them as tables. They are
audit and control tables: real counts and totals copied from `audit.*` and `dw.plan_coverage` by the views in
`sql/audit/780_v_model_controls.sql` and `sql/audit/781_v_model_controls_full.sql` (in the audit layer because they read audit tables), with no number recalculated. Each carries
"AUDIT and CONTROL" first in its description and the display folder `Audit and control` on every visible column.
**Tested**: `sql/tests/780` (committed scope) and `sql/tests/781` (full scope) show that each view has the rows and totals of
its audit table, and DAX tests 780 to 784 show that the model returns the same figures.

| Model table | Source view | Rows | Scope | What it shows |
|---|---|---:|---|---|
| File Control | `dw.v_model_file_control` (`audit.file_control`) | 31 | committed and full | rows read, loaded and quarantined, the file's exact sum as text and its four-decimal total, per release; related to Release |
| Plan Coverage | `dw.v_model_plan_coverage` (`dw.plan_coverage`) | 69 | committed and full | plan fact rows, source lines and total by plan source, year, measure and grain |
| Annual Control | `dw.v_model_annual_control` (`audit.bud_vs_inyear_del`) | 60 | full | in-year outturn against the restated annual file; only DEL at total level is graded |
| PSS Control | `dw.v_model_pss_control` (`audit.pss_vs_outturn`) | 443 | full | the Public Spending Statistics database against OSCAR; the capital DEL gaps of 2023-24 and 2024-25 are rows of it |
| Plan Variance Check | `dw.v_model_plan_variance` (`audit.plan_variance_reconciliation`) | 364 | full | every plan variance from FY2022-23 by group and measure, with the independent outturn, the gaps, the residual and the verdict (ok, fixed, explained, unexplained); related to nothing |
| Load Control | `dw.v_model_load_control` | 46 | full | rows read, loaded and quarantined of every in-year and annual file |

The four full-scope views need files that are not in git, so a model on a committed-scope database cannot refresh these four
tables; the model is built and tested on the full-scope database (the README says so). Five of the six tables are related to
nothing (a control table is a list of checks, and a relationship would let a slicer filter an audit row), which the analyzer
counts as five information findings among the ten of that rule (`evidence/bpa`).

Measures added for the report, each with a DAX test:

| Measure | Table | What it is | Test |
|---|---|---|---|
| `File Total (4 decimals)`, `Outturn as at Release (own year)`, `Difference to File Total` | File Control | the file's total, the model's as-at outturn of the release's own year, and their difference (0 for all 31 releases) | 780 |
| `Plan Coverage Total` | Plan Coverage | the plan total of the rows in context | 783 |
| `Rows Read`, `Rows Loaded`, `Rows Quarantined`, `Web Rows Quarantined` | Load Control | counts; the last is the rows of the deflator and CPI quarantine tables | 784 |
| `Plan Source and Grain` | Fact Plan | the badge: plan source and grain of the plan rows in context, in the words of the source's edition and of Plan Grain | 785 |
| `Variance to Phased Plan`, `Variance to Phased Plan %` | Fact Plan Phased (derived) | DERIVED: outturn on the plan's basis less the phased plan, in a month or (under Time Intelligence) the year to date | 786, 788 |
| `Plan and Outturn by Scenario` | Fact Plan | plan on the Plan scenario and outturn on the plan's basis on the Outturn scenario, for a waterfall with Scenario as its category | 793 |
| `Latest Release in View` | Fact Outturn | the month of the latest release, a page header label | 788 (page text) |

`Variance to Phased Plan` and `Plan and Outturn by Scenario` are added to the amount measures that `Display Unit` scales (the list is in each of its six
expressions), which is the one change to that calculation group, made by hand and reviewed as a diff. The two label measures
return text and so have no number format; their analyzer ignores say so (`te/bpa/ignores.csv`). The rule that lists the
allowed format strings now allows `#,##0` for a count of rows. The model has 23 relationships (22 before File Control to Release).

## Scripts, rules and perspectives

The model's metadata is kept by scripts, so that a display folder, a description, a perspective or a real-terms measure can be
rebuilt and a drift shows up as a diff. The TMDL files stay the source of truth; the scripts edit them through Tabular Editor 2
and I review the diff of every run.

### Normalising the files to the Tabular Editor layout

Tabular Editor 2.29 reformats TMDL when it saves, so I loaded the model and saved it back once with no script and committed that
alone ("Normalise the model files to the Tabular Editor layout"), so that every later script diff shows only a real change. Of the 30
files, 27 changed and 3 did not (below). The changes are layout: the order of objects in a table file, less quoting (`ref table
Sub-Segment`), blank lines, a function body indented under `function 'Name' =` instead of fenced, the `ref expression` lines of
`model.tmdl` gone, and two markers Tabular Editor writes (`compatibilityMode: powerBI` in `database.tmdl` and `annotation __TEdtr
= 1` on the model). No expression, property, `$schema`, lineage tag or the compatibility level changed.

**What I could not round-trip.** Tabular Editor 2.29 reads the `ordinal` of a calculation item and does not write it back, and it
writes the item `Favourable/Adverse` unquoted. So `Display Unit`, `Time Intelligence` and `Scenario Comparison` stay as written by
hand, and the wrapper never copies them back (its `-Keep` list). A script that has to change one of them edits the text itself; the
real-terms measures are added to the lists of `Display Unit` by hand and `test_display_unit_scales_every_real_terms_measure_in_every_item`
fails when one is missing.

**Tested.** The normalised model opens in Desktop and refreshes (11.5 s), all 47 DAX tests then existing gave results byte for byte
equal to the committed ones (`git status` clean on `tests/results`), `ukfr dax-compare` passed 47 of 47, and the 114 violation lines that Tabular
Editor's analyzer printed for the standard Microsoft rule set before and after are identical.

### The scripts

`tools/run_te_script.ps1` (Windows PowerShell 5.1) loads `model/UKGroupFinance.SemanticModel/definition`, runs the scripts one after
another, saves TMDL to a scratch folder and copies back only the files that changed, then lists them. If a script or Tabular Editor
fails, nothing is copied back. The scripts read their input files through `UKFR_REPO_ROOT`, which the wrapper sets.

| Script | What it does | Input |
|---|---|---|
| `te/scripts/real_terms_measures.csx` | writes the seven `(real terms)` twins (above) | the list at its top |
| `te/scripts/display_folders.csx` | gives each visible measure its display folder, the `Derived` folder to the visible columns of the derived table and `Authored` to those of the authored tables; fails on a visible measure it cannot place | the table at its top |
| `te/scripts/descriptions.csx` | fails, listing the offenders, if a visible table, column or measure, a calculation item, a function or a perspective has no description; writes nothing | none |
| `te/scripts/perspectives.csx` | builds the three perspectives and deletes any other | `te/scripts/perspectives.csv` |
| `te/scripts/mdx_availability.csx` | sets IsAvailableInMDX to false on a hidden column nothing sorts by or groups, and true on one that something does | none |
| `te/scripts/bpa_ignores.csx` | writes the per-object ignore annotations of the analyzer | `te/bpa/ignores.csv` |

```
powershell.exe -NoProfile -File tools\run_te_script.ps1 -Script te\scripts\display_folders.csx
powershell.exe -NoProfile -File tools\run_te_script.ps1 -Script te\scripts\descriptions.csx,te\scripts\perspectives.csx
```

**Tested.** I ran each script a second time against the committed files and the wrapper reported "No file changed" for every one.
The failing paths: `descriptions.csx` named five planted offenders (a table, two columns, a measure and a perspective) and, in another
run, a function without a description, and exited 1, and `display_folders.csx` named three planted measures it had no folder for. The descriptions of the
table, column and measure files are written by hand in the TMDL (`///` lines); the script only checks them. The two CSV files
(`perspectives.csv`, `ignores.csv`) are metadata about the model and hold no data, so they are not in the README register, which
lists authored data files that reach the warehouse. `pipeline/tests/test_model_scripts.py` checks that the TMDL says what the
scripts and their CSV files say.

### The analyzer rules

`te/bpa/rules.json` has 63 rules: 48 kept from the standard Microsoft set and 15 of mine whose ID starts with `UKFR_` (no inactive
or bi-directional relationship, no measure named like a column of its own table, a description on every visible object, a folder and
a format string on every measure, the labels of the authored and derived tables, no Double amount, `DIVIDE` and not `/`, no
`IFERROR`, hidden relationship keys). What I dropped from the standard set and why, the severity convention (3 fails CI, 2 warns,
1 informs) and every ignore with its reason are in [te/bpa/README.md](../te/bpa/README.md). Each of my rules was tested by planting one
violation in a scratch copy of the model and reading what Tabular Editor reported: all 15 fired.

The first run of the new file on the normalised model found 74 violations in 14 rules, one of them at severity 3. What I did:

| Rule (severity) | Before | After | What I did |
|---|---:|---:|---|
| `ISAVAILABLEINMDX_FALSE_NONATTRIBUTE_COLUMNS` (2) | 44 | 0 | `mdx_availability.csx` set the property on the hidden keys and amounts; DAX does not read it, and the MDX format-string evidence ([evidence/model/format_strings.csv](../evidence/model/format_strings.csv)) came out byte for byte the same |
| `AVOID_DUPLICATE_MEASURES` (2) | 3 | 0 | ignored on the three measures, with the reason |
| `MINIMIZE_POWER_QUERY_TRANSFORMATIONS` (2) | 4 | 0 | ignored on the four web partitions: the parsing in Power Query is a decision |
| `UNNECESSARY_COLUMNS` (2) | 3 | 0 | ignored on three hidden columns, with the reason |
| `SNOWFLAKE_SCHEMA_ARCHITECTURE` (2) | 2 | 0 | ignored on `Fiscal Period` and `Account` |
| `DAX_MEASURES_UNQUALIFIED` (3) | 1 | 0 | ignored on the field parameter, which needs the qualified form |
| `HIDE_FACT_TABLE_COLUMNS`, `HIDE_FOREIGN_KEYS`, `MEASURES_SHOULD_NOT_BE_DIRECT_REFERENCES_OF_OTHER_MEASURES`, `REDUCE_USAGE_OF_CALCULATED_TABLES`, `REMOVE_REDUNDANT_COLUMNS_IN_RELATED_TABLES`, `UKFR_RELATIONSHIP_COLUMNS_HIDDEN` (2) | 1 each | 0 | ignored on one object each |
| `ENSURE_TABLES_HAVE_RELATIONSHIPS` (1) | 5 | 5 | left as information: the web tables and the field parameter are unrelated on purpose |
| `RELATIONSHIP_COLUMNS_SHOULD_BE_OF_INTEGER_DATA_TYPE` (1) | 6 | 6 | left as information: the year and the grain are text codes |

After: 11 violations, both rules at severity 1 (`evidence/bpa/bpa_counts.csv`, `evidence/bpa/bpa_violations.csv`, written by
`tools/summarise_bpa.py`). The `model-bpa` job fails on severity 3 and then fails if its counts differ from those two files. The
ignores are 26 rows for 23 objects (`te/bpa/ignores.csv`), two of them for the hidden plain forms of the slow measures. Before I replaced the authored tables' descriptions, the label rule
would have found Scenario, Spending Review Group, Plan Source, Plan Grain and Statement Measure unlabelled; I prefixed their
descriptions with AUTHORED and `display_folders.csx` puts their visible columns in `Authored`, as the derived table's are in `Derived`.

### Perspectives

Three, built from `te/scripts/perspectives.csv` (one row per object, hidden objects refused):

| Perspective | For | Holds |
|---|---|---|
| `Executive` | the headline figures | outturn, outturn on the plan's basis, the comparison measure, plan, the statement amounts, variance, outturn on the current structure and the real-terms twins of the amounts; the year, period, department, Spending Review group and statement line; the three calculation groups. No keys, no quarantine, no restatement detail |
| `Restatement` | how a figure moved between releases | the release, the as-at, first-reported, revision, restatement and gross measures, the structure and transfer measures, the data-quality findings, the organisation and department structures, the time items and the unit |
| `Data Controls` | what to check before trusting a number | the two quarantine tables, plan grain and source, the findings, the release, the as-at and file-control measures, `Plan Below Grain` |

A calculation group is in a perspective only with the dimensions it needs to run (`Time Intelligence` with `Fiscal Period` and
`Fiscal Year`); `Scenario Comparison` is left out of `Restatement` and `Data Controls` because it does not act on their measures.

**What a perspective does and does not do. Tested.** It narrows the field list and the metadata a client sees; it secures nothing.
(a) `tests/dax/777_perspective_measures.dax` reads the engine's own list of the measures of each perspective
(`$SYSTEM.MDSCHEMA_MEASURES`, one cube per perspective) and compares it with the measure rows of `perspectives.csv`: 42 rows, difference 0
(Executive 17, Restatement 16, Data Controls 9; the model's own cube lists 38). (b) `pipeline/tests/test_model_scripts.py` compares the TMDL
of each perspective, table by table and column by column, with the expansion of the CSV and checks that nothing hidden is in one.
(c) `tools/run_perspective_checks.ps1` runs four queries under `Cube=Executive` and one under a name that does not exist and writes
[evidence/model/perspective_queries.csv](../evidence/model/perspective_queries.csv): a query that names an object outside the perspective
**is answered** (`Outturn as at Release`, a column of `Data Quality Issue` and a row count of `Release` all returned a value), so
my expectation that such a query would fail was wrong; only a perspective that does not exist fails, with the text "The
NoSuchPerspective cube does not exist." That is why 777 is a test of metadata and not of access, and why access control is for
object-level security, not perspectives.

## Parameters and sources

| Name | Default | Used by |
|---|---|---|
| `Server` | `localhost` | every SQL partition |
| `Database` | `UKGroupFinance` | every SQL partition |

Both are text parameters in `expressions.tmdl`, in a query group `Parameters`. The credential for that server and
database was stored in Desktop in an earlier session; no dialog appears for it.

### The deflator and CPI queries (Power Query)

I read these in Power Query, so that the parsing is visible in the model and not hidden in a loader. Five files are read over the web with `Web.Contents`; nothing is
read from a local path. **Internet access is needed at refresh.**

| File | Link | Query |
|---|---|---|
| three GDP deflator workbooks (`gdp_deflator`: June 2026 QNA, September 2026 QNA, October 2026 Budget) | the `file_url` of each row in `data/manifest/files.csv` | `Deflator Raw` |
| two ONS CSVs (`ons_cpi`: D7BT index, D7G7 annual rate) | the `file_url` of each row | `CPI Raw` |

The links sit in one place each (a list of records at the top of `Deflator Raw` and `CPI Raw`), and
**tested** (`test_the_web_links_are_the_manifest_links_and_appear_once_in_one_expression`) that they are exactly
the five links of the manifest and appear nowhere else in the model.

Structure, so that the privacy firewall has nothing to object to:

- `Deflator Raw` and `CPI Raw` read the web and nothing else, and return the cells of each file untouched.
- `fnParseGdpDeflator` and `fnParseCpi` (one function per file shape) take those cells and read no source.
- `Deflator`, `Deflator Quarantine`, `CPI` and `CPI Quarantine` call a function on a raw query. No query reads a
  source and calls another query, and no query combines the web with SQL (**tested** for the SQL side:
  `test_each_sql_table_reads_one_view_with_the_server_and_database_parameters`).

**Parsing is by header text, not position** (the profiling of the deflator files showed why: column A is empty, the note lines change order between vintages and forecast years carry a dash). The GDP
function finds the row that holds the words "Financial year" and a column headed "= 100", then the columns headed
"Financial year", "= 100" and "per cent change"; it reads every row whose label starts with a year like `2026-27`
(footnote markers allowed), and takes the index as a number or a dash. The ONS function classifies each line by the
shape of its first field (`1989`, `1989 Q1`, `1989 JAN`), takes the metadata (`CDID`, `Title`, `Unit`, `Release date`)
from the lines before the data, and loads only the monthly block.

**Nothing is dropped silently.** A row that cannot be read is returned with the status `rejected` and a reason, and
the two quarantine tables show them with the file and the reason. A row is rejected for: an index or per cent change
cell that is neither a number nor a dash; a forecast year with no per cent change (it cannot be chained); a year that
appears twice; numbers on a row whose label is not a financial year; a financial-year row after the data block ended;
a workbook without exactly one sheet or without the header row; for the ONS files a value that is not a number, a
month that does not follow the one before, a block out of order, a row of no known shape after the data started, a
file with no `CDID` line. Blank lines and note lines are not data and are not quarantined. **Tested** on a scratch
copy of the project: the functions were run on in-memory copies of the October 2026 workbook and of D7BT, with and
without planted faults, and every planted fault came back as a rejected row with its reason, and the unfaulted input
parsed to the same values as the Python reader (the largest difference was 0)
([evidence/model/parse_quarantine_probe.csv](../evidence/model/parse_quarantine_probe.csv)). The probe is not part of
the committed model.

**The `Deflator` table** has one row per financial year and vintage: `Index Published` (2025-26 = 100; blank for a
forecast year, where the workbook gives only the per cent change), `Per Cent Change`, `Chained Index` and
`Is Default Vintage`. All three vintages are 2025-26 = 100: they differ by revision, not by rebasing
(`docs/profiling/cross-checks-and-deflators.md`). `Chained Index` is the published index for an outturn year and, for
a forecast year, the previous level times one plus the published per cent change, rounded to four decimals at each
step, the rule of `ukfr.readers.deflators.chained_index`. Real terms must chain forecast years from one vintage and
never mix index levels from two. The default vintage is the October 2026 Budget, and `Is Default Vintage` marks it.

**The ONS files are volatile.** ONS regenerates them each month (the file ONS served on 18 November 2026 held
October 2026, the pinned copy ends September 2026). The model can therefore hold later months than the tests compare.

## Refresh

Data is lost when Desktop closes, so a session starts with `tools/run_dax.ps1 -Refresh` (or `tools/run_dax_tests.ps1
-Refresh`). **Tested**, in the Desktop of this work (the timings are printed by the tool and are not committed as a
result file):

- the 16 SQL tables: 10.7 s the first time after Desktop opened, then 3.3 to 7.1 s;
- the four web tables on the first web refresh: 47.9 s (the credentials for both web hosts were already stored in this
  Desktop, so no dialog appeared);
- a full refresh of all 20 tables afterwards: 3.7 s (I expect the mashup engine to have cached the web responses; I did
  not verify that).

A web credential is stored per host, anonymous. A Desktop that has never read those hosts shows an "Access Web content"
dialog for `https://www.ons.gov.uk/generator` (tab Anonymous, "Use anonymous access for this Web content", Connect) and,
I expect, one for the gov.uk assets host; only the person at the keyboard can answer them. I saw the ONS dialog once and it
was answered or cancelled before I could record its second step, so the assets dialog is not seen.

### Values loaded (tested: `tests/results/703_deflators.csv`, equal to the pinned workbooks)

| Vintage | 2024-25 | 2025-26 | 2026-27 (chained) | 2027-28 (chained) |
|---|---:|---:|---:|---:|
| June 2026 QNA | 96.6694 | 100 | 102.0057 | 103.9866 |
| September 2026 QNA | 96.757 | 100 | 102.0057 | 103.9866 |
| October 2026 Budget (default) | 96.757 | 100 | 102.6328 | 104.8078 |

## Not in the model yet

Translations, paybill object-level security (a later phase adds it to the Restricted Viewer role, see [security.md](security.md)) and any security in the service. Not tested: the measures on a report
canvas under a role, a visual that selects different periods in different years, and the matrix subtotals of the
calculation groups.
