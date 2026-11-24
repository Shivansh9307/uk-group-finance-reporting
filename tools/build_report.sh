#!/usr/bin/env bash
# Builds the pages of model/UKGroupFinance.Report with the pbir CLI, one function per page. It is the record of how the
# report was made: no report file is edited by hand. Run from Git Bash, from anywhere, with the theme already applied
# (pbir theme apply-template UKGroupFinance.Report ukfr-finance):
#
#   bash tools/build_report.sh exec          # build one page (the page must not exist yet)
#   bash tools/build_report.sh all           # every page, in order
#   bash tools/build_report.sh filters       # the report-level filter on the plan measure (see report_filters)
#
# Moving a visual next to another trips pbir's overlap check part-way, so the script runs with PBIR_ALLOW_OVERLAP=1;
# `pbir validate --qa` is run afterwards and decides.
set -u
cd "$(dirname "$0")/../model"
export PBIR_ALLOW_OVERLAP=1
R="UKGroupFinance.Report"
ERR="${TMPDIR:-/tmp}/build_report.err"
: >"$ERR"
P=""

# --------------------------------------------------------------------------------------------------- helpers
q() { pbir -q "$@" >/dev/null 2>>"$ERR" || echo "FAILED: pbir $*" >&2; }

# page_new NAME: a page of 1280 x 720 with its automatic title removed (header() builds the header)
page_new() {
  P="$R/$1.Page"
  q add page "$P" -n "$1" --width 1280 --height 720
  q rm "$P/*.Visual" -f
}

# header TITLE SUBTITLE [nav]: title, subtitle, latest release label and, unless nav is 'no', the page navigator
header() {
  q add title "$P" "$1" --width 780
  q add subtitle "$P" "$2" --width 1020
  q visuals rename "$P/Title.Visual" --to page_title -f
  q visuals rename "$P/Subtitle.Visual" --to page_subtitle -f
  q visuals position "$P/page_title.Visual" --x 24 --y 0 --width 780 --height 52
  q visuals position "$P/page_subtitle.Visual" --x 24 --y 52 --width 1020 --height 38
  q visuals general "$P/page_title.Visual" --altText "Page title: $1"
  q visuals general "$P/page_subtitle.Visual" --altText "Page basis: $2"
  card latest_release "Latest release" 1064 8 192 76 "Fact Outturn.Latest Release in View" \
    "The month of the latest OSCAR in-year release loaded into the model" 16
  if [ "${3:-nav}" != "no" ]; then
    q add visual pageNavigator "$P" -n page_nav -x 24 -y 92 -w 1232 -h 36
    q visuals general "$P/page_nav.Visual" --altText "Page navigation buttons, one for each page of the report"
  fi
}

# text NAME X Y W H TEXT: a static text box (pbir writes its text at 14 points, grey)
text() {
  q add subtitle "$P" "$6" --width "$4"
  q visuals rename "$P/Subtitle.Visual" --to "$1" -f
  q visuals position "$P/$1.Visual" --x "$2" --y "$3" --width "$4" --height "$5"
  q visuals general "$P/$1.Visual" --altText "$6"
}

# card NAME TITLE X Y W H FIELD ALT [SIZE] [wrap]: a new-card visual on one field (Table.Field). The value shows in the
# unit the Display Unit calculation group gives it (no card display units), at SIZE points; wrap lets a text value
# run over several lines.
card() {
  q add visual cardVisual "$P" -n "$1" -t "$2" -x "$3" -y "$4" -w "$5" -h "$6" -d "Data:$7"
  q visuals general "$P/$1.Visual" --altText "$8"
  q set "$P/$1.Visual.label.show" --value false
  q set "$P/$1.Visual.value.labelDisplayUnits" --value 1
  q set "$P/$1.Visual.value.fontSize" --value "${9:-20}"
  if [ "${10:-}" = "wrap" ]; then
    q set "$P/$1.Visual.value.textWrap" --value true
    q set "$P/$1.Visual.value.horizontalAlignment" --value left
  fi
}

# vf VISUAL TABLE FIELD VALUE...: a visual-level filter that fixes the values (never a slicer selection)
vf() {
  local v="$1" t="$2" f="$3"; shift 3
  q add filter "$t" "$f" -v "$P/$v.Visual" --values "$1"
  if [ "$#" -gt 1 ]; then
    local args=() x
    for x in "$@"; do args+=(--values "$x"); done
    q filters set "$P/$v.Visual/$t.$f.Filter" "${args[@]}"
  fi
}

# pf TABLE FIELD VALUE...: a page-level filter that fixes the values
pf() {
  local t="$1" f="$2"; shift 2
  pbir -q rm "$P/$t.$f.Filter" -f >/dev/null 2>&1
  q add filter "$t" "$f" -p "$P" --values "$1"
  if [ "$#" -gt 1 ]; then
    local args=() x
    for x in "$@"; do args+=(--values "$x"); done
    q filters set "$P/$t.$f.Filter" "${args[@]}"
  fi
}

# visual TYPE NAME TITLE X Y W H ALT DATA...: a chart or table with its data bindings (Role:Table.Field)
visual() {
  local type="$1" name="$2" title="$3" x="$4" y="$5" w="$6" h="$7" alt="$8"; shift 8
  local args=() d
  for d in "$@"; do args+=(-d "$d"); done
  q add visual "$type" "$P" -n "$name" -t "$title" -x "$x" -y "$y" -w "$w" -h "$h" "${args[@]}"
  q visuals general "$P/$name.Visual" --altText "$alt"
}

# badge NAME X Y W H ALT FY: the plan badge, a one-column table whose text wraps (a card clips a long text)
badge() {
  visual tableEx "$1" "" "$2" "$3" "$4" "$5" "$6" "Values:Fact Plan.Plan Source and Grain"
  q visuals title "$P/$1.Visual" --no-show
  q set "$P/$1.Visual.values.wordWrap" --value true
  q set "$P/$1.Visual.values.fontSize" --value "${8:-10}"
  q set "$P/$1.Visual.columnHeaders.fontSize" --value "${8:-10}"
  vf "$1" "Fiscal Year" "Financial Year" "$7"
}

# button NAME LABEL X Y W H TYPE [TARGET]: an action button (Back, PageNavigation or Drillthrough)
button() {
  q add visual actionButton "$P" -n "$1" -x "$3" -y "$4" -w "$5" -h "$6"
  q visuals action "$P/$1.Visual" --type "$7" ${8:+--target "$8"}
  q set "$P/$1.Visual.text.show" --value true
  q set "$P/$1.Visual.text.text" --value "$2"
  q visuals title "$P/$1.Visual" --no-show
  q visuals general "$P/$1.Visual" --altText "$2"
}

# ------------------------------------------------------------------------------------------------------ pages
BN='£bn'
MN='£m'
CMP="Fact Outturn.Comparison Amount"

# report_filters: one report-level filter that every page obeys. The plan measure is resource DEL excluding depreciation or
# capital DEL, the voted limits. Departmental AME is a forecast (PESA), and the in-year outturn of AME is a first look that
# lacks the year-end provisions, impairments and pension entries, so an AME variance is not an underspend and is
# reconciled on the Variance page instead of being added to the headline (docs/reconciliation.md).
report_filters() {
  pbir -q rm "$R/Fact Plan.Plan Measure.Filter" -f >/dev/null 2>&1
  q add filter "Fact Plan" "Plan Measure" -r "$R" --values RDEL_EX_DEPN
  q filters set "$R/Fact Plan.Plan Measure.Filter" --values RDEL_EX_DEPN --values CDEL
}

