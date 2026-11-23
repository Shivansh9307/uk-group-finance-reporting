# Best Practice Analyzer rules for the model

This folder holds the rule file Tabular Editor 2 runs on the model (`rules.json`), the per-object ignores with the reason for each (`ignores.csv`, written into the model by `te/scripts/bpa_ignores.csx`) and this page. CI (job `model-bpa`) runs `TabularEditor <definition folder> -A te/bpa/rules.json`, fails on a violation of severity 3 or more (`.github/scripts/run-bpa.ps1`) and then compares the counts of the run with `evidence/bpa` (`tools/summarise_bpa.py --check`). A rule that Tabular Editor cannot evaluate also fails the job.

## Severity

| Severity | Meaning | Effect in CI |
|---|---|---|
| 3 | the model breaks a rule I treat as a contract | fails the job; there is none at the moment (**tested**: `evidence/bpa/bpa_counts.csv`, `test_the_committed_counts_cover_every_rule_in_the_file_and_nothing_at_severity_three_is_violated`) |
| 2 | a warning: something to look at, or a convention the model has not met | printed as a warning; counted in `evidence/bpa` |
| 1 | information | printed; counted |

The counts are committed so that a new violation below severity 3 is a visible change: the count step fails until I have looked at it and run `python tools/summarise_bpa.py --trx <file.trx> --write evidence/bpa`. The TRX file itself is never committed.

## Rules

The file has 63 rules: 48 kept from the standard Microsoft Analysis Services set (unchanged apart from the `Source` field) and 15 project rules whose ID starts with `UKFR_`. Rules are sorted by ID. I tested each project rule against the model in Tabular Editor by planting one violation of it in a scratch copy of the model and reading the result (every one fired; the copy is not in the repository). The measure-name rule cannot be planted through Tabular Editor's own API, which renames a new measure that collides with a column, so I planted it by writing the measure into the TMDL text of the copy.

### Project rules

