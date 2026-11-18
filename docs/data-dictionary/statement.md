# Data dictionary: the group income and expenditure statement

The layout I wrote for treating central government as a group: income, then expenditure by kind, net expenditure
for resource and for capital, and a total that equals the outturn. This page describes the two authored files, the
three warehouse tables they resolve to, the view that computes the statement in SQL, and the judgements the account
dimension forced. Amounts are GBP thousands, spending positive, income negative, `DECIMAL(19,4)`. Every claim is
labelled **tested** (the test or command) or **designed** (not run).

The layout holds no amount. It decides which line of the statement a real amount is added to. The amounts are
`dw.fact_outturn` and `dw.fact_plan`, untouched.

## Register of authored data

| Object | What it is | Why | Where it can reach |
|---|---|---|---|
| `authored/statement_line.csv` (`authored.statement_line`, `stg.statement_line`, `dw.statement_line`) | 39 rows, one per line of the statement: label, order, type (detail, subtotal, total, spacer), sign presentation, indent, the lines a subtotal adds up, the plan scope | no source publishes a statement for the whole of central government; this is mine | nothing: no amount column (**tested**: `sql/tests/745`) |
| `authored/statement_account_rule.csv` (`authored.statement_account_rule`, `stg.statement_account_rule`) | 31 rules that send an account to a detail line | the economic categories are OSCAR's; which of my lines each belongs to is a judgement | nothing: it moves an account to a line, the amounts are the facts' (**tested**: `sql/tests/740`, `741`) |

Both files carry an `evidence` and a `note` column on every row. `ukfr build` loads them through the generic authored
stage, `sql/stg/740_statement_line.sql` types them and stops the build on a broken rule, `sql/dw/740_statement_line.sql`
resolves them.

## The layout

| Column of `statement_line.csv` | Meaning |
|---|---|
| `line_id` | short id: `R` resource, `C` capital, `N` other, `S` spacer, `T` total; the number leaves room to insert a line |
| `label` | what the line is called; blank for a spacer (the build writes a distinct zero-width label) |
| `sort_order` | where it prints; unique |
| `line_type` | `detail` adds the accounts its rules select; `subtotal` and `total` add other lines; `spacer` has no amount |
| `sign_presentation` | `as reported` (spending positive, income negative) or `income positive` (the sign of the line is reversed, so income reads as a positive number) |
| `indent_level` | 2 for a detail line, 1 for a subtotal, 0 for a net or total line |
| `members` | the line ids a subtotal or total adds up, separated by spaces; each must be an earlier line, so a line can never add itself |
| `plan_scope` | `RESOURCE`, `CAPITAL` or `ALL` on the three lines that sit at a published plan's grain; blank elsewhere |

The statement as it is laid out (detail lines are indented two steps):

```
Resource income        Sales of goods and services | Fees, charges, levies and fines | Interest and dividends receivable |
                       Grants and contributions received | Pension contributions and pension income |
                       Release of provisions | Other resource income
Total resource income  (income positive)
Resource expenditure   Pay | Purchase of goods and services and rentals | Grants to local government |
                       Benefits and grants to persons and non-profit bodies | Subsidies and grants abroad |
                       Public service pensions | Depreciation and impairments | Provisions | Interest payable |
                       Other resource expenditure
Total resource expenditure
Net resource expenditure          = total resource income + total resource expenditure   (plan scope RESOURCE)
(spacer)
Capital income         Sales of assets | Capital grants received | Loan repayments and investment disposals | Other capital income
Total capital income   (income positive)
Capital expenditure    Purchase of assets | Capital grants paid | Lending and investment |
                       Research and development in capital budgets | Other capital expenditure
Total capital expenditure
Net capital expenditure           = total capital income + total capital expenditure     (plan scope CAPITAL)
(spacer)
Other                  Non-budget transfers and funds | No economic category
Net other items
(spacer)
Net expenditure                   = net resource + net capital + net other items         (plan scope ALL)
```

**DEL and AME are not rows.** They are a property of the outturn line (the control budget), not of the account, so
the statement has them as columns: put `Control Budget[Control Budget]` on the columns and the same lines split into
DEL, AME and Non-budget. **Tested**: DAX test 742 (six lines, two years, every control budget) equals SQL.

## How an account reaches a line