exec_page() {
  # the first page is the page the project started with ("Home"); it keeps its folder and takes the new name
  P="$R/Executive summary.Page"
  pbir ls "$R" 2>/dev/null | grep -q "Home.Page" && q set "$R/Home.Page.displayName" --value "Executive summary"
  q rm "$P/*.Visual" -f
  q rm "$P/*.Filter" -f
  header "UK Group Finance: executive summary" \
    "GBP billions, nominal unless marked 2025-26 prices; departments on the current structure; plan is DEL"
  pf "Display Unit" Unit "$BN"

  text note_a 24 130 1232 38 "Latest full year, 2025-26. Plan and variance are DEL only; AME is reconciled on the Variance page"
  card a_outturn "Outturn, all budgets" 24 168 192 92 "Fact Outturn.Outturn" "Outturn of 2025-26 for all budgets, in billions of pounds"
  card a_basis "DEL on the plan's basis" 232 168 192 92 "$CMP" "Outturn of 2025-26 on the basis the plan is published on, in billions of pounds"
  card a_plan "Plan (DEL)" 440 168 192 92 "Fact Plan.Plan" "Published plan for 2025-26, in billions of pounds"
  card a_variance "Variance (DEL)" 648 168 192 92 "$CMP" "Outturn on the plan's basis less the plan for 2025-26, in billions of pounds; below zero is favourable"
  card a_variance_pct "Variance % (DEL)" 856 168 192 92 "$CMP" "Variance as a percentage of the plan for 2025-26"
  card a_real "In 2025-26 prices" 1064 168 192 92 "Fact Outturn.Outturn (real terms)" "Outturn of 2025-26 in 2025-26 prices, in billions of pounds"
  for v in a_outturn a_basis a_plan a_variance a_variance_pct a_real; do vf "$v" "Fiscal Year" "Financial Year" 2025-26; done
  vf a_basis "Scenario Comparison" Comparison Actual
  vf a_variance "Scenario Comparison" Comparison Variance
  vf a_variance_pct "Scenario Comparison" Comparison "Variance %"
  badge a_badge 24 264 1232 60 "The plan source and the grain it is published at for 2025-26" 2025-26

  text note_b 24 326 800 38 "Year to date, 2026-27 to June 2026 (period 3), against the derived phased plan"
  card b_basis "On the plan's basis" 24 364 192 92 "Fact Outturn.Outturn (plan basis)" "Outturn on the plan's basis for 2026-27 to period 3, in billions of pounds"
  card b_phased "Phased plan (derived)" 232 364 192 92 "Fact Plan Phased (derived).Plan (phased)" "Derived phased plan for 2026-27 to period 3, in billions of pounds"
  card b_variance "Variance to phased" 440 364 192 92 "Fact Plan Phased (derived).Variance to Phased Plan" "Outturn less the derived phased plan for 2026-27 to period 3, in billions of pounds"
  card b_variance_pct "Variance %" 648 364 192 92 "Fact Plan Phased (derived).Variance to Phased Plan %" "Variance to the derived phased plan as a percentage"
  card b_real "In 2025-26 prices" 856 364 192 92 "Fact Outturn.Outturn (real terms)" "Outturn for 2026-27 to period 3 in 2025-26 prices, in billions of pounds"
  for v in b_basis b_phased b_variance b_variance_pct b_real; do
    vf "$v" "Fiscal Year" "Financial Year" 2026-27
    vf "$v" "Fiscal Period" "Period Number" 3
    vf "$v" "Time Intelligence" "Time Calculation" YTD
  done
  badge b_badge 1064 364 192 92 "The plan source and the grain it is published at for 2026-27" 2026-27 8

  visual lineChart chart_year "Outturn by year, nominal and 2025-26 prices" 24 468 440 228     "Line chart of outturn by financial year from 2018-19 to 2025-26, nominal and in 2025-26 prices, in billions of pounds"     "Category:Fiscal Year.Financial Year" "Y:Fact Outturn.Outturn" "Y:Fact Outturn.Outturn (real terms)"
  vf chart_year "Fiscal Year" "Financial Year" 2018-19 2019-20 2020-21 2021-22 2022-23 2023-24 2024-25 2025-26
  q visuals sort "$P/chart_year.Visual" -f "Fiscal Year.Financial Year" -d Ascending
  q set "$P/chart_year.Visual.valueAxis.labelDisplayUnits" --value 1
  visual clusteredBarChart chart_dept "Ten largest departments, 2025-26 (current structure)" 480 468 504 228     "Bar chart of the ten departments of the current structure with the largest outturn in 2025-26, in billions of pounds"     "Category:Department (current structure).Department" "Y:Fact Outturn.Outturn (current structure)"
  vf chart_dept "Fiscal Year" "Financial Year" 2025-26
  q add filter "Department (current structure)" Department -v "$P/chart_dept.Visual" --type TopN --n 10 --by-table "Fact Outturn" --by-field "Outturn (current structure)"
  q set "$P/chart_dept.Visual.valueAxis.labelDisplayUnits" --value 1
  visual clusteredBarChart chart_budget "DEL, AME and non-budget, 2025-26" 1000 468 256 228     "Bar chart of 2025-26 outturn split into departmental expenditure limits, annually managed expenditure and non-budget, in billions of pounds"     "Category:Control Budget.Control Budget" "Y:Fact Outturn.Outturn"
  vf chart_budget "Fiscal Year" "Financial Year" 2025-26
  vf chart_budget "Control Budget" "Control Budget" DEL AME Non-budget
  q set "$P/chart_budget.Visual.valueAxis.labelDisplayUnits" --value 1
}

pnl_page() {
  page_new "P&L statement"
  header "UK Group Finance: P&L statement" \
    "GBP millions, nominal; 2025-26 against 2024-25; the plan comparison is on the Variance page"
  pf "Fiscal Year" "Financial Year" 2025-26
  pf "Display Unit" Unit "$MN"
  # the 39 lines do not fit one matrix at a readable size, so the statement is two matrices that split at line 200
  # (net resource expenditure). Both show the amount and the prior year. The plan columns were dropped: the plan is
  # published for the net lines and the total only, and the total adds DEL limits to an AME forecast, so a variance on
  # it is a mismatch of bases, not an underspend. The comparison by group, reconciled, is on the Variance page.
  local m x w title op
  for m in pnl_left pnl_right; do
    if [ "$m" = "pnl_left" ]; then
      visual pivotTable "$m" "Income and resource expenditure" 24 136 480 444 \
        "Matrix of the income and resource expenditure lines of the group statement for 2025-26, with the amount and the amount a year earlier" \
        "Rows:Statement Line.Line" "Values:Fact Outturn.Statement Amount" "Values:Fact Outturn.Statement Amount PY (OFFSET)"
      op=LessThanOrEqual
    else
      visual pivotTable "$m" "Capital, other items and net expenditure" 520 136 736 444 \
        "Matrix of the capital, other and total lines of the group statement for 2025-26, with the amount and the amount a year earlier" \
        "Rows:Statement Line.Line" "Values:Fact Outturn.Statement Amount" "Values:Fact Outturn.Statement Amount PY (OFFSET)"
      op=GreaterThan
    fi
    q add filter "Statement Line" "Sort Order" -v "$P/$m.Visual" --type Advanced --operator "$op" --values 200
    q visuals sort "$P/$m.Visual" -f "Statement Line.Line" -d Ascending
    q visuals show-all "$P/$m.Visual" --role Rows
    q set "$P/$m.Visual.subTotals.rowSubtotals" --value false
    for o in values rowHeaders columnHeaders; do q set "$P/$m.Visual.$o.fontSize" --value 9; done
    q set "$P/$m.Visual.values.fontSize" --value 8
    q set "$P/$m.Visual.rowHeaders.wordWrap" --value true
  done
  # short column headings (the measures keep their model names; only this report's headings change)
  q fields rename "$R" "Fact Outturn.Statement Amount" "Outturn"
  q fields rename "$R" "Fact Outturn.Statement Amount PY (OFFSET)" "Prior year"
  text pnl_note 24 588 1232 108 "No plan columns here. The plan is published for the net lines and the total only, and the total adds DEL limits to an AME forecast, so a variance on it is a mismatch of bases. The comparison by Spending Review group, with its reconciliation, is on the Variance page."
}