| Rule | Severity | What it enforces |
|---|---:|---|
| `UKFR_NO_INACTIVE_RELATIONSHIPS` | 3 | Every relationship is active. A relationship that has to be switched on by USERELATIONSHIP is a second way to read a number; the model uses TREATAS or a role-playing dimension instead. |
| `UKFR_NO_BIDIRECTIONAL_RELATIONSHIPS` | 3 | Every relationship filters one way, from the one side to the many side. A bi-directional relationship makes filter propagation depend on the visual. |
| `UKFR_MEASURE_NAME_NOT_A_COLUMN_NAME` | 3 | The engine refuses a measure named like a column of its own table, in any letter case (Desktop reports that a column with the same name already exists). |
| `UKFR_DESCRIBE_VISIBLE_OBJECT` | 3 | Every visible table, column and measure carries a description (the /// line in the TMDL file). Hidden keys and technical columns are left out. |
| `UKFR_DESCRIBE_ITEM` | 3 | Calculation groups, their items and perspectives are always visible to a report author, so each has a description. Functions are checked by te/scripts/descriptions.csx, which a rule cannot reach. |
| `UKFR_MEASURE_FOLDER_AND_FORMAT` | 3 | Every measure sits in a display folder (te/scripts/display_folders.csx) and has a format string or a format string expression. |
| `UKFR_MEASURE_FORMAT_IN_SET` | 2 | The model shows an amount as a pound figure in thousands with the k suffix, a percentage as 0.0%, and a count of rows as #,##0, and a rank as 0. A different format string is either a new convention that needs a decision or a mistake. A measure with a format string expression is exempt. |
| `UKFR_LABEL_AUTHORED_TABLE` | 3 | A table of names or layout that I wrote (the authored tables of the README register) has a description that starts with AUTHORED, so a reader of the field list cannot take it for source data. A new authored table is added to this rule and to the register. |
| `UKFR_LABEL_AUTHORED_COLUMNS` | 3 | The visible columns of an authored dimension table sit in the display folder Authored (te/scripts/display_folders.csx). Statement Measure, a field parameter, is labelled in its description only. |
| `UKFR_LABEL_DERIVED_TABLE` | 3 | A table that holds derived numbers has (derived) at the end of its name and a description that starts with DERIVED. A table whose name ends in (synthetic) or (scale) needs a description that starts with SYNTHETIC. |
| `UKFR_LABEL_DERIVED_COLUMNS` | 3 | Visible columns of a table whose name ends in (derived) sit in the display folder Derived; those of a (synthetic) or (scale) table in the folder Synthetic. |
| `UKFR_NO_DOUBLE_AMOUNT` | 3 | Amounts are Decimal (fixed decimal, four places), never a floating point type. A Double column whose name says it is an amount, cost, spend, pay or expenditure is a mistake; index levels and shares may be Double. |
| `UKFR_DIVIDE_NOT_SLASH` | 3 | A division in a measure or a calculation item uses DIVIDE, so a zero or blank denominator gives BLANK and not an error or infinity. |
| `UKFR_NO_IFERROR` | 3 | IFERROR and ISERROR hide a wrong number behind a blank or a fallback. A measure that can fail is fixed at its cause. |
| `UKFR_RELATIONSHIP_COLUMNS_HIDDEN` | 2 | A column that a relationship uses is a key: hidden, so a report author does not put it on a visual. The financial year of Fiscal Year and Fiscal Period is the one key that is also an attribute people use. |

Authored tables are named inside `UKFR_LABEL_AUTHORED_TABLE` and in `te/scripts/display_folders.csx`: Scenario, Spending Review Group, Plan Source, Plan Grain, Statement Line and Statement Measure. A new authored table is added in both and to the README register. There are no synthetic tables yet; the derived table is Fact Plan Phased (derived).

### Standard rules I dropped

The rest of the standard set is kept. These are dropped, each with its reason. A rule goes when it depends on a service feature, on a feature this model does not use, or on VertiPaq statistics that a TMDL folder does not hold, or when a project rule replaces it with a stricter one or one that fits the model's formats.

| Rule | State | Reason |
|---|---|---|
| `AVOID_FLOATING_POINT_DATA_TYPES` | dropped | replaced by UKFR_NO_DOUBLE_AMOUNT: the model has Double columns for index levels and shares, which are not money; the project rule looks at amounts only |
| `REDUCE_USAGE_OF_LONG-LENGTH_COLUMNS_WITH_HIGH_CARDINALITY` | dropped | needs VertiPaq Analyzer annotations, which a TMDL folder does not hold |
| `LARGE_TABLES_SHOULD_BE_PARTITIONED` | dropped | partitioning serves incremental refresh, which is a service feature; the largest table has 658,554 rows |
| `MODEL_SHOULD_HAVE_A_DATE_TABLE` | dropped | the model has no calendar date table by design: time is the fiscal period dimension (test_the_model_has_no_refresh_policy_no_range_parameters_and_no_date_table) |
| `DATE/CALENDAR_TABLES_SHOULD_BE_MARKED_AS_A_DATE_TABLE` | dropped | there is no date table to mark, same reason |
| `LIMIT_ROW_LEVEL_SECURITY_(RLS)_LOGIC` | dropped | the model has no roles yet; add it back with the security work |
| `AVOID_USING_MANY-TO-MANY_RELATIONSHIPS_ON_TABLES_USED_FOR_DYNAMIC_ROW_LEVEL_SECURITY` | dropped | no roles and no many-to-many relationships; add it back with the security work |
| `CHECK_IF_DYNAMIC_ROW_LEVEL_SECURITY_(RLS)_IS_NECESSARY` | dropped | no roles in the model |
| `MODEL_USING_DIRECT_QUERY_AND_NO_AGGREGATIONS` | dropped | the model is Import; DirectQuery belongs to the scale model |
| `MEASURES_USING_TIME_INTELLIGENCE_AND_MODEL_IS_USING_DIRECT_QUERY` | dropped | the model is Import |
| `AVOID_STRUCTURED_DATA_SOURCES_WITH_PROVIDER_PARTITIONS` | dropped | the model has no provider data sources, only M partitions |
| `AVOID_THE_USERELATIONSHIP_FUNCTION_AND_RLS_AGAINST_THE_SAME_TABLE` | dropped | there are no inactive relationships and no roles (UKFR_NO_INACTIVE_RELATIONSHIPS) |
| `INACTIVE_RELATIONSHIPS_THAT_ARE_NEVER_ACTIVATED` | dropped | replaced by UKFR_NO_INACTIVE_RELATIONSHIPS, which forbids every inactive relationship |
| `USE_THE_DIVIDE_FUNCTION_FOR_DIVISION` | dropped | replaced by UKFR_DIVIDE_NOT_SLASH at severity 3 |
| `AVOID_USING_THE_IFERROR_FUNCTION` | dropped | replaced by UKFR_NO_IFERROR, which also covers ISERROR, at severity 3 |
| `FIX_REFERENTIAL_INTEGRITY_VIOLATIONS` | dropped | needs VertiPaq Analyzer annotations; relationship integrity is tested by DAX test 701 |
| `REMOVE_ROLES_WITH_NO_MEMBERS` | dropped | members of a role are assigned in the service |
| `OBJECTS_WITH_NO_DESCRIPTION` | dropped | replaced by UKFR_DESCRIBE_VISIBLE_OBJECT and UKFR_DESCRIBE_ITEM, at severity 3 |
| `PROVIDE_FORMAT_STRING_FOR_MEASURES` | dropped | replaced by UKFR_MEASURE_FOLDER_AND_FORMAT |
| `PERCENTAGE_FORMATTING` | dropped | replaced by UKFR_MEASURE_FORMAT_IN_SET: the model uses 0.0% and a pound format with a suffix, not the generic #,0.0% |
| `INTEGER_FORMATTING` | dropped | replaced by UKFR_MEASURE_FORMAT_IN_SET, same reason |
| `DATECOLUMN_FORMATSTRING` | dropped | would force the US format mm/dd/yyyy on an en-GB model, and a column named "Month Start Date" matches both this rule and the month rule with different strings |
| `MONTHCOLUMN_FORMATSTRING` | dropped | same reason as DATECOLUMN_FORMATSTRING |

## Ignores

A rule that is right in general and wrong for one object is switched off for that object with the annotation `BestPracticeAnalyzer_IgnoreRules`, written by `te/scripts/bpa_ignores.csx` from `ignores.csv`. There is no model-level ignore and no ignore of a rule for every object. Only rules of severity 2 and 3 get one. The information rules stay counted in `evidence/bpa` and are explained here instead: `ENSURE_TABLES_HAVE_RELATIONSHIPS` flags the four web tables, the field parameter and the four data-control tables that are read as they are (plan coverage, annual control, PSS control, load control), which are related to nothing on purpose (the index is matched with TREATAS, see docs/model.md; a control table is a list of checks, and a relationship would let a slicer filter an audit row), and `RELATIONSHIP_COLUMNS_SHOULD_BE_OF_INTEGER_DATA_TYPE` flags the year (`2023-24`) and grain (A to D) keys, which are text codes in the sources.

| Object | Rule | Reason |
|---|---|---|
| `measure:Fact Outturn[Outturn]` | `AVOID_DUPLICATE_MEASURES` | Outturn, Revision in Release and Outturn (current structure) have one definition (the sum of the deltas) and three names on purpose: each name says what a matrix is showing, and the calculation groups act on a measure by name. |
| `measure:Fact Outturn[Revision in Release]` | `AVOID_DUPLICATE_MEASURES` | Same definition as Outturn under a name that cannot be mistaken for a total (a release's movement of the year to date); see Outturn. |
| `measure:Fact Outturn[Outturn (current structure)]` | `AVOID_DUPLICATE_MEASURES` | Same definition as Outturn; the name says which department structure a matrix with both structures is showing; see Outturn. |
| `measure:Fact Outturn[Comparison Amount]` | `MEASURES_SHOULD_NOT_BE_DIRECT_REFERENCES_OF_OTHER_MEASURES` | The Scenario Comparison items act on this measure and pass every other measure through, so it must be a distinct measure that equals Outturn (plan basis). |
| `table:Statement Measure` | `DAX_MEASURES_UNQUALIFIED` | A field parameter refers to its measures with NAMEOF and the table name, and the engine needs the qualified form. |
| `table:Statement Measure` | `REDUCE_USAGE_OF_CALCULATED_TABLES` | The field parameter is a calculated table by definition. |
| `column:Statement Measure[Statement Measure Fields]` | `UNNECESSARY_COLUMNS` | The hidden column of a field parameter holds the references to the four measures; the engine reads it. |
| `partition:Deflator` | `MINIMIZE_POWER_QUERY_TRANSFORMATIONS` | The deflator workbooks are parsed in Power Query on purpose, by header text, so that the parsing is visible in the model and the rows that fail go to a quarantine table (docs/model.md, the deflator and CPI queries). |
| `partition:Deflator Quarantine` | `MINIMIZE_POWER_QUERY_TRANSFORMATIONS` | Same parsing as Deflator, keeping the rows that failed. |
| `partition:CPI` | `MINIMIZE_POWER_QUERY_TRANSFORMATIONS` | The ONS series are parsed in Power Query by the shape of each line, as the deflators are. |
| `partition:CPI Quarantine` | `MINIMIZE_POWER_QUERY_TRANSFORMATIONS` | Same parsing as CPI, keeping the rows that failed. |
| `column:Release[Release Sequence]` | `HIDE_FACT_TABLE_COLUMNS` | The rule reads a column used by MAX or VALUES in a measure as a fact column. Release Sequence is the ordering attribute of the Release dimension (Outturn as at Release takes its maximum, and Release sorts by it) and a reader may want it visible. |
| `column:Fiscal Year[Financial Year]` | `HIDE_FOREIGN_KEYS` | The rule matches columns by name and finds the Financial Year of Fiscal Year, which is the one side of the relationship and the only year a report author should pick; the foreign key with the same name is in Fiscal Period. |
| `column:Fact Plan Phased (derived)[Is Derived]` | `REMOVE_REDUNDANT_COLUMNS_IN_RELATED_TABLES` | The flag is on every row of the phased plan on purpose, so that the derived label travels with the data; Scenario carries the same flag for the scenario. |
| `table:Fiscal Period` | `SNOWFLAKE_SCHEMA_ARCHITECTURE` | Fiscal Period relates to Fiscal Year because the plan is published by year and outturn by period; one year dimension filters both facts (docs/model.md, what was awkward in the star schema, item 2). |
| `table:Account` | `SNOWFLAKE_SCHEMA_ARCHITECTURE` | Account relates to Statement Line, so that a statement line filters the accounts it adds up and, through them, the outturn; the layout is authored once and not copied onto the account. |
| `column:Plan Grain[Grain Code]` | `UKFR_RELATIONSHIP_COLUMNS_HIDDEN` | The grain code (A to D) is the key of Plan Grain and also the label that people read next to the grain name. |
| `column:Account[Source Codes]` | `UNNECESSARY_COLUMNS` | A hidden column that carries the spellings of the code in the releases from the warehouse view, so that a person inspecting the model can see them; no measure uses it. |
| `column:Data Quality Issue[Period Key]` | `UNNECESSARY_COLUMNS` | A hidden column that carries the period of a finding from the warehouse view, for the same reason; no measure or relationship uses it. |
| `measure:Fact Plan[Plan Source and Grain]` | `UKFR_MEASURE_FOLDER_AND_FORMAT` | A text measure: it returns a label for a page and not a number, so it has no number format. |
| `measure:Fact Plan[Plan Source and Grain]` | `UKFR_MEASURE_FORMAT_IN_SET` | A text measure: it returns a label for a page and not a number, so it has no number format. |
| `measure:Fact Outturn[Latest Release in View]` | `UKFR_MEASURE_FOLDER_AND_FORMAT` | A text measure: it returns a label for a page and not a number, so it has no number format. |
| `measure:Fact Outturn[Latest Release in View]` | `UKFR_MEASURE_FORMAT_IN_SET` | A text measure: it returns a label for a page and not a number, so it has no number format. |
| `measure:Fact Outturn[Outturn as at Release (naive)]` | `UNNECESSARY_MEASURES` | Kept on purpose as evidence: the plain form of Outturn as at Release, timed and traced in docs/performance.md and compared with the rewrite in tests 810 to 812. It is hidden and no report or measure reads it. |
| `measure:Fact Outturn[Department Group Rank (YTD Variance %) (naive)]` | `UNNECESSARY_MEASURES` | Kept on purpose as evidence: the plain form of Department Group Rank (YTD Variance %), timed and traced in docs/performance.md and compared with the rewrite in test 813. It is hidden and no report or measure reads it. |
| `column:File Control[Release Label]` | `REMOVE_REDUNDANT_COLUMNS_IN_RELATED_TABLES` | The label is repeated from Release on purpose, so that the file-control table shows each release without a Release column and its as-at measure reads the release from the file row. |

## Running it

```
TabularEditor model/UKGroupFinance.SemanticModel/definition -A te/bpa/rules.json -T <scratch>/bpa.trx
python tools/summarise_bpa.py --trx <scratch>/bpa.trx --check evidence/bpa
```

Pass Tabular Editor the `definition` folder with no trailing backslash. `--write` replaces `--check` after a reviewed change. The rule file has LF line endings, which Tabular Editor 2.29.0 loads (the CRLF requirement that some guides give did not show up). **Tested**: `pipeline/tests/test_model_scripts.py`.