`statement_account_rule.csv` has one row per rule: a `line_id` and any of `economic_budget`, `flow`,
`pesa_economic_group_code` and `economic_category_code` (blank means any; a field may list values separated by `|`).
Where several rules select one account the most specific wins: a category rule (weight 8) beats a group rule (4),
which beats a flow rule (2), which beats an economic budget rule (1). Each line has a default rule (economic budget
and flow only) that catches what no more specific rule does, so a new category that OSCAR adds lands in "Other ..."
and the statement still ties; the build stops only if a category matches no rule at all, or two rules of the top
weight name different lines.

Attributes of `dw.dim_account` that the rules read (the dimension is described in
[outturn.md](outturn.md)): `economic_budget` (RESOURCE, CAPITAL, OTHER NON-BUDGET, NA, Unknown), `flow`
(Expenditure, Income, Not applicable: the digit rule with 12 authored exceptions), `pesa_economic_group_code` and
`economic_category_code`.

**Coverage.** Every one of the 128 accounts (127 categories and the Unknown member) maps to exactly one of the 28
detail lines. **Tested**: `sql/tests/740` resolves the rules a second way (with `LIKE` on the rule lists) and
compares, and reports an account with no line, two rows, a line that is not a detail line, two rules of the top
weight that disagree, and a detail line with no account.

| Line | Accounts | Economic categories |
|---|---:|---|
| R10 Sales of goods and services | 1 | B102 |
| R11 Fees, charges, levies and fines | 3 | T102 T202 T302 |
| R12 Interest and dividends receivable | 7 | J102 J302 S102 S202 S302 S502 S602 |
| R13 Grants and contributions received | 5 | D102 D132 D202 D502 D602 |
| R14 Pension contributions and pension income | 3 | D402 D412 D422 |
| R15 Release of provisions | 4 | L102 L402 L412 M102 |
| R19 Other resource income | 9 | A102 C302 Q102 R802 T402 X102 X202 X402 Y102 |
| R30 Pay | 1 | A101 |
| R31 Purchase of goods and services and rentals | 2 | B101 Q101 |
| R32 Grants to local government | 2 | D501 Y103 |
| R33 Benefits and grants to persons and non-profit bodies | 2 | D111 D121 |
| R34 Subsidies and grants abroad | 3 | C101 C301 D201 |
| R35 Public service pensions | 5 | D401 D411 L401 L411 L501 |
| R36 Depreciation and impairments | 5 | P101 P201 P301 P401 Z201 |
| R37 Provisions | 4 | L101 L201 M101 M201 |
| R38 Interest payable | 4 | S101 S301 S501 S601 |
| R39 Other resource expenditure | 11 | D601 F201 R101 R201 R501 R801 X101 X201 X401 Y101 Z101 |
| C10 Sales of assets | 4 | E102 E112 E202 F102 |
| C11 Capital grants received | 5 | G102 G132 G202 G502 G602 |
| C12 Loan repayments and investment disposals | 8 | H102 H132 H202 H302 H502 H602 K102 K302 |
| C19 Other capital income | 3 | B202 E302 R902 |
| C30 Purchase of assets | 5 | E101 E111 E201 E211 F101 |
| C31 Capital grants paid | 7 | E501 G101 G131 G201 G301 G501 G601 |
| C32 Lending and investment | 8 | H101 H131 H201 H301 H501 H601 K101 K301 |
| C33 Research and development in capital budgets | 6 | A201 B201 C201 C401 D701 D801 |
| C39 Other capital expenditure | 6 | E301 R301 R401 R901 Z301 Z401 |
| N10 Non-budget transfers and funds | 3 | U101 U201 U301 |
| N20 No economic category | 2 | NA UNK |

The counts add to 128 (**tested**: `sql/tests/740`; the list is `dw.account_statement_line` joined to `dw.dim_account`).

## Judgements the account dimension forced

Each is a choice I made and can be changed in the rule file; none moves a number between years or hides one.

1. **The flow of an account decides whether it is income or expenditure, not its sign.** 125 of the 128 categories
   carry both signs in the outturn (a repayment in an expenditure category, a refund in an income category), so the
   sign cannot place an account. I use `dw.dim_account.flow`, the digit rule with the 12 authored exceptions in
   `authored/account_flow.csv`. A line therefore adds expenditure and income categories each at their net: R101 (Loan
   write-offs, an expenditure category) nets to -26.7bn across all years of data and sits in "Other resource expenditure"
   as a negative. Evidence: `sql/tests/308` and `docs/profiling/data/` for the flow exceptions.