variance_page() {
  page_new "Variance"
  header "UK Group Finance: outturn against plan" \
    "GBP billions, 2024-25; DEL; variance is outturn on the plan basis less plan"
  pf "Fiscal Year" "Financial Year" 2024-25
  pf "Display Unit" Unit "$BN"
  visual waterfallChart wf_plan_outturn "From outturn to plan: the gap by Spending Review group (DEL)" 24 140 612 264 \
    "Waterfall chart with Plan and Outturn as the two categories and the Spending Review groups as the breakdown, in billions of pounds, for the DEL plan of 2024-25" \
    "Category:Scenario.Scenario" "Breakdown:Spending Review Group.Spending Review Group" "Y:Fact Plan.Plan and Outturn by Scenario"
  vf wf_plan_outturn "Scenario" Scenario Plan Outturn
  q set "$P/wf_plan_outturn.Visual.valueAxis.labelDisplayUnits" --value 1
  q visuals sort "$P/wf_plan_outturn.Visual" -f "Scenario.Scenario" -d Ascending
  visual clusteredBarChart bar_variance_pct "DEL variance % by Spending Review group (blue favourable, orange adverse)" 652 140 604 264 \
    "Bar chart of the DEL variance as a percentage of plan for each Spending Review group in 2024-25, blue where below plan and orange where above" \
    "Category:Spending Review Group.Spending Review Group" "Y:Fact Outturn.Comparison Amount"
  vf bar_variance_pct "Scenario Comparison" Comparison "Variance %"
  q visuals sort "$P/bar_variance_pct.Visual" -f "Fact Outturn.Comparison Amount" -d Ascending
  q visuals cf "$P/bar_variance_pct.Visual" --rules --field "Fact Outturn.Comparison Amount" --rule "gt 0 bad" --rule "lte 0 good" --on dataPoint.fill
  # the reconciliation: every variance of 2024-25 that is not simply ok, with the cause the audit names (GBP thousands)
  visual tableEx plan_check "Plan variances of 2024-25 that need a reason, and the reason (GBP thousands; DEL and AME)" 24 412 832 284 \
    "Table of the 2024-25 plan variances that are explained, fixed or unexplained, by Spending Review group and plan measure, with the variance, its percentage and the verdict with its reason" \
    "Values:Plan Variance Check.Spending Review Group" "Values:Plan Variance Check.Plan Measure" "Values:Plan Variance Check.Variance Amount" \
    "Values:Plan Variance Check.Variance Share" "Values:Plan Variance Check.Verdict"
  vf plan_check "Plan Variance Check" "Financial Year" 2024-25
  vf plan_check "Plan Variance Check" "Verdict Class" explained fixed unexplained
  q set "$P/plan_check.Visual.total.totals" --value false
  q set "$P/plan_check.Visual.values.fontSize" --value 8
  q set "$P/plan_check.Visual.values.wordWrap" --value true
  q set "$P/plan_check.Visual.columnHeaders.fontSize" --value 8
  q visuals sort "$P/plan_check.Visual" -f "Plan Variance Check.Variance Amount" -d Ascending
  badge var_badge 872 412 384 76 "The plan source and the grain it is published at for 2024-25, DEL" 2024-25
  text var_note 872 496 384 140 "DEL only. AME is a forecast, so it is reconciled in the table, not added to the headline. SIA: plan, no outturn. Home Office: fee income missing in-year."
  button btn_dept "Department detail" 872 648 184 40 Drillthrough "Department detail"
  button btn_group "Group detail" 1072 648 184 40 Drillthrough "Group detail"
}

dept_page() {
  page_new "Department detail"
  header "Department detail" "GBP millions, 2025-26; current structure; opens by drill-through (capture shows all)" no
  q pages drillthrough "$P" --table "Department (current structure)" --field Department
  q pages hide "$P"
  pf "Fiscal Year" "Financial Year" 2025-26
  pf "Display Unit" Unit "$MN"
  button btn_back "Back" 24 92 120 36 Back
  visual clusteredColumnChart dept_months "Outturn by month (period 0 is not allocated to a month)" 24 140 744 280 \
    "Column chart of outturn by month of 2025-26 on the current department structure, in millions of pounds" \
    "Category:Fiscal Period.Period" "Y:Fact Outturn.Outturn (current structure)"
  q visuals sort "$P/dept_months.Visual" -f "Fiscal Period.Period" -d Ascending
  q set "$P/dept_months.Visual.valueAxis.labelDisplayUnits" --value 1
  card dept_ytd "Year to date (period 12)" 784 140 232 84 "Fact Outturn.Outturn (current structure)" "Outturn of 2025-26 year to date at period 12 in millions of pounds"
  vf dept_ytd "Fiscal Period" "Period Number" 12
  vf dept_ytd "Time Intelligence" "Time Calculation" YTD
  card dept_first "As first reported" 1024 140 232 84 "Fact Outturn.Outturn as First Reported" "Outturn of 2025-26 as first reported in millions of pounds"
  card dept_revision "Revision since first reported" 784 232 232 84 "Fact Outturn.Revision since First Reported" "Change in 2025-26 outturn since it was first reported in millions of pounds"
  card dept_revision_pct "Revision %" 1024 232 232 84 "Fact Outturn.Revision %" "Revision since first reported as a percentage of the amount first reported"
  text dept_note 784 324 472 96 "No plan below Spending Review group. Group detail sets outturn beside the derived phased plan."
  visual tableEx dept_orgs "Ten largest organisations by outturn, 2025-26" 24 432 1232 264 \
    "Table of the ten organisations with the largest outturn in 2025-26, in millions of pounds" \
    "Values:Organisation (as reported).Organisation" "Values:Fact Outturn.Outturn"
  q set "$P/dept_orgs.Visual.total.totals" --value false
  q add filter "Organisation (as reported)" Organisation -v "$P/dept_orgs.Visual" --type TopN --n 10 --by-table "Fact Outturn" --by-field Outturn
}

