# Security: row-level and object-level

The model has two roles, `Department Analyst` and `Restricted Viewer`. Both filter the data to the departments of the
current structure that a signed-in user is mapped to. The second one also hides objects. This page says what each role
does, which choices I made and why, and what I tested. Every claim is labelled **tested** (with the command and the
result file) or **designed** (not run, because it needs the Power BI service, which I do not use).

## The user map is synthetic

No real person is in this repository. The map is `synthetic/user_department.csv`: eight invented users with addresses at
`example.org` (a reserved domain), 11 rows in all, each row a user and a three-digit department number. It is loaded into
`synthetic.user_department` by its own stage, labelled SYNTHETIC in the table description and in the model, and listed in
the register in the [README](../README.md#register-of-real-authored-derived-and-synthetic-data). It holds no amount.

| User | Departments (number) | Why this user is in the map |
|---|---|---|
| `alice.morgan@example.org` | 003 | one department that is the only member of its group (Environment, Food and Rural Affairs) |
| `ben.okafor@example.org` | 004 | the same for Transport |
| `chloe.patel@example.org` | 033, 903 | **two departments**; the two are the whole group Health (NHS) |
| `dev.sharma@example.org` | 010 | one of three departments of its group (010, 901, 915): outturn and no plan |
| `fatima.khan@example.org` | 079 | **a department with outturn in six of the nine financial years** (Parliamentary Works Grant); one of 27 members of its group |
| `george.evans@example.org` | 087 | HM Treasury, one department, one group |
| `hannah.price@example.org` | 085 | the one department that feeds two groups (CLG Communities and CLG Local Government) |
| `jasmine.reid@example.org` | 013, 048, 084 | the three departments whose FY2022-23 plan is published as one combined group |
| `nobody@example.org` | none | **in no row, on purpose**: the unmapped user. The tests pass this name; the table cannot hold "no row" |

The model reads the map through two views and two hidden tables:

- `dw.v_model_user_department` becomes the table `User Department (synthetic)`: one row per user and department, with
  the key of the department of the current structure. The view stops the build if a number is not a live department of
  the current structure, so a typo can never give a user fewer rows without a sign.
- `dw.v_model_user_plan_group` becomes `User Plan Group (synthetic)`: one row per user and Spending Review group whose
  plan the user may see (the rule is below).

Both tables are hidden, related to nothing and hold no amount. Each role also filters them to the rows of the signed-in
user, so a user who queries them reads their own rows and no other.

**Tested** that no real total moves: `pipeline/tests/test_synthetic.py::test_the_real_facts_keep_the_pinned_row_counts_and_sums_with_the_synthetic_user_map_loaded`
(the row counts and sums in `evidence/expected/real_fact_totals.csv`, measured with the map loaded),
`sql/tests/821_only_the_two_role_views_read_the_synthetic_table_and_nothing_reads_them.sql` and
`pipeline/tests/test_register.py::test_the_synthetic_schemas_hold_exactly_the_registered_tables_and_no_fact_or_total_view_reads_them`
(only the two views read the table, nothing reads the views, no foreign key points at it, no numeric column),
`tests/dax/822_unrestricted_totals_with_the_user_map_loaded.dax` (with no role the model's totals equal SQL with the map
loaded: result `tests/results/822_unrestricted_totals_with_the_user_map_loaded.csv`).

## What the two roles filter

| Table | Filter | Why |
|---|---|---|
| `Department (current structure)` | the department keys of the signed-in user in `User Department (synthetic)` | `Fact Outturn` is related to this table, so the filter reaches every outturn line through the relationship |
| `Fact Plan`, `Fact Plan Phased (derived)` | the group keys of the signed-in user in `User Plan Group (synthetic)` | the plan is published by Spending Review group and is not related to a department, so a department filter cannot reach it |
| the two synthetic tables | the rows of the signed-in user | a user cannot list the map |

The user name is `USERPRINCIPALNAME()`, matched without regard to case (**tested**, case `alice_upper_analyst`). There is
no branch that returns every row: a name with no row in the map gives an empty set, so the filter fails closed.
`pipeline/tests/test_model_files.py::test_both_roles_filter_the_department_dimension_and_both_plan_facts_by_the_signed_in_name_and_fail_closed`
reads the role files and refuses `TRUE`, `OR` and `USERNAME`.

### The plan under row-level security: my decision

The plan sits at Spending Review group grain, and a group is often more than one department (Health (NHS) is 033 and 903;
Small and Independent Bodies has 27). There were two ways to filter it:

1. show a user the plan of the group their department belongs to, or
2. show the plan of a group only where **every** department of the group is one of the user's departments.

I chose 2. The first would show a user the plan of departments they cannot see: Cabinet Office is one of three departments
of its group, and the group's plan is the plan of all three. The cost of the second is that a user who holds part of a
group sees outturn for their department and a blank plan for the group, which is honest: the plan figure for a part of a
group does not exist in the source, and the plan grain guard (`Grain.BelowGrain`) already refuses to show a plan finer than
its grain. The guard is unchanged and still applies under both roles.

The members of a group are the department numbers in `authored/department_sr_group.csv` for that group (basis `current`,
or `pre2023_as_reported` for the combined group of FY2022-23). A group with no department member (reserves, the Single
Intelligence Account, central lines, the outturn-only member) is never visible to a user of either role. The rule is
written twice in SQL, in the view and in a second query over the authored text table, and the two agree
(**tested**: `sql/tests/822_a_user_sees_the_plan_of_a_group_only_when_every_department_of_the_group_is_the_users.sql`,
`sql/tests/823_the_named_users_see_the_groups_the_security_document_says.sql`,
`tests/dax/821_user_plan_group_rows.dax`).

What a user of each kind sees (**tested**: `tests/rls/results/`, cases in `tests/rls/manifest.csv`):

| User | Outturn, all years (GBP 000) | Groups with a plan | Result file |
|---|---:|---|---|
| `alice.morgan` | 62,887,897 | Environment, Food and Rural Affairs | `totals__alice_analyst.csv` |
| `chloe.patel` | 1,744,787,194 | Health (NHS) | `totals__chloe_analyst.csv` |
| `dev.sharma` | 11,048,271 | none: plan blank | `totals__dev_analyst.csv`, `outturn_and_plan_by_group_2024_25__dev_analyst.csv` |
| `fatima.khan` | 419,046 | none: plan blank; outturn in six years, blank in the other six years of the model | `totals__fatima_analyst.csv`, `outturn_by_year__fatima_analyst.csv` |
| `hannah.price` | 354,098,445 | CLG Communities and CLG Local Government | `plan_by_year_group__hannah_analyst.csv` |
| `jasmine.reid` | 283,020,683 | Combined pre-2023 (2017-18 to 2022-23), Business and Trade, Culture, Media and Sport, Science, Innovation and Technology | `plan_by_year_group__jasmine_analyst.csv` |
| `nobody@example.org` | blank | none | `totals__nobody_analyst.csv` |

The whole-model outturn is 9,098,653,566 (GBP 000), so no role sees it (**tested**, the `not_full` cases, mode `differs`:
the result of each mapped user is compared with the unfiltered total and must not equal it).

**An unmapped user sees nothing, and what that looks like:** a query that returns a table has no rows (the department list,
outturn by year and department, the plan by group), and a query that returns a single row of measures has that row with
every measure blank (`totals__nobody_analyst.csv` is one row of three empty cells). It is blank, not zero and not an error.

## The two roles

`Department Analyst` is the filter and nothing else. It still sees the audit and control tables (file control, plan coverage,
annual control, PSS control, load control, plan variance check): they hold file-level control totals and plan coverage, not
department detail, and an analyst reconciling a figure needs them. I did not restrict them in this role. (**Tested**: the
case `control_tables_rows__chloe_analyst` returns 31 file-control rows and 69 plan-coverage rows.) A consequence that I
have not removed: the plan variance check shows the plan variance by group for all groups.

`Restricted Viewer` is the same row filter plus object-level security, in **one** role, because the engine refuses a
row-level role combined with a separate object-level one ("The combination of active roles results in a dynamic security
configuration that is currently not supported", `docs/spikes/desktop_capabilities.md`, row 7f). It hides:

| Hidden | What | Why this and not more |
|---|---|---|
| tables `File Control`, `Plan Coverage`, `Annual Control`, `PSS Control`, `Load Control`, `Plan Variance Check` | the audit and control tables | no measure outside them reads them |
| columns of `Organisation (as reported)`: Organisation, Version Number, Department (as reported), Valid From Release, Valid To Release, Releases Reported, Version Reason, Durable Key Rule, Successor Durable Key, Is Current Version, Is Latest Version | the organisation's name and version history | the plan grain guard and the plan row selection read `Organisation Code` and `Durable Key`, and the as-reported measure reads `Department Number (as reported)`; hiding any of the three would make every plan measure error, so they stay |
| columns of `Data Quality Issue`: Issue Description, Treatment, Release From, Release To, Organisation Code, Sub-Segment Code, Economic Category Code, Control Budget Detail Code, Period Key, Amount Before, Amount After, Rows Affected | the line-level detail of each finding | `Issue Type`, `Issue Rule` and `Flags Fact Rows` stay, and the table itself stays, because the grain guard counts its rows |

I first meant to hide the whole organisation table and the whole data-quality table. That would make `Plan` and every measure
built on the grain guard return an error for this role, so I hid the columns instead and kept the three that a measure reads.
The cost is that a restricted user still sees an organisation's code (`organisation_codes__chloe_restricted.csv`: 300 codes,
the same as the analyst), though not its name. The organisation table is not filtered by department: a dimension member is
visible to a user and its measure values are blank outside their departments. Filtering it by department would drop outturn
lines through its relationship, because an organisation's department as reported is not its department in the current
structure.

Paybill detail is in the pay bridge, and its object-level security is in this same role, not in a third one: see "The pay bridge under the two roles" below.

### Which measures the object-level security affects

A measure that reads a hidden object returns an error, not a blank. `tools/run_rls_tests.ps1 -ProbeMeasures` evaluated each
of the 53 measures of the model alone as the Restricted Viewer (69 with the NHS trust accounts, see below) and wrote
[evidence/model/ols_measure_probe.csv](../evidence/model/ols_measure_probe.csv): 45 answer and 8 return an error. The 8 are
the measures that live in the hidden tables themselves: `Difference to File Total`, `File Total (4 decimals)` and
`Outturn as at Release (own year)` (File Control), `Rows Loaded`, `Rows Quarantined`, `Rows Read` and `Web Rows Quarantined`
(Load Control), and `Plan Coverage Total` (Plan Coverage). No other measure reads a hidden object, so no restructuring was
needed (**tested**: `pipeline/tests/test_model_files.py::test_the_ols_measure_probe_errors_for_exactly_the_measures_that_live_in_the_hidden_tables`
and `test_no_measure_or_function_reads_a_column_or_table_the_restricted_role_hides_except_those_the_document_lists`).
The report pages that show the data controls, the restatement detail by finding and the organisations of a department use
the hidden objects, so those visuals fail for this role. I did not run the report under a role and make no claim about it.

## The NHS trust accounts under the two roles

The NHS trust accounts (`Fact TAC`, `Fact TAC Cash Flow (derived)`, the provider and line tables, [model.md](model.md#the-nhs-trust-accounts-balance-sheet-cash-flow-and-elimination-control))
follow the same row filter as everything else, without a third role and without a new user.

- **Row-level.** Every provider is related to the Department of Health and Social Care, which is department 033 in the synthetic map. `Department (current structure)` filters `TAC Provider`, which filters both TAC facts, so a user sees TAC only if the map
  gives them department 033: `chloe.patel` does, the other seven do not, and `nobody@example.org` does not. The hand-keyed consolidated figures have no provider, so their table has its own row filter in both roles
  (`'User Department (synthetic)'` against the department key of `TAC Provider`): a user who cannot see the providers cannot list the consolidated values either, and the measures that read them are blank.
- **Object-level (Restricted Viewer only, in the same role).** I **did** decide to hide the identity of a provider: the name, code, region, sector, the years with statements, the reporting status and the successor columns of `TAC Provider` (12 columns). The type of provider, the
  key and the department key stay, and no measure reads a hidden column, so every TAC measure answers for the Restricted Viewer and gives the same figure as for the analyst. The reason is the design of the role, not the confidentiality of the data (the accounts are published): the restricted viewer reads
  group totals and not named trusts, and a hidden name is the simplest object-level rule to test.
- A measure that reads a hidden object returns an error: the probe now evaluates 69 measures as the Restricted Viewer, 61 answer and 8 return an error, the same 8 as before ([evidence/model/ols_measure_probe.csv](../evidence/model/ols_measure_probe.csv)); none of the 16 TAC measures is among them.

**Tested** (`tools/run_rls_tests.ps1`, `ukfr rls-expected`, `ukfr rls-compare`: 113 of 113 cases pass, the 26 new ones in `tests/rls/manifest.csv` with the queries `tac_*`):

| Case | Role and user | Result |
|---|---|---|
| `tac_totals` (cash 2024-25, providers, derived net change, consolidated cash and gap, row counts) | analyst: `chloe`; seven other mapped analysts and `nobody` | `chloe`: 9,633,778.7198 cash, 207 providers, 228 provider rows, 344,812 fact rows, 48 consolidated rows; every other user: amounts blank, row counts 0 |
| `tac_totals` | restricted: `chloe`, `alice`, `jasmine`, `nobody` | `chloe`: the same figures as the analyst; the others: blank and 0 |
| `tac_provider_names` | analyst: `chloe` (228 rows), `alice` and `nobody` (0 rows) | equal to SQL |
| `tac_provider_names_hidden` | restricted: `chloe`, `nobody` | refused: `Column 'Provider' in table 'TAC Provider' cannot be found or may not be used in this expression.` |
| `tac_by_provider_type` | analyst `chloe`; restricted `chloe`, `alice`, `nobody` | the type column is not hidden: `chloe` sees the same two rows in both roles, the others none |
| `tac_consolidated_rows` | analyst `chloe`, `alice`; restricted `chloe`, `nobody` | 48 rows for `chloe`, none for the others |

The expected values are written from `dw.tac_provider_group`, `dw.tac_fact`, `dw.tac_cash_flow_derived` and `dw.tac_consolidated_control` with `synthetic.user_department`, never from the views the model reads.

## The pay bridge under the two roles

The pay bridge (`Fact Pay Bridge (derived)`, `Pay Organisation`, `Pay Coverage`, `Pay Bridge Step`; [model.md](model.md#the-pay-bridge-paybill-volume-rate-and-mix)) follows the same filter as everything else, in the same two roles and with no third one.

- **Row-level.** The bridge fact is related to `Department (current structure)` through the department the organisation sat in that month, so the Department Analyst and Restricted Viewer filters reach it without a table permission of its own. A user sees the bridge only for the departments of the map that have workforce data: `alice.morgan` (003) sees the Department for Environment, Food and Rural Affairs, `jasmine.reid` (013, 048, 084) three departments, `chloe.patel` (033) Health and Social Care; `dev.sharma` (010, Cabinet Office) and `nobody@example.org` see nothing and every amount is blank. Volume and mix are worked out on the rows the user can see, so a user for two departments sees a bridge pooled over those two.
- **Object-level (Restricted Viewer only, in the same role).** I hide the organisation-level detail of paybill:
  1. the table `Pay Organisation` (the code and name of each of the 89 organisations);
  2. the column `Organisation Key` of `Fact Pay Bridge (derived)` (the key that would give the paybill of each organisation);
  3. the table `Pay Coverage` (the paybill and full-time equivalent published and placed, by department series and month; a control table, so the department filter does not reach it, and the Department Analyst can read it, like `Plan Coverage`).
  **Known exposure, accepted.** `Pay Coverage` is not filtered by department, so every Department Analyst can read the published paybill and full-time equivalent of every department series, whatever department the user is mapped to (case `905_pay_coverage_rows`: 1,353 rows and the same paybill for `alice` and for `nobody`). I did not put a row filter on it because a series is a file collection, not a department (one series covers bodies of several departments), so no department key exists to filter on. I kept it open to analysts because the page's coverage visual needs it and the figures are published workforce data; a pound amount is more sensitive than a count, so this is a choice, not an oversight. The alternative is to hide the table from the Department Analyst in the same role, which makes the coverage visual error for analysts (**designed**, not built).
  No bridge measure reads a hidden object, so all 13 measures of the bridge fact answer for the Restricted Viewer with the same figures as for the analyst; the five measures of `Pay Coverage` return an error, because they live in a hidden table. Hiding `Organisation Key` protects a department with several organisations; in a department with one organisation the department's paybill is that organisation's paybill, so the hidden column adds nothing there (a limit I accept, since the department total is visible to the role anyway). The paybill parts (salary, allowances, overtime, pension, national insurance) are not in the model, so there is nothing more to hide.
- The names of the organisations are visible to every Department Analyst whatever department they are mapped to (a dimension member is not filtered; the amounts are), which is what the organisation table of the outturn does too. **Tested** (`902`, case `alice_analyst` and `nobody_analyst` both see 89).

A measure that reads a hidden object returns an error: the probe ([evidence/model/ols_measure_probe.csv](../evidence/model/ols_measure_probe.csv)) now evaluates 108 measures as the Restricted Viewer, 95 answer and 13 return an error: the same 8 as before and the 5 measures of `Pay Coverage`. None of the 13 measures of the bridge fact is among them. **Tested**: `test_the_ols_measure_probe_errors_for_exactly_the_measures_that_live_in_the_hidden_tables`.

**Tested** (`tools/run_rls_tests.ps1`, `ukfr rls-expected`, `ukfr rls-compare`: 136 of 136 cases pass, the 23 new ones in `tests/rls/manifest.csv` with the queries `900_pay_totals` to `906_pay_coverage_hidden`):

| Case | Role and user | Result |
|---|---|---|
| `900_pay_totals` (the bridge of 2025-26, the paybill of the valid cells, the rows of the fact and of the rows left out) | analyst: `alice`, `ben`, `chloe`, `george`, `hannah`, `jasmine`; `dev`, `nobody` | figures for the user's departments, equal to SQL; `dev` and `nobody`: amounts blank, counts 0 |
| `900_pay_totals` | restricted: `alice`, `jasmine`, `nobody` | the same figures as the analyst of the same name |
| `901_pay_by_department` | analyst: `jasmine` (three departments), `chloe` (one), `nobody` (none); restricted: `alice` | only the user's departments, equal to SQL |
| `902_pay_organisation_names` | analyst: `alice`, `nobody` | 89 organisations, 89 named, for both |
| `903_pay_organisation_names_hidden` | restricted: `chloe`, `nobody` | refused: `Cannot find table 'Pay Organisation'.` |
| `904_pay_organisation_key_hidden` | restricted: `alice` | refused: `Column 'Organisation Key' in table 'Fact Pay Bridge (derived)' cannot be found or may not be used in this expression.` |
| `905_pay_coverage_rows` | analyst: `alice`, `nobody` | 1,353 rows and the same paybill for both (no department filter) |
| `906_pay_coverage_hidden` | restricted: `chloe` | refused: `Cannot find table 'Pay Coverage'.` |

The expected values are written from `dw.workforce_month`, `dw.dim_organisation`, `dw.dim_department`, `dw.department_reported_number`, `audit.workforce_row_arithmetic` and `synthetic.user_department`, never from the views the model reads.

## The forecast accuracy under the two roles

`Fact Forecast Accuracy (derived)`, `Forecast Method` and `Forecast Return` follow the same department filter as everything else, in the
same two roles and with no third one: the fact is related to `Department (current structure)`, so a user sees the forecast scores of the
department groups that map to the user's departments (by the department number in the group code) and nothing else; a user with no
department sees nothing.

- **Row-level.** Both roles filter through the department dimension, with no new table permission.
- **Object-level (Restricted Viewer): nothing is hidden, and I decided that on the pay bridge's rule.** The rule there is that any
  object that exposes organisation-level paybill is hidden. The forecast fact exposes the paybill of a department group's workforce
  only as the sum of the department's valid organisations in one month (two hidden columns, `Cover Workforce` and `Cover Pay`, behind
  the one ratio `FTE x Cost Pay Cover`), never one organisation's; the department's own paybill is already visible to the role in the
  pay bridge. The FTE x cost rows carry no organisation key, and nothing else in the model joins the fact to an organisation. A
  department with a single organisation shows that organisation's paybill in the ratio; the department total is visible to the role
  anyway, as with the pay bridge. A test (`pipeline/tests/test_model_files.py`) fails if a column of the fact names an organisation.
- **Known exposure.** The cover columns are hidden and not secured: a Restricted Viewer who writes a query naming them gets the
  department-level paybill in thousands and the pay line of the month for the department's own groups. That is data the role may see.

**Tested** (`tools/run_rls_tests.ps1`, `ukfr rls-expected`, `ukfr rls-compare`: 149 of 149 cases pass, the 13 new ones in
`tests/rls/manifest.csv` with the queries `920_forecast_department_accuracy` and `921_forecast_fte_cost_rows`):

| Query | Users and role | What it shows |
|---|---|---|
| `920_forecast_department_accuracy` (cells, absolute error, absolute outturn and WAPE of the department's own forecast, by department) | analyst: `alice`, `chloe`, `jasmine`, `george`, `nobody`; restricted: `alice`, `chloe`, `nobody` | only the user's departments, equal to SQL over `dw.forecast_accuracy` and the user map; `nobody`: no rows; the restricted viewer sees the same rows as the analyst of the same name |
| `921_forecast_fte_cost_rows` (FTE x cost cells and the pay seen, by department) | analyst: `chloe`, `jasmine`, `nobody`; restricted: `chloe`, `jasmine` | only the user's departments, equal to SQL; the restricted viewer answers the FTE x cost measures with the same figures (no hidden object is read) |

## The cases I ran

`tools/run_rls_tests.ps1` runs each row of `tests/rls/manifest.csv` through `tools/run_dax.ps1` with `-Roles` and `-User`
(the ActAs scheme; without `-User` the name would be `MACHINE\user` on this machine and match no row). The expected values are
written by `ukfr rls-expected` from SQL over the `dw` and `synthetic` tables, never over the views the model reads, and
`ukfr rls-compare` compares them (same comparison as the DAX tests: any row order, numbers to 0.0001) and writes
[evidence/model/rls_tests.csv](../evidence/model/rls_tests.csv).

```
powershell.exe -NoProfile -File tools\run_rls_tests.ps1 -Refresh
uv run --project pipeline ukfr rls-expected
uv run --project pipeline ukfr rls-compare
```

Result of the last run: **149 of 149 cases pass** (127 `values`, 11 `differs`, 11 `error`, with the NHS trust accounts, the pay bridge and the forecast accuracy above; 87 of 87 before the NHS trust accounts). A planted wrong number in one result
file made `rls-compare` report one failure, and restoring it made all pass.

| Case family | Users and role | What it shows |
|---|---|---|
| each analyst sees only their departments' outturn, by year | all nine, Department Analyst, `outturn_by_year_department` | equal to SQL by year and department number |
| the two-department user | `chloe.patel` | 18 rows: 033 and 903 over nine years |
| a department with no outturn in some years | `fatima.khan`, `outturn_by_year` | blank in six years (three years in which the department reported nothing and three plan-only years), values in six |
| the unmapped user | `nobody@example.org` | no rows, or one row of blanks; no error |
| plan behaviour | all nine, `plan_by_year_group` and `totals`; `dev`, `chloe`, `hannah`, `nobody` in `outturn_and_plan_by_group_2024_25` | plan only for the complete groups; `dev.sharma` has outturn 1,044,013 for Cabinet Office in 2024-25 and a blank plan |
| the map filters itself | `chloe`, `nobody` | a user reads their own rows only |
| no role sees the full total | eight analysts, three restricted | the result differs from the unfiltered total |
| the analyst has no object-level security | `chloe` | file control (31 rows) and plan coverage (69 rows) answer |
| object-level security of the restricted role | `chloe`, `nobody` | the five `error` cases below; the same row filter as the analyst for four query shapes and five users |

The five refusals, with the text the engine returned (`tests/rls/results/ols_*.csv`, `control_tables_rows__chloe_restricted.csv`):

| Query | Engine message |
|---|---|
| a row count of `Plan Variance Check` | `Cannot find table 'Plan Variance Check'.` |
| a row count of `File Control` | `Cannot find table 'File Control'.` |
| a filter on `Organisation (as reported)[Organisation]` | `Column 'Organisation' in table 'Organisation (as reported)' cannot be found or may not be used in this expression.` |
| a sum of `Data Quality Issue[Amount Before]` | `Column 'Amount Before' in table 'Data Quality Issue' cannot be found or may not be used in this expression.` |

(the tool prefixes each message with `Error: Query (line, column)`, which the result files keep; the case checks the text after it.) A query on the visible measures under the same role works: `totals__chloe_restricted.csv` and the other restricted
cases equal SQL.

## Designed, not run

I use Power BI Desktop only, so none of this was run in the service:

- **Security groups and membership.** In the service the roles' members are Entra ID users or security groups, added on the
  semantic model's security page. Mine have no members.
- **App audiences.** An app can show different pages to different audiences; that does not secure data, so the roles are
  the control and the audience only the navigation.
- **Entra ID mapping.** In the service `USERPRINCIPALNAME()` returns the signed-in user's sign-in name (the UPN), not the
  mail alias, and a guest user's name has a different form. The real map would hold the UPNs the tenant returns. The
  synthetic one holds invented names so that no real person is in the repository.
- **View as role.** I did the equivalent here with ActAs, not with the Desktop or service "View as" dialogue.
- **Workspace roles.** Admins, members and contributors of a workspace bypass row-level security on a model they can edit.
  Only viewers are restricted, and I have not run this.
- **Report under a role.** Not run: see the last paragraph of "Which measures the object-level security affects".