2. **The PESA economic group does not follow my lines in four places, so those accounts are listed by code.** Interest
   payable and receivable, pay-like and write-off categories, non-ringfenced depreciation (P401), grants received
   (D102, D602) and the expected-credit-loss utilisation (M102) all sit in the PESA groups Other resource or Take up of
   provisions, which mix unlike items. The category rules are weight 8 and say why in their `note`.
3. **Capital R&D categories.** OSCAR's capital budget carries pay (A201), purchases (B201), subsidies (C201, C401) and
   current grants (D701, D801) marked R&D. They belong to the capital budget, because that is what the plan is set
   on, so they stay in the capital block as "Research and development in capital budgets" and not in resource pay.
4. **Resource and capital are the economic budget, so the net lines are exactly the plan's budgets.** `Net resource
   expenditure` holds every account whose economic budget is RESOURCE and `Net capital expenditure` every account
   whose economic budget is CAPITAL. **Tested**: `sql/tests/743`. This is why the plan can be compared with them.
5. **Lines with no economic category.** The code NA (and the Unknown member) is not income or expenditure. It carries
   78.6bn in 2019-20 and -29.2bn in 2024-25 (`dw.v_statement_pnl`, line N20), nearly all of it in the control budget
   Non-budget (see the evidence below). I keep it in its own line, inside "Net other items", so it
   is visible and the statement still equals `Outturn`. I did not guess what it is.
6. **Non-budget transfers.** The three OTHER NON-BUDGET accounts (U101 the devolved administration transfer, U201,
   U301 the Social Fund) are one line, "Non-budget transfers and funds", outside resource and capital. In 2024-25 the
   line is 94.9bn; I read U101 as the devolved administration transfer from its name and have not checked it against
   a published account.

Evidence for 5, from a query on `dw.fact_outturn` (GBP thousands, 2019-20, economic budget NA): control budget
NON-BUDGET 78,590,370; DEL ADMIN -7; DEL PROG -125, which sum to the 78,590,238 on N20. No test pins these three
figures; test 741 and 745 show the line is in the total and that it holds the Unknown account once.

## Sign presentation

A line is `as reported` or `income positive`. The detail income lines and the two income totals are income positive,
so income reads as a positive number and a finance reader sees income and expenditure as two positive blocks; the net
and total lines are as reported (net spending positive). A subtotal sums the **as reported** amounts of the detail lines
under it and applies its own sign once, so `Net resource expenditure` is resource expenditure plus resource income
(income negative) and not a sum of presented numbers. The measure applies the sign by the line in context. **Tested**:
`sql/tests/744` (presented amount is the reported amount times the sign factor, and an income-positive line holds
income accounts only).

## Tables and views

| Object | Rows | What it is |
|---|---:|---|
| `stg.statement_line`, `stg.statement_account_rule` | 39; 31 | typed copies of the authored files; the build stops on a bad type, label, member or rule |
| `dw.statement_line` | 39 | the layout resolved: `line_key` is the place on the statement; `sign_factor` is -1 or 1; `detail_line_keys` is `|3|4|5|`, the detail lines the line adds up |
| `dw.statement_line_member` | 110 | line x every detail line it adds up; `path_count` is 1 everywhere, so no amount is added twice (the build stops otherwise) |
| `dw.account_statement_line` | 128 | account x its one detail line, the winning rule and its weight |
| `dw.v_statement_pnl` | one row per line and year with an amount or a plan | the statement computed in SQL from `dw.fact_outturn` and `dw.fact_plan` (below); never read by the model |
| `dw.v_model_statement_line` | 39 | the layout for the model |
| `dw.v_model_account` | 128 | `dw.dim_account` plus `statement_line_key`, moved from `sql/dw/701` to `sql/dw/741` because it now reads `dw.account_statement_line` |

Row counts: committed scope, `evidence/build/table_counts.csv`.

## `dw.v_statement_pnl`

One row per statement line (not a spacer) and financial year, from `dw.fact_outturn` and `dw.fact_plan`. It is the
expectation for the model's statement measures (DAX tests 740 to 752), and it is a separate implementation from the
DAX: it reads the dimensions' attributes and `dw.plan_measure_selection`, and writes the rules of the five voted
budgets itself.

| Column | Meaning |
|---|---|
| `outturn_as_reported` | the sum of the line's detail lines, spending positive |
| `outturn` | the same in the sign the line is presented in |
| `plan_amount` | the published plan, only on a line with a plan scope and only where the source gives a plan at that level |
| `outturn_plan_basis` | where there is a plan, the outturn on the plan's basis, within the line's economic budget |

**Which plan a line has.** Only the three lines with a plan scope. `RESOURCE` and `CAPITAL` have a plan only in a
year in which every plan row is OSCAR Plans (FY2017-18 to FY2021-22), which are published by economic budget. `ALL`
has a plan in every year that has one (FY2017-18 to FY2028-29). The later sources (Estimates, PESA) are published by
Spending Review group and measure, with no economic budget below resource DEL excluding depreciation and capital DEL,
so a plan for the net resource line in 2024-25 does not exist and the measure is BLANK, not an invention.

**Which plan measures are compared.** The five voted budgets: RDEL, RDEL excluding depreciation, CDEL, departmental AME
resource and capital. I left out administration (part of resource DEL), and OSCAR Plans' non-departmental AME,
non-budget and unclassified measures, because the non-budget plan is published gross and the outturn is net: in 2019-20
the resource non-budget plan is 791,549,206 against an outturn on those control budgets of -9,323,463 (GBP thousands,
`dw.fact_plan` and `dw.fact_outturn`), and comparing them would make the net resource variance of 2019-20 read as about -970bn. This is a
decision of mine; the model's own `Plan` and `Comparison Amount` still include those measures.

**Tested**: `sql/tests/741` (the total line equals the fact in every year, and so does the sum of the detail lines),
`742` (every subtotal is the sum of its listed members, no detail line is reached by two paths, a spacer has no amount),
`743` (the net lines hold exactly the accounts of their economic budget and the total every account once), `744` (labels
distinct, signs), `745` (authored labels, no amount column), `746` (the plan of 2024-25 is the sum of the four
published budgets).

## One year as it prints

2019-20, GBP millions (`dw.v_statement_pnl`; the plan is OSCAR Plans, RDEL and departmental AME for resource, CDEL and
departmental AME for capital; Variance is the outturn on the plan's basis less the plan):

| Line | Outturn | Plan | Outturn on plan basis | Variance |
|---|---:|---:|---:|---:|
| Total resource income | 141,668.8 (income positive) | | | |
| Total resource expenditure | 894,162.8 | | | |
| Net resource expenditure | 752,493.9 | 828,756.5 | 757,250.7 | -71,505.7 |
| Total capital income | 12,377.6 (income positive) | | | |
| Total capital expenditure | 102,071.4 | | | |
| Net capital expenditure | 89,693.7 | 99,978.9 | 90,959.3 | -9,019.6 |
| Net other items | 126,669.0 | | | |
| Net expenditure | 968,856.7 | 928,735.4 | 848,210.0 | -80,525.3 |

Resource expenditure plus resource income (income negative) is 894,162.8 - 141,668.8 = 752,494.0, which is the net line
to rounding. The variance is negative on every plan line: outturn under plan, which is favourable with spending
positive. The plan of the total line is the plan of the resource and capital lines added (828,756.5 + 99,978.9 =
928,735.4), and so is its outturn on the plan's basis (757,250.7 + 90,959.3 = 848,210.0), because in an OSCAR Plans year
the four measures RDEL, RAME, CDEL and CAME are published by economic budget, resource or capital, and the total line
adds the same rows. The total line has a
plan and the net other items line does not, so the total line's outturn (968,856.7) is larger than the net resource and
net capital outturn together (842,187.6) by the 126,669.0 of net other items, which the plan has no line for. In
2024-25 the plan exists only on the total line (1,256,541.0 against 1,132,794.6 on the plan's basis, variance
-123,746.4).

## Not covered

- A plan for a detail line, an income line or the net resource line after FY2021-22: no source publishes one.
- A statement by department (the measure works with any department selected; the plan is BLANK there).
- Real terms, restatements and a notes page: later work.