group_page() {
  page_new "Group detail"
  header "Group detail: outturn and phased plan" "GBP millions, 2025-26; DEL; the monthly plan is derived, not published; opens by drill-through" no
  q pages drillthrough "$P" --table "Spending Review Group" --field "Spending Review Group"
  q pages hide "$P"
  pf "Fiscal Year" "Financial Year" 2025-26
  pf "Display Unit" Unit "$MN"
  button btn_back "Back" 24 92 120 36 Back
  visual lineChart group_months "Outturn on the plan's basis and phased plan (derived), by month" 24 140 744 300 \
    "Line chart of outturn on the plan's basis and the derived phased plan by month of 2025-26, in millions of pounds" \
    "Category:Fiscal Period.Period" "Y:Fact Outturn.Outturn (plan basis)" "Y:Fact Plan Phased (derived).Plan (phased)"
  q visuals sort "$P/group_months.Visual" -f "Fiscal Period.Period" -d Ascending
  q set "$P/group_months.Visual.valueAxis.labelDisplayUnits" --value 1
  q add filter "Fiscal Period" "Period Number" -v "$P/group_months.Visual" --type Advanced --operator GreaterThanOrEqual --values 1
  card grp_basis "Plan basis, to date" 784 140 232 84 "Fact Outturn.Outturn (plan basis)" "Outturn on the plan's basis for 2025-26 to period 12 in millions of pounds"
  card grp_phased "Phased plan (derived)" 1024 140 232 84 "Fact Plan Phased (derived).Plan (phased)" "Derived phased plan for 2025-26 to period 12 in millions of pounds"
  card grp_variance "Variance to phased plan" 784 232 232 84 "Fact Plan Phased (derived).Variance to Phased Plan" "Outturn less the derived phased plan for 2025-26 in millions of pounds"
  card grp_variance_pct "Variance %" 1024 232 232 84 "Fact Plan Phased (derived).Variance to Phased Plan %" "Variance to the derived phased plan as a percentage"
  for v in grp_basis grp_phased grp_variance grp_variance_pct; do
    vf "$v" "Fiscal Period" "Period Number" 12
    vf "$v" "Time Intelligence" "Time Calculation" YTD
  done
  badge grp_badge 784 324 472 116 "The plan source and the grain it is published at for 2025-26" 2025-26
  visual tableEx grp_table "Outturn on the plan's basis, phased plan (derived) and variance, by month" 24 452 1232 244 \
    "Table of outturn on the plan's basis, the derived phased plan and the variance to it for each month of 2025-26, in millions of pounds" \
    "Values:Fiscal Period.Period" "Values:Fact Outturn.Outturn (plan basis)" "Values:Fact Plan Phased (derived).Plan (phased)" "Values:Fact Plan Phased (derived).Variance to Phased Plan"
  q set "$P/grp_table.Visual.total.totals" --value false
  q visuals sort "$P/grp_table.Visual" -f "Fiscal Period.Period" -d Ascending
  q add filter "Fiscal Period" "Period Number" -v "$P/grp_table.Visual" --type Advanced --operator GreaterThanOrEqual --values 1
}

restate_page() {
  page_new "Restatements"
  header "UK Group Finance: restatements" \
    "GBP billions; what each release said the outturn was, and how later releases changed it"
  pf "Display Unit" Unit "$BN"
  visual clusteredColumnChart rs_net "Change each release made to the year-to-date outturn (net)" 24 140 612 224 \
    "Column chart of the net change each of the 31 releases made to the year-to-date outturn, in billions of pounds" \
    "Category:Release.Release" "Y:Fact Outturn.Revision in Release"
  q visuals sort "$P/rs_net.Visual" -f "Release.Release" -d Ascending
  visual clusteredColumnChart rs_restated "Part of it that restated earlier figures (net)" 644 140 612 224 \
    "Column chart of the net part of each release's change that restated amounts already reported, in billions of pounds" \
    "Category:Release.Release" "Y:Fact Outturn.Restatement in Release"
  q visuals sort "$P/rs_restated.Visual" -f "Release.Release" -d Ascending
  visual clusteredColumnChart rs_gross "Gross restatement, with and without flagged rows" 24 380 612 224 \
    "Column chart of the gross restatement of each release, with and without the rows flagged as a unit error, in billions of pounds" \
    "Category:Release.Release" "Y:Fact Outturn.Gross Restatement in Release" "Y:Fact Outturn.Gross Restatement in Release (excl. flagged)"
  q visuals sort "$P/rs_gross.Visual" -f "Release.Release" -d Ascending
  visual tableEx rs_dq "Data-quality findings" 644 380 612 224 \
    "Table of the data-quality findings: type, releases, line, amounts before and after, and rows affected" \
    "Values:Data Quality Issue.Issue Type" "Values:Data Quality Issue.Release From" "Values:Data Quality Issue.Release To" "Values:Data Quality Issue.Sub-Segment Code" "Values:Data Quality Issue.Amount Before" "Values:Data Quality Issue.Amount After"
  for v in rs_net rs_restated rs_gross; do q set "$P/$v.Visual.valueAxis.labelDisplayUnits" --value 1; done
  vf rs_dq "Data Quality Issue" "Issue Rule" a b c d
  card rs_as_at "As at March 2026 release" 24 620 240 76 "Fact Outturn.Outturn as at Release" "Outturn of 2025-26 as the March 2026 release stated it, in billions of pounds"
  card rs_first "As first reported" 280 620 240 76 "Fact Outturn.Outturn as First Reported" "Outturn of 2025-26 as first reported up to the March 2026 release, in billions of pounds"
  card rs_revision "Revision since first reported" 536 620 240 76 "Fact Outturn.Revision since First Reported" "Change in 2025-26 outturn between first report and the March 2026 release, in billions of pounds"
  for v in rs_as_at rs_first rs_revision; do
    vf "$v" "Release" "Release Label" 2026-03
    vf "$v" "Fiscal Year" "Financial Year" 2025-26
  done
  text rs_note 792 620 464 76 "Gross figures add up every change. Flagged rows (two NHS Pension Scheme lines, 1,000 times too large) are left out of the excl. variant."
}

controls_page() {
  page_new "Data controls"
  header "UK Group Finance: data controls" \
    "GBP thousands; file totals, annual and PSS controls, plan coverage and quarantined rows"
  visual tableEx ctl_files "File controls: each release file against the model (GBP thousands)" 24 136 1232 252 \
    "Table with one row for each of the 31 release files: rows read, loaded and quarantined, the exact file sum, the four-decimal file total, the model's as-at outturn and their difference" \
    "Values:File Control.Release Label" "Values:File Control.Rows Read" "Values:File Control.Rows Loaded" "Values:File Control.Rows Quarantined" "Values:File Control.File Sum (exact)" "Values:File Control.File Total (4 decimals)" "Values:File Control.Outturn as at Release (own year)" "Values:File Control.Difference to File Total" "Values:File Control.Status"
  q visuals sort "$P/ctl_files.Visual" -f "File Control.Release Label" -d Ascending
  visual tableEx ctl_annual "In-year outturn against the restated annual files, DEL (GBP thousands)" 24 400 604 150 \
    "Table of the in-year outturn against the restated annual file for DEL by financial year and vintage, with the gap, its share and the status" \
    "Values:Annual Control.Financial Year" "Values:Annual Control.Vintage" "Values:Annual Control.In-Year Amount" "Values:Annual Control.Annual Amount" "Values:Annual Control.Gap" "Values:Annual Control.Gap Share" "Values:Annual Control.Status"
  vf ctl_annual "Annual Control" Level DEL
  visual tableEx ctl_pss "PSS against OSCAR, annual-file basis, total excl. Scotland (GBP thousands)" 644 400 612 150 \
    "Table of the Public Spending Statistics against OSCAR for the total excluding Scotland by year and measure, with the gap, its share, the tolerance and the status; the capital DEL gaps of 2023-24 and 2024-25 are shown" \
    "Values:PSS Control.Comparison" "Values:PSS Control.Financial Year" "Values:PSS Control.Measure" "Values:PSS Control.Gap" "Values:PSS Control.Gap Share" "Values:PSS Control.Tolerance" "Values:PSS Control.Status"
  vf ctl_pss "PSS Control" Level "TOTAL EXCL SCOTLAND"
  vf ctl_pss "PSS Control" Comparison BUD
  q visuals sort "$P/ctl_pss.Visual" -f "PSS Control.Status" -d Ascending
  visual tableEx ctl_plan "Plan coverage: what the plan fact holds (GBP thousands)" 24 562 560 134 \
    "Table of plan coverage by plan source, financial year, measure and grain, with the fact rows, source lines and total" \
    "Values:Plan Coverage.Plan Source Code" "Values:Plan Coverage.Financial Year" "Values:Plan Coverage.Plan Measure" "Values:Plan Coverage.Grain Code" "Values:Plan Coverage.Fact Rows" "Values:Plan Coverage.Source Lines" "Values:Plan Coverage.Plan Coverage Total"
  visual pivotTable ctl_load "" 600 562 656 70 \
    "Table of rows read, loaded and quarantined for the in-year release files and the annual restated files" \
    "Rows:Load Control.Source Family" "Values:Load Control.Rows Read" "Values:Load Control.Rows Loaded" "Values:Load Control.Rows Quarantined"
  card ctl_web "Web rows quarantined (deflators and CPI)" 600 640 656 56 "Load Control.Web Rows Quarantined" "Rows of the deflator workbooks and the CPI series that did not parse" 9
  q visuals title "$P/ctl_load.Visual" --no-show
  local v
  for v in ctl_files ctl_annual ctl_pss ctl_plan; do
    q set "$P/$v.Visual.total.totals" --value false
  done
  for v in ctl_files ctl_annual ctl_pss ctl_plan ctl_load; do
    q visuals table-density "$P/$v.Visual" --preset dense
    q set "$P/$v.Visual.values.fontSize" --value 8
    q set "$P/$v.Visual.columnHeaders.fontSize" --value 8
  done
}

