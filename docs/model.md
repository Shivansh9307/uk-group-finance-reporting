# The semantic model

One Power BI semantic model, `model/UKGroupFinance.pbip` (PBIP: TMDL for the model, PBIR for the report), on the star
schema that `ukfr build` writes to SQL Server. This page says what is in it, where each table comes from, how the
tables relate, and what I left out and why. It describes the skeleton: tables, relationships, parameters and the
deflator queries. There are no measures yet, no calculation groups and no report pages; those are later work. Every
claim is labelled **tested** (with the command and the result file) or **designed**.

## Decisions

- **Import mode, compatibility level 1702**, hand-written TMDL (**tested**: Desktop opens the project, and
  `tools/run_dax_tests.ps1` queries it; Tabular Editor 2's Best Practice Analyzer loads the folder and finds nothing
  to report with the starter rule file). Import because the largest table is 658,554 rows and refreshes in seconds
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
| Fiscal Year | `dw.v_model_fiscal_year` | 11 | real | financial years 2018-19 to 2028-29 |
| Fiscal Period | `dw.v_model_fiscal_period` | 143 | real | year and period 0 to 12 |
| Release | `dw.v_model_release` | 31 | real | the OSCAR in-year releases |
| Scenario | `dw.v_model_scenario` | 5 | authored | Outturn, Plan, Plan (phased), Departments' forecast, Own forecast |
| Account | `dw.v_model_account` | 128 | real, with an authored flow | economic categories (127 and Unknown) |
| Control Budget | `dw.v_model_control_budget` | 6 | real | DEL, AME, Non-budget and the five detail codes |
| Sub-Segment | `dw.v_model_segment` | 3,766 | real | OSCAR sub-segments (3,765 and Unknown) |
| Organisation (as reported) | `dw.v_model_organisation` | 409 | real, authored keys | Type 2 organisation versions (408 and Unknown) |
| Department (current structure) | `dw.v_model_department` | 63 | real, authored names | live departments and the four Unallocated members |
| Spending Review Group | `dw.v_model_sr_group` | 32 | authored | the groups plans are published by |
| Plan Source | `dw.v_model_plan_source` | 17 | authored | each plan source and edition |
| Plan Grain | `dw.v_model_plan_grain` | 4 | authored | the four grains a plan is published at |
| Data Quality Issue | `dw.v_model_data_quality` | 7 | real findings | six findings and the "No issue flagged" member |
| Deflator | web, see below | 229 | real | GDP deflators, three vintages, index and chained index |
| Deflator Quarantine | web | 0 | | deflator rows that failed to parse |
| CPI | web | 918 to September 2026; the web copy also held October 2026 on 18 November 2026 | real | ONS D7BT and D7G7, monthly |
| CPI Quarantine | web | 0 | | CPI rows that failed to parse |

Subsets, each tested by `sql/tests/700` and DAX test 700: Fiscal Year is one row per financial year of
`dw.dim_period`; Department (current structure) is the 63 live members of `dw.dim_department` (a closed naming period,
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

21 relationships, all active, all many-to-one, all single direction (the one side filters the many side). There are
no inactive relationships and no bidirectional ones (**tested**:
`test_every_relationship_joins_existing_columns_and_is_active_single_direction_many_to_one`), the one side is always
a key column of a dimension (`test_the_one_side_of_every_relationship_is_a_key_column_of_a_dimension`), and no row of
the many side meets a blank member (**tested**: DAX test 701, 21 relationships, 0 rows without a member in each).

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
   `Fiscal Period` and `Fact Plan`, so a year slicer filters outturn, plan and phased plan.
3. **`fact_plan` has no scenario key.** The view adds the key of the `Plan` scenario by joining `dw.dim_scenario` on
   its name.
4. **`dq_issue_id` is nullable.** A nullable key adds a blank member to the relationship. The view writes
   NULL as 0 and `Data Quality Issue` has a member 0, "No issue flagged". **Tested**: `sql/tests/703`.
5. **Plan grain A carries an organisation code, not a version.** `Fact Plan[Plan Organisation Code]` is an OSCAR code
   (grain A only, to FY2021-22), and a code can belong to two durable keys over time (BIS084 is BEIS and then DSIT), so it
   cannot relate to the Type 2 `Organisation (as reported)`. It stays as an attribute of the plan; a grain-A comparison
   with outturn goes through the code and the guard that blanks a plan below its grain (a measure, later).
6. **`Fact Outturn.department_key` is not exposed.** The department as the release reports it is carried by the
   organisation version (one row, EHR030 in June 2019, is reported under a different department from its version's;
   it is the only difference). The department of a version is the column `Department (as reported)`.
7. **Closed department periods are not in `Department (current structure)`.** 13 of the 76 rows of `dw.dim_department`
   are closed naming periods that never receive a line; showing them would add members that are always empty.
8. **The deflator history is wider than the fiscal calendar** (1955-56 onwards against 2018-19 to 2028-29), and the
   ONS series reach back to 1988. A relationship to `Fiscal Year` or `Fiscal Period` would add a blank member, so
   neither is related; measures will reach them with `TREATAS`. **Tested**:
   `test_the_deflator_and_cpi_tables_are_not_related_to_anything`.

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

Measures (the base measures, time intelligence, the scenario comparison and the grain guard), the statement layout,
security, perspectives, translations and report pages. Tabular Editor 2's Best Practice Analyzer runs in CI on this
folder with the three starter rules of the spike; a fuller rule file replaces them later.
