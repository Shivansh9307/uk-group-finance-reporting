# Data dictionary: the allocation of a shared-cost pool, and the what-if settings

What `ukfr build --scope full` puts in the database for the allocation of one real pool across departments by payroll full-time
equivalent, and for the invented what-if settings that sit beside it. The pool is real, the weights are real, the allocation is
my own rule and the what-if percentages are invented, and each of the three classes is kept apart and labelled. Every claim is
labelled **tested** (the test or command) or **designed** (not run).

The pool needs the in-year outturn and the weights need the workforce files, which are not in git, so the SQL objects of the
allocation are scope `full`, and the tests that read them carry `-- marker: localdata`. The what-if settings are a committed
file (`synthetic/whatif_parameter.csv`), so they are built in both scopes.

## What it is, and what it is not

It is a worked example of a weighted many-to-many allocation in the semantic model: a real cost that sits in one department, spread
across the departments that publish a workforce, with a stored weight, a stated rounding rule and a tie to the pool. It is **my own
allocation**. It is not a government policy, a recharge or a charge that any department pays, and the Cabinet Office administration
budget is mostly the Cabinet Office's own running cost, so I do not claim it is a shared service pool in the accounting sense
(`authored.allocation_rule.not_this` says so in the database, the table description of `Allocation Rule` says so in the model, and
the page says so).

## The pool

`authored.allocation_rule` (`sql/authored/940_allocation_rule.sql`, one row, class authored, scope full) names the pool:

| Field | Value |
|---|---|
| Rule | `CO_ADMIN_FTE`: Cabinet Office administration spend, spread by payroll full-time equivalent |
| Pool | the outturn of the Cabinet Office (department 010 of the current structure) in the control budget detail `DEL ADMIN`, all economic categories, GBP thousands, spending positive; the latest view of each financial year (the sum of the revision deltas of every release) |
| Basis | payroll full-time equivalent |
| Years | 2018-19 to 2025-26 (the closed years: 2026-27 is a part year and is not allocated) |
| Minimum months | 9 of 12 |

I chose it by profiling the Cabinet Office outturn by control budget detail and year: DEL ADMIN is a single, clearly defined
control budget detail with a real outturn in every closed year (GBP 204.7m to GBP 627.4m, against GBP 485.0m to GBP 1,460.5m for
DEL PROG, which is programme spend and not a running cost). The Cabinet Office does not appear in the workforce source, so it is
never both pool and weight, and the allocation of a central cost by the number of people a department employs is the plainest
basis there is. I did not profile other departments as candidates, so I cannot say it is the best pool. It is a judgement and not
a result (**designed**).

`dw.allocation_pool` holds the pool of each rule and year (8 rows). **Tested** (`sql/tests/942`): each pool equals a second
computation that reads no delta, the line snapshot of the last release that reports the year (`stg.outturn_line_snapshot`, what the
release file states), with the department found through the current-structure map and the sub-segment code. The two agree in all
eight years, to the last decimal.

| Year | Pool (GBP thousands) |
|---|---:|
| 2018-19 | 204,650 |
| 2019-20 | 346,886 |
| 2020-21 | 362,400 |
| 2021-22 | 627,437 |
| 2022-23 | 471,517 |
| 2023-24 | 625,341 |
| 2024-25 | 502,103 |
| 2025-26 | 602,847 |

## The weights

A department takes part in a year if it has a **valid payroll cell** (the cells of the pay bridge: a positive full-time equivalent and
paybill and no row-arithmetic fault, `dw.v_pay_cell`) in at least 9 of the 12 months. Its full-time equivalent for the year is the
average, over the months in which it has a valid cell, of the sum of its valid cells in the month (an organisation counts once a
month; agencies counted in a parent are in the parent), rounded to four decimals. Its weight is that over the sum of the
participants'. The weights of a year add to 1 (**tested**: `sql/tests/943`, within 0.000000001).

`audit.allocation_participation` has one row for every department with at least one valid cell in a year of the rule (121 rows): the
months present, the full-time equivalent, the least and most organisations in a month present (a department's cells are not always
all there), its status, and for a department left out the weight it would have had.

**Tested** (`sql/tests/943`): the participants, their months present, their average full-time equivalent and their weight equal a
second computation that starts again from the raw rows of `dw.workforce_month` (the valid cells found again, the organisation version
in force found by a window function) and compares the two with equality on the set of participants and 0.0001 on the average.

### Who is left out, and the effect

Who is not in the weights is the most important limit of the allocation, and each of the three groups has its own count in
`audit.allocation_year_summary` and in the model's `Allocation Coverage` table.

- **The workforce source does not hold them.** The Home Office, the Ministry of Justice, the Cabinet Office (the pool's own
  department) and the Office for National Statistics are not in it, and neither are most small bodies and the pension schemes. Between
  35 and 44 live departments of the current structure have no valid cell in a year (35 in 2025-26). They get no weight and no allocated
  amount, so the departments that are in the source carry the whole pool. If the Home Office and the Ministry of Justice had been in
  the source, every weight would be smaller. I cannot say by how much: that is the missing data, not a result.