# ------------------------------------------------------------------------------------------ NHS trust accounts pages
tac_balance_page() {
  page_new "NHS balance sheet"
  header "NHS providers: balance sheet" \
    "GBP millions, TAC sign; the sum of the provider accounts, not the consolidated accounts; 2024-25 unless marked"
  pf "Display Unit" Unit "$MN"
  local y=2024-25 v
  card bs_nca "Non-current assets" 24 136 192 84 "Fact TAC.TAC Closing Balance" "Closing balance of non-current assets of the NHS providers at the end of 2024-25, in millions of pounds" 17
  card bs_ca "Current assets" 232 136 192 84 "Fact TAC.TAC Closing Balance" "Closing balance of current assets of the NHS providers at the end of 2024-25, in millions of pounds" 17
  card bs_cl "Current liabilities" 440 136 192 84 "Fact TAC.TAC Closing Balance" "Closing balance of current liabilities of the NHS providers at the end of 2024-25, in millions of pounds, negative" 17
  card bs_ncl "Non-current liabilities" 648 136 192 84 "Fact TAC.TAC Closing Balance" "Closing balance of non-current liabilities of the NHS providers at the end of 2024-25, in millions of pounds, negative" 17
  card bs_net "Total assets employed" 856 136 192 84 "Fact TAC.TAC Closing Balance" "Total assets employed of the NHS providers at the end of 2024-25 as published, in millions of pounds" 17
  card bs_providers "Providers reporting" 1064 136 192 84 "Fact TAC.TAC Providers Reporting" "Number of NHS providers with statements for 2024-25"
  vf bs_nca "TAC Statement Line" Section "Non-current assets"
  vf bs_ca "TAC Statement Line" Section "Current assets"
  vf bs_cl "TAC Statement Line" Section "Current liabilities"
  vf bs_ncl "TAC Statement Line" Section "Non-current liabilities"
  vf bs_net "TAC Statement Line" Section "Net assets"
  for v in bs_nca bs_ca bs_cl bs_ncl bs_net bs_providers; do vf "$v" "Fiscal Year" "Financial Year" "$y"; done

  visual pivotTable bs_blocks "Balance sheet by block, 2024-25: closing, opening, last year's closing and the restatement (GBP millions)" 24 232 744 232 \
    "Matrix of the balance sheet blocks of the NHS providers for 2024-25 with the closing balance, the opening balance as restated, the closing balance of the year before, their difference and the restatement of values both files hold, in millions of pounds" \
    "Rows:TAC Statement Line.Section" "Values:Fact TAC.TAC Closing Balance" "Values:Fact TAC.TAC Opening Balance" "Values:Fact TAC.TAC Prior Year Closing Balance" \
    "Values:Fact TAC.TAC Opening less Prior Year Closing" "Values:Fact TAC.TAC Restatement"
  vf bs_blocks "TAC Statement Line" "Statement Code" SoFP
  vf bs_blocks "Fiscal Year" "Financial Year" "$y"
  q visuals sort "$P/bs_blocks.Visual" -f "TAC Statement Line.Section" -d Ascending
  q set "$P/bs_blocks.Visual.subTotals.rowSubtotals" --value false
  q set "$P/bs_blocks.Visual.values.fontSize" --value 8
  q set "$P/bs_blocks.Visual.columnHeaders.fontSize" --value 8
  q set "$P/bs_blocks.Visual.rowHeaders.fontSize" --value 9
  q fields rename "$R" "Fact TAC.TAC Closing Balance" "Closing"
  q fields rename "$R" "Fact TAC.TAC Opening Balance" "Opening"
  q fields rename "$R" "Fact TAC.TAC Prior Year Closing Balance" "Last year's closing"
  q fields rename "$R" "Fact TAC.TAC Opening less Prior Year Closing" "Opening less last year's closing"
  q fields rename "$R" "Fact TAC.TAC Restatement" "Restatement (both files)"

  visual clusteredColumnChart bs_restatement "Restatement of the opening net assets, by year (GBP millions)" 784 232 472 232 \
    "Column chart of the net restatement of the opening total assets employed of the NHS providers by financial year, for the values that the file of the year and the file of the year before both hold, in millions of pounds" \
    "Category:Fiscal Year.Financial Year" "Y:Fact TAC.TAC Restatement"
  vf bs_restatement "TAC Statement Line" "Sub Code" BAL1400
  vf bs_restatement "Fiscal Year" "Financial Year" 2020-21 2021-22 2022-23 2023-24 2024-25
  q visuals sort "$P/bs_restatement.Visual" -f "Fiscal Year.Financial Year" -d Ascending
  q set "$P/bs_restatement.Visual.valueAxis.labelDisplayUnits" --value 1

  visual clusteredColumnChart bs_assets "Total assets at the end of the year (GBP millions)" 24 476 372 220 \
    "Column chart of the total assets of the NHS providers at the end of each financial year from 2019-20 to 2024-25, in millions of pounds" \
    "Category:Fiscal Year.Financial Year" "Y:Fact TAC.TAC Closing Balance"
  vf bs_assets "TAC Statement Line" Section "Non-current assets" "Current assets"
  vf bs_assets "Fiscal Year" "Financial Year" 2019-20 2020-21 2021-22 2022-23 2023-24 2024-25
  q visuals sort "$P/bs_assets.Visual" -f "Fiscal Year.Financial Year" -d Ascending
  q set "$P/bs_assets.Visual.valueAxis.labelDisplayUnits" --value 1

  visual lineChart bs_providers_year "Providers with statements, by year" 412 476 356 220 \
    "Line chart of the number of NHS providers with statements in each financial year from 2019-20 to 2024-25; a provider acquired or merged stops being counted after its last year" \
    "Category:Fiscal Year.Financial Year" "Y:Fact TAC.TAC Providers Reporting"
  vf bs_providers_year "Fiscal Year" "Financial Year" 2019-20 2020-21 2021-22 2022-23 2023-24 2024-25
  q visuals sort "$P/bs_providers_year.Visual" -f "Fiscal Year.Financial Year" -d Ascending

  visual tableEx bs_gone "Providers that stop reporting: last year and successor" 784 476 472 220 \
    "Table of the NHS providers that were acquired, merged or dissolved, with the last year they have statements, the successor and the kind of change; they contribute nothing to a balance after their last year" \
    "Values:TAC Provider.Provider" "Values:TAC Provider.Last Year With Statements" "Values:TAC Provider.Successor" "Values:TAC Provider.Successor Kind"
  vf bs_gone "TAC Provider" "Successor Kind" acquired merged demised new_code
  q visuals sort "$P/bs_gone.Visual" -f "TAC Provider.Last Year With Statements" -d Ascending
  q set "$P/bs_gone.Visual.values.fontSize" --value 8
  q set "$P/bs_gone.Visual.columnHeaders.fontSize" --value 8
}

tac_cash_page() {
  page_new "NHS cash flow"
  header "NHS providers: cash flow" \
    "GBP millions, TAC sign; derived by the indirect method against the published cash flow; the residual is not forced to zero"
  pf "Display Unit" Unit "$MN"
  visual tableEx cf_lines "Derived against published cash flow by line, 2024-25 (GBP millions)" 24 136 744 560 \
    "Table of the 22 lines of the derived cash flow of the NHS providers for 2024-25 with the derived amount, the published lines they are compared with and the residual, in millions of pounds, and the total" \
    "Values:TAC Cash Flow Line.Cash Flow Section" "Values:TAC Cash Flow Line.Cash Flow Line" "Values:Fact TAC Cash Flow (derived).TAC Cash Flow (derived)" \
    "Values:Fact TAC.TAC Cash Flow (published)" "Values:Fact TAC Cash Flow (derived).TAC Cash Flow Residual"
  vf cf_lines "Fiscal Year" "Financial Year" 2024-25
  q visuals sort "$P/cf_lines.Visual" -f "TAC Cash Flow Line.Cash Flow Line" -d Ascending
  q set "$P/cf_lines.Visual.values.fontSize" --value 8
  q set "$P/cf_lines.Visual.columnHeaders.fontSize" --value 8
  q set "$P/cf_lines.Visual.values.wordWrap" --value true
  q fields rename "$R" "Fact TAC Cash Flow (derived).TAC Cash Flow (derived)" "Derived"
  q fields rename "$R" "Fact TAC.TAC Cash Flow (published)" "Published"
  q fields rename "$R" "Fact TAC Cash Flow (derived).TAC Cash Flow Residual" "Residual"

  visual clusteredColumnChart cf_residual "Residual by section and year: derived less published (GBP millions)" 784 136 472 270 \
    "Clustered column chart of the residual of the derived cash flow against the published cash flow for each financial year from 2019-20 to 2024-25, one series for each of operating, investing, financing and reserve movements, in millions of pounds" \
    "Category:Fiscal Year.Financial Year" "Series:TAC Cash Flow Line.Cash Flow Section" "Y:Fact TAC Cash Flow (derived).TAC Cash Flow Residual"
  vf cf_residual "Fiscal Year" "Financial Year" 2019-20 2020-21 2021-22 2022-23 2023-24 2024-25
  q visuals sort "$P/cf_residual.Visual" -f "Fiscal Year.Financial Year" -d Ascending
  q set "$P/cf_residual.Visual.valueAxis.labelDisplayUnits" --value 1

  visual tableEx cf_net "Net change in cash by year (GBP millions)" 784 418 472 190 \
    "Table of the net change in cash of the NHS providers for each financial year: the derived figure, the published figure, the balance sheet cash movement and the derived less published residual, in millions of pounds" \
    "Values:Fiscal Year.Financial Year" "Values:Fact TAC Cash Flow (derived).TAC Cash Flow (derived)" "Values:Fact TAC.TAC Net Change in Cash (published)" "Values:Fact TAC.TAC Cash Movement (balance sheet)" "Values:Fact TAC Cash Flow (derived).TAC Cash Flow Residual"
  vf cf_net "Fiscal Year" "Financial Year" 2019-20 2020-21 2021-22 2022-23 2023-24 2024-25
  q set "$P/cf_net.Visual.total.totals" --value false
  q visuals sort "$P/cf_net.Visual" -f "Fiscal Year.Financial Year" -d Ascending
  q set "$P/cf_net.Visual.values.fontSize" --value 8
  q set "$P/cf_net.Visual.columnHeaders.fontSize" --value 8
  q fields rename "$R" "Fact TAC.TAC Net Change in Cash (published)" "Published"
  q fields rename "$R" "Fact TAC.TAC Cash Movement (balance sheet)" "Balance sheet"
  q visuals table-density "$P/cf_lines.Visual" --preset dense
  text cf_note 784 616 472 80 "Non-cash items sit in published operating and in derived investing. Nothing is forced to tie."
}

tac_elimination_page() {
  page_new "NHS elimination control"
  header "NHS providers: elimination control" \
    "GBP millions, TAC sign; consolidated figures are hand-keyed (authored); gap = provider sum less consolidated"
  pf "Display Unit" Unit "$MN"
  local y=2024-25 v
  card el_income "Gap: operating income, 2024-25" 24 136 304 84 "TAC Consolidated Accounts.TAC Elimination Gap" "Sum of the provider operating income less the consolidated operating income for 2024-25, in millions of pounds"
  card el_expenses "Gap: operating expenses, 2024-25" 344 136 304 84 "TAC Consolidated Accounts.TAC Elimination Gap" "Sum of the provider operating expenses less the consolidated operating expenses for 2024-25, in millions of pounds, negative"
  card el_assets "Gap: total assets, 2024-25" 664 136 304 84 "TAC Consolidated Accounts.TAC Elimination Gap" "Sum of the provider total assets less the consolidated total assets for 2024-25, in millions of pounds"
  card el_cash "Gap: cash, 2024-25" 984 136 272 84 "TAC Consolidated Accounts.TAC Elimination Gap" "Sum of the provider cash less the consolidated cash for 2024-25, in millions of pounds, negative"
  vf el_income "TAC Control Line" "Control Code" OPERATING_INCOME
  vf el_expenses "TAC Control Line" "Control Code" OPERATING_EXPENSES
  vf el_assets "TAC Control Line" "Control Code" TOTAL_ASSETS
  vf el_cash "TAC Control Line" "Control Code" CASH
  for v in el_income el_expenses el_assets el_cash; do vf "$v" "Fiscal Year" "Financial Year" "$y"; done

  visual tableEx el_gap "The gap by year and line (GBP millions)" 24 232 744 464 \
    "Table of the six control lines for each financial year from 2019-20 to 2024-25: the sum of the provider accounts, the consolidated figure, the gap and the gap as a share of the consolidated figure, in millions of pounds" \
    "Values:Fiscal Year.Financial Year" "Values:TAC Control Line.Control Line" "Values:Fact TAC.TAC Provider Sum (control)" "Values:TAC Consolidated Accounts.TAC Consolidated Total" \
    "Values:TAC Consolidated Accounts.TAC Elimination Gap" "Values:TAC Consolidated Accounts.TAC Elimination Gap %"
  vf el_gap "Fiscal Year" "Financial Year" 2019-20 2020-21 2021-22 2022-23 2023-24 2024-25
  q set "$P/el_gap.Visual.total.totals" --value false
  q visuals sort "$P/el_gap.Visual" -f "Fiscal Year.Financial Year" -d Ascending
  q set "$P/el_gap.Visual.values.fontSize" --value 8
  q set "$P/el_gap.Visual.columnHeaders.fontSize" --value 8
  q fields rename "$R" "Fact TAC.TAC Provider Sum (control)" "Provider sum"
  q fields rename "$R" "TAC Consolidated Accounts.TAC Consolidated Total" "Consolidated"
  q fields rename "$R" "TAC Consolidated Accounts.TAC Elimination Gap" "Gap"
  q fields rename "$R" "TAC Consolidated Accounts.TAC Elimination Gap %" "Gap %"

  visual lineChart el_gap_pct "Gap as a share of the consolidated figure, by year" 784 232 472 224 \
    "Line chart of the elimination gap as a share of the consolidated figure for each financial year from 2019-20 to 2024-25, one line for each of operating income, operating expenses, total assets, total liabilities and cash" \
    "Category:Fiscal Year.Financial Year" "Series:TAC Control Line.Control Line" "Y:TAC Consolidated Accounts.TAC Elimination Gap %"
  vf el_gap_pct "Fiscal Year" "Financial Year" 2019-20 2020-21 2021-22 2022-23 2023-24 2024-25
  vf el_gap_pct "TAC Control Line" "Control Code" OPERATING_INCOME OPERATING_EXPENSES TOTAL_ASSETS TOTAL_LIABILITIES CASH
  q visuals sort "$P/el_gap_pct.Visual" -f "Fiscal Year.Financial Year" -d Ascending

  visual tableEx el_keyed "The hand-keyed values of 2024-25, with their pages (GBP millions)" 784 468 472 160 \
    "Table of the eight values keyed from the 2024-25 consolidated NHS provider accounts: the printed line, the value as printed, the printed page and the PDF page" \
    "Values:TAC Consolidated Accounts.Printed Line" "Values:TAC Consolidated Accounts.Printed Amount (GBP million)" "Values:TAC Consolidated Accounts.Printed Page" "Values:TAC Consolidated Accounts.PDF Page"
  vf el_keyed "Fiscal Year" "Financial Year" "$y"
  q set "$P/el_keyed.Visual.total.totals" --value false
  q set "$P/el_keyed.Visual.values.fontSize" --value 8
  q set "$P/el_keyed.Visual.columnHeaders.fontSize" --value 8
  q visuals table-density "$P/el_gap.Visual" --preset dense
  text el_note 784 636 472 60 "The TAC file leaves out 1, 5 and 3 providers in 2019-20, 2023-24 and 2024-25; the consolidated accounts include them."
}