- **Too few months.** A department with some valid cells but fewer than 9 months in a year is left out of that year and listed with
  the weight it would have had. The effect is large in some years: the Ministry of Defence in 2022-23 has 8 months and would carry
  13.6% of the pool, the Department for Environment, Food and Rural Affairs in 2018-19 and 2020-21 has 2 and 4 months (a run of missing
  files, see [workforce.md](workforce.md)) and would carry 7.4% and 8.1%. Taken together the departments left out for too few months
  would have carried 9.0% of the full-time equivalent in 2018-19, 8.2% in 2020-21, 1.2% in 2021-22, 15.6% in 2022-23, 2.7% in 2023-24
  and 1.6% in 2024-25, and none in 2019-20 and 2025-26 (their full-time equivalent over the participants' plus their own). Dropping them moves their share of the pool to the others, which is the rule
  and which I show; an allocation that estimated their missing months would be a second, larger judgement.
- **Partial organisations in a month.** A department's monthly full-time equivalent is the sum of its valid cells, and a cell can be
  missing for one month (one organisation not reported). The department's average then dips for that month. The least and most
  organisations in a month are in the participation table, so the dip can be seen; I did not repair it.

**Tested** (`sql/tests/945`): every department with a valid cell has a participation row, status follows the minimum months, a
department left out has no allocation row and the weight it would have had equals its full-time equivalent over the participants'
plus its own, and the year summary counts are recomputed from the participation table and the department dimension.

## The allocation

`dw.fact_allocation` has one row per rule, year and participating department (108 rows; 10 to 20 departments a year):

| Column | Meaning |
|---|---|
| `pool_amount` | the pool of the year, GBP thousands, the same on every row of the year |
| `avg_fte`, `months_present` | the department's average monthly full-time equivalent and the months it rests on |
| `weight` | `avg_fte` over the participants' sum, `DECIMAL(19,10)` |
| `allocated_amount` | the pool times the weight, `DECIMAL(19,4)`, with the rounding adjustment included |
| `rounding_adjustment`, `is_rounding_row` | zero on every row but one a year |
| `paybill_annualised` | the average monthly paybill of the valid cells over the months present times 12, GBP thousands (the files are in pounds) |

**Rounding rule.** The allocated amount is `pool x full-time equivalent / sum of the participants' full-time equivalent`, worked in
integers of a ten-thousandth of a thousand pounds so that no decimal scale is lost, and rounded half away from zero to four
decimals (GBP thousands, so to ten pence). The remainder to the pool is put on the participant with the largest
full-time equivalent (the lower department number on a tie), so that the allocated amounts add up to the pool exactly. The
adjustment is stored on its row, flagged in `is_rounding_row`, and summed in the audit; it is never hidden. It is small: the largest in
any year is 0.0002 (GBP 0.20).

### The tie, year by year (**tested**: `sql/tests/944`, `audit.allocation_year_summary`)

| Year | Pool | Sum of allocated | Difference | Rounding adjustment | Departments taking part |
|---|---:|---:|---:|---:|---:|
| 2018-19 | 204,650.0000 | 204,650.0000 | 0.0000 | 0.0000 | 11 |
| 2019-20 | 346,886.0000 | 346,886.0000 | 0.0000 | -0.0001 | 11 |
| 2020-21 | 362,400.0000 | 362,400.0000 | 0.0000 | 0.0002 | 10 |
| 2021-22 | 627,437.0000 | 627,437.0000 | 0.0000 | -0.0001 | 13 |
| 2022-23 | 471,517.0000 | 471,517.0000 | 0.0000 | 0.0001 | 12 |
| 2023-24 | 625,341.0000 | 625,341.0000 | 0.0000 | -0.0001 | 15 |
| 2024-25 | 502,103.0000 | 502,103.0000 | 0.0000 | 0.0000 | 16 |
| 2025-26 | 602,847.0000 | 602,847.0000 | 0.0000 | 0.0002 | 20 |

The tie is not true by construction: the remainder is what makes the sum exact, so the check that the sum equals the pool would hold
whatever the pool. The test therefore compares the sum with the pool taken from the release snapshot (the second route of the pool
test) and not with `dw.allocation_pool`, checks that each non-remainder amount is the pool times the weight within the rounding of the
stored amount (0.00006 in GBP thousands, six pence), that the remainder row is the participant with the largest full-time
equivalent, and that the stored adjustment is no more than half a unit of the last place for each participant.

### The weights of the latest year (2025-26)

20 departments take part; DWP has 11 months of data, DEFRA 11, DESNZ 11, Ofgem 11 and UK Export Finance 9.

| Department | Months | Average full-time equivalent | Weight | Allocated (GBP thousands) |
|---|---:|---:|---:|---:|
| Work and Pensions (032) | 11 | 88,990.4 | 23.89% | 144,030.1 |
| HM Revenue and Customs (041) | 12 | 68,074.2 | 18.28% | 110,177.6 |
| Defence (017) | 12 | 54,774.8 | 14.71% | 88,652.6 |
| Environment, Food and Rural Affairs (003) | 11 | 31,048.3 | 8.34% | 50,251.4 |
| Health and Social Care (033) | 12 | 29,448.8 | 7.91% | 47,662.5 |
| Transport (004) | 12 | 17,656.3 | 4.74% | 28,576.5 |
| Science, Innovation and Technology (084) | 12 | 16,434.1 | 4.41% | 26,598.4 |
| Education (022) | 12 | 12,213.1 | 3.28% | 19,766.8 |
| Business and Trade (013) | 12 | 11,426.8 | 3.07% | 18,494.1 |
| Energy Security and Net Zero (066) | 11 | 9,840.9 | 2.64% | 15,927.4 |
| FCDO (030) | 12 | 7,955.4 | 2.14% | 12,875.7 |
| HM Land Registry (078) | 12 | 6,274.0 | 1.68% | 10,154.4 |
| National Crime Agency (073) | 12 | 5,737.0 | 1.54% | 9,285.3 |
| Housing, Communities and Local Government (085) | 12 | 3,429.2 | 0.92% | 5,550.1 |
| HM Treasury (087) | 12 | 2,716.6 | 0.73% | 4,396.9 |
| Ofgem (020) | 11 | 2,226.0 | 0.60% | 3,602.7 |
| Food Standards Agency (026) | 12 | 1,540.6 | 0.41% | 2,493.4 |
| Culture, Media and Sport (048) | 12 | 1,094.4 | 0.29% | 1,771.3 |
| Competition and Markets Authority (076) | 12 | 1,020.5 | 0.27% | 1,651.7 |
| UK Export Finance (025) | 9 | 573.3 | 0.15% | 927.9 |

The Home Office, the Ministry of Justice and the Cabinet Office are not in the table (the source does not hold them). The five
departments with 11 months or fewer rest on that many months; I did not estimate the months they lack.

## The what-if settings

`synthetic/whatif_parameter.csv` (`synthetic.whatif_parameter`, 5 rows, class synthetic, `sql/synthetic/940_whatif_parameter.sql`) holds
five settings, each a pay award and a headcount change in per cent:

| Setting | Pay award | Headcount change | Where the values come from |
|---|---:|---:|---|
| Base (the default) | 3.4% | 0% | pay award: the ONS CPI annual rate (series D7G7) for 2025, from the copy of the series the repository already holds (`data/raw/ons_cpi/latest/d7g7.csv`, source `ons_cpi` in the manifest); headcount: invented, no change |
| Pay award 1 point lower | 2.4% | 0% | invented: the base less one point |
| Pay award 1 point higher | 4.4% | 0% | invented: the base plus one point |
| Headcount down 5 per cent | 3.4% | -5% | headcount invented |
| Headcount up 5 per cent | 3.4% | +5% | headcount invented |

No ONS series that gives a headcount path is in the repository, so every headcount value is a plainly invented round number and says
so in its basis column. I did not add a data source. The table holds percentages and no amount, only `dw.v_model_whatif_setting` reads
it and nothing reads that view. **Tested**: `sql/tests/940` (labelled SYNTHETIC, one default setting, the base rate is the 3.4 it names, one
reader, no foreign key, no amount column and no what-if column in a view of a real fact), `pipeline/tests/test_synthetic.py` (the
file's columns and bases, and, where the data folder is present, that the 2025 value of the ONS file is 3.4).

The settings are per setting and not per year as the design asked: a what-if on a closed year is a counterfactual that nobody needs,
so the what-if measures apply the setting in context to whichever year the visual shows (the page fixes 2025-26). I changed the design for
that reason and say so in the model page.

## What a later task reads

| Object | Grain | Use |
|---|---|---|
| `authored.allocation_rule` | rule | the pool, basis, years, minimum months and rounding rule |
| `dw.allocation_pool` | rule x year | the real pool |
| `audit.allocation_participation` | rule x year x department | who takes part, the full-time equivalent and the weight a department left out would have had |
| `dw.fact_allocation` | rule x year x participating department | the weight and the allocated amount |
| `audit.allocation_year_summary` | rule x year | the tie, the rounding adjustment and the coverage counts |
| `dw.v_model_allocation_*`, `dw.v_model_whatif_setting` | | what the model reads |

## Limitations

- The pool is a department's own administration cost, spread across other departments by a rule I made up; the amounts are not
  anyone's cost.
- The weights rest on a workforce source that holds a subset of departments, and on a rule that drops a department with fewer than
  nine months in a year. A department's years differ in how many months and organisations they rest on, and that is shown, not repaired.
- A year's weights are each a department's full-time equivalent over the participants' of the year; the participants change from year to
  year (11 to 20), so a department's weight can fall because more departments entered the source, not because it shrank.
- The what-if is illustrative: a pay award applied to the allocated amount assumes the pool is staff cost, which I did not test.