pay_page() {
  page_new "Pay bridge"
  header "Pay bridge: paybill, volume, rate and mix" \
    "Pounds; 2025-26 against 2024-25, month by month; payroll of the organisations in the workforce files"
  local f="Fact Pay Bridge (derived)" y=2025-26 v
  card pay_prior "Prior paybill" 24 136 240 76 "$f.Pay Bridge Prior Paybill" "Payroll paybill of the organisations in the bridge in 2024-25, the same months a year before, in pounds, shown in billions"
  card pay_current "Current paybill" 272 136 240 76 "$f.Pay Bridge Current Paybill" "Payroll paybill of the organisations in the bridge in 2025-26, in pounds, shown in billions"
  card pay_change "Change in paybill" 520 136 240 76 "$f.Pay Bridge Change" "Change in payroll paybill between the two years, in pounds, shown in billions"
  card pay_tie "Tie difference" 768 136 240 76 "$f.Pay Bridge Tie Difference" "Change in paybill less volume, rate, mix and entry and exit, in pounds; it is zero"
  card pay_left_out "Rows left out of the bridge" 1016 136 240 76 "$f.Pay Bridge Rows Not Bridged" "Number of department, organisation and month rows left out of the bridge because the other month's cell is not valid or the department has no valid cell in one of the two months"
  for v in pay_prior pay_current pay_change pay_tie pay_left_out; do vf "$v" "Fiscal Year" "Financial Year" "$y"; done
  for v in pay_prior pay_current pay_change; do
    q set "$P/$v.Visual.value.labelDisplayUnits" --value 0
    q set "$P/$v.Visual.value.labelPrecision" --value 2
  done
  q set "$P/pay_tie.Visual.value.labelDisplayUnits" --value 1

  visual waterfallChart pay_waterfall "From last year's paybill to this year's (pounds, millions)" 24 220 340 228 \
    "Waterfall chart of the payroll paybill of the group in 2025-26 against 2024-25: the prior paybill, then the effect of volume, of rate, of organisation mix and of organisations that entered or left, and a total bar that is the current paybill, in millions of pounds" \
    "Category:Pay Bridge Step.Step" "Y:$f.Pay Bridge Step Amount"
  vf pay_waterfall "Fiscal Year" "Financial Year" "$y"
  q visuals sort "$P/pay_waterfall.Visual" -f "Pay Bridge Step.Step" -d Ascending
  q set "$P/pay_waterfall.Visual.valueAxis.labelDisplayUnits" --value 1000000
  q set "$P/pay_waterfall.Visual.labels.show" --value true
  q set "$P/pay_waterfall.Visual.labels.labelDisplayUnits" --value 1000000
  q set "$P/pay_waterfall.Visual.labels.fontSize" --value 9

  visual tableEx pay_dept "The bridge by department, 2025-26 (pounds)" 376 220 880 228 \
    "Table of the payroll paybill bridge of 2025-26 for each department of the current structure that has workforce data: prior paybill, volume, rate, mix, entry and exit, current paybill and the tie difference, in pounds, with the group total" \
    "Values:Department (current structure).Department" "Values:$f.Pay Bridge Prior Paybill" "Values:$f.Pay Bridge Volume" "Values:$f.Pay Bridge Rate" \
    "Values:$f.Pay Bridge Mix" "Values:$f.Pay Bridge Entry and Exit" "Values:$f.Pay Bridge Current Paybill" "Values:$f.Pay Bridge Tie Difference"
  vf pay_dept "Fiscal Year" "Financial Year" "$y"
  q set "$P/pay_dept.Visual.values.fontSize" --value 8
  q set "$P/pay_dept.Visual.columnHeaders.fontSize" --value 8
  q visuals table-density "$P/pay_dept.Visual" --preset dense
  q fields rename "$R" "$f.Pay Bridge Prior Paybill" "Prior"
  q fields rename "$R" "$f.Pay Bridge Volume" "Volume"
  q fields rename "$R" "$f.Pay Bridge Rate" "Rate"
  q fields rename "$R" "$f.Pay Bridge Mix" "Mix"
  q fields rename "$R" "$f.Pay Bridge Entry and Exit" "Entry, exit"
  q fields rename "$R" "$f.Pay Bridge Current Paybill" "Current"
  q fields rename "$R" "$f.Pay Bridge Tie Difference" "Tie"

  visual lineChart pay_fte "Payroll full-time equivalent, by month" 24 456 290 240 \
    "Line chart of the payroll full-time equivalent of the organisations the workforce files cover, for each month from April 2018" \
    "Category:Fiscal Period.Month Start Date" "Y:$f.Pay FTE"
  q visuals sort "$P/pay_fte.Visual" -f "Fiscal Period.Month Start Date" -d Ascending
  visual lineChart pay_cost "Average monthly paybill per full-time equivalent (pounds)" 322 456 290 240 \
    "Line chart of the average monthly payroll paybill per full-time equivalent, in pounds, for each month from April 2018" \
    "Category:Fiscal Period.Month Start Date" "Y:$f.Pay Average Cost"
  q visuals sort "$P/pay_cost.Visual" -f "Fiscal Period.Month Start Date" -d Ascending

  visual tableEx pay_cover "Coverage of the workforce files, all months" 624 456 632 168 \
    "Table of the share of published payroll full-time equivalent and paybill that the organisation map places on an organisation, for each department series, all months, with the total" \
    "Values:Pay Coverage.Series" "Values:Pay Coverage.Pay Coverage Months" "Values:Pay Coverage.Pay FTE Coverage" "Values:Pay Coverage.Pay Paybill Coverage"
  q set "$P/pay_cover.Visual.values.fontSize" --value 8
  q set "$P/pay_cover.Visual.columnHeaders.fontSize" --value 8
  q visuals table-density "$P/pay_cover.Visual" --preset dense
  q fields rename "$R" "Pay Coverage.Pay Coverage Months" "Months"
  q fields rename "$R" "Pay Coverage.Pay FTE Coverage" "FTE mapped"
  q fields rename "$R" "Pay Coverage.Pay Paybill Coverage" "Paybill mapped"
  text pay_note 624 628 632 68 "No Home Office, MoJ, Cabinet Office or ONS in the files; MHCLG core not mapped; MOD paybill 45.5% covered; no grade mix."
}

forecast_page() {
  page_new "Forecast accuracy"
  header "Forecast accuracy by method" \
    "Returns scored against the final outturn (R13); WAPE and bias are ratios of sums"
  local f="Fact Forecast Accuracy (derived)" line="Budget measure total" payl="Pay line (A101, resource DEL)" v
  card fc_wape "Dept WAPE, all returns" 24 136 240 76 "$f.Forecast WAPE" "Weighted absolute percentage error of the department's own full-year forecast on the budget measure totals, over every return and year, with the known bad returns kept in" 20
  card fc_wape_x "Dept WAPE, no bad returns" 272 136 240 76 "$f.Forecast WAPE (excl. bad returns)" "The same error without the known bad returns, the department group returns that are flagged for a units error, a scale outlier or a missing body" 20
  card fc_bad "Known bad return cells" 520 136 240 76 "$f.Known Bad Return Cells" "Number of scored department group, budget measure, year and return cells that belong to a known bad return" 20
  card fc_cov "FTE x cost cells covered" 768 136 240 76 "$f.FTE x Cost Cell Coverage" "Share of the pay line cells of returns R1 to R11 in FY2018-19 to FY2022-23 that have an FTE x cost forecast; the rest have no published workforce for the month" 20
  card fc_cover "FTE x cost pay seen" 1016 136 240 76 "$f.FTE x Cost Pay Cover" "Workforce paybill of the last actual month as a share of the pay line of the return for that month, over the cells that have the method" 20
  for v in fc_wape fc_wape_x fc_bad; do
    vf "$v" "$f" "Forecast Line" "$line"
    q add filter "Forecast Method" "Method" -v "$P/$v.Visual" --values Department
  done
  for v in fc_cov fc_cover; do
    vf "$v" "Fiscal Year" "Financial Year" 2018-19 2019-20 2020-21 2021-22 2022-23
  done

  visual clusteredColumnChart fc_chart_all "WAPE by year, all returns (budget measure totals, cells every method scored)" 24 220 410 228 \
    "Clustered column chart of the full-year weighted absolute percentage error for each financial year from 2017-18 to 2022-23, one column for each of the three methods: the department's own forecast, my run rate and my seasonal method, on the cells that all three scored, with the known bad returns kept in" \
    "Category:Fiscal Year.Financial Year" "Series:Forecast Method.Method" "Y:$f.Forecast WAPE"
  visual clusteredColumnChart fc_chart_excl "WAPE by year, without the known bad returns" 442 220 410 228 \
    "Clustered column chart of the same full-year weighted absolute percentage error for each financial year and method, on the same cells, with the known bad returns left out; the two known cases are in 2018-19 and 2020-21" \
    "Category:Fiscal Year.Financial Year" "Series:Forecast Method.Method" "Y:$f.Forecast WAPE (excl. bad returns)"
  visual clusteredColumnChart fc_chart_bias "Bias by year, without the known bad returns" 860 220 396 228 \
    "Clustered column chart of the signed full-year bias for each financial year and method, on the cells all three methods scored, without the known bad returns; above zero is a forecast that was too high" \
    "Category:Fiscal Year.Financial Year" "Series:Forecast Method.Method" "Y:$f.Forecast Bias (excl. bad returns)"
  for v in fc_chart_all fc_chart_excl fc_chart_bias; do
    vf "$v" "$f" "Forecast Line" "$line"
    q add filter "$f" "Scored By Every Method" -v "$P/$v.Visual" --values true
    q visuals sort "$P/$v.Visual" -f "Fiscal Year.Financial Year" -d Ascending
  done

  visual clusteredColumnChart fc_chart_pay "Pay line: WAPE by year without the known bad returns, four methods" 24 456 330 240 \
    "Clustered column chart of the full-year weighted absolute percentage error of the pay line for each financial year from 2018-19, one column for each of four methods: the department, run rate, seasonal and FTE x cost, on the cells that all four scored and without the known bad returns; FTE x cost is far higher because the workforce files cover part of each department group's pay" \
    "Category:Fiscal Year.Financial Year" "Series:Forecast Method.Method" "Y:$f.Forecast WAPE (excl. bad returns)"
  vf fc_chart_pay "$f" "Forecast Line" "$payl"
  q add filter "$f" "Scored By Every Method" -v "$P/fc_chart_pay.Visual" --values true
  q visuals sort "$P/fc_chart_pay.Visual" -f "Fiscal Year.Financial Year" -d Ascending

  visual tableEx fc_dept "The department's own forecast, by department" 362 456 520 240 \
    "Table with one row for each department of the current structure that has a department group in the returns: WAPE with and without the known bad returns, the share of pay-line cells with an FTE x cost forecast and the share of the pay line the workforce paybill is, with a total row" \
    "Values:Department (current structure).Department" "Values:$f.Forecast WAPE" "Values:$f.Forecast WAPE (excl. bad returns)" \
    "Values:$f.FTE x Cost Cell Coverage" "Values:$f.FTE x Cost Pay Cover"
  vf fc_dept "$f" "Forecast Line" "$line"
  q add filter "Forecast Method" "Method" -v "$P/fc_dept.Visual" --values Department
  q set "$P/fc_dept.Visual.values.fontSize" --value 8
  q set "$P/fc_dept.Visual.columnHeaders.fontSize" --value 8
  q visuals table-density "$P/fc_dept.Visual" --preset dense
  q fields rename "$R" "$f.Forecast WAPE" "WAPE"
  q fields rename "$R" "$f.Forecast WAPE (excl. bad returns)" "WAPE without bad"
  q fields rename "$R" "$f.FTE x Cost Cell Coverage" "FTE cells"
  q fields rename "$R" "$f.FTE x Cost Pay Cover" "Pay seen"

  text fc_note_bad 890 456 366 118 "Bad returns (FCDO R0 2020-21, Health R1 2018-19) are flagged, and left out of the middle and right charts."
  text fc_note_fte 890 580 366 116 "FTE x cost needs workforce files: none for Home Office, MoJ, Cabinet Office, ONS. Gaps are never filled."
}

# ----------------------------------------------------------------------------------------------------- driver
order() {
  q pages move "$R/Executive summary.Page" --to 1
  q pages move "$R/P&L statement.Page" --to 2
  q pages move "$R/Variance.Page" --to 3
  q pages move "$R/Restatements.Page" --to 4
  q pages move "$R/Data controls.Page" --to 5
  q pages move "$R/NHS balance sheet.Page" --to 6
  q pages move "$R/NHS cash flow.Page" --to 7
  q pages move "$R/NHS elimination control.Page" --to 8
  q pages move "$R/Pay bridge.Page" --to 9
  q pages move "$R/Forecast accuracy.Page" --to 10
}

case "${1:-}" in
  exec) exec_page ;;
  pnl) pnl_page ;;
  variance) variance_page ;;
  filters) report_filters ;;
  dept) dept_page ;;
  group) group_page ;;
  restate) restate_page ;;
  controls) controls_page ;;
  tac_balance) tac_balance_page ;;
  tac_cash) tac_cash_page ;;
  tac_elimination) tac_elimination_page ;;
  pay) pay_page ;;
  forecast) forecast_page ;;
  order) order ;;
  all) report_filters; exec_page; pnl_page; variance_page; restate_page; controls_page; dept_page; group_page; tac_balance_page; tac_cash_page; tac_elimination_page; pay_page; forecast_page; order ;;
  *) echo "usage: build_report.sh exec|pnl|variance|dept|group|restate|controls|tac_balance|tac_cash|tac_elimination|pay|forecast|filters|order|all" >&2; exit 2 ;;
esac
cat "$ERR" 2>/dev/null | head -20
