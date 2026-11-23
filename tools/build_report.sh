#!/usr/bin/env bash
# Builds the pages of model/UKGroupFinance.Report with the pbir CLI, one function per page. It is the record of how the
# report was made: no report file is edited by hand. Run from Git Bash, from anywhere, with the theme already applied
# (pbir theme apply-template UKGroupFinance.Report ukfr-finance):
#
#   bash tools/build_report.sh exec          # build one page (the page must not exist yet)
#   bash tools/build_report.sh all           # every page, in order
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

exec_page() {
  # the first page is the page the project started with ("Home"); it keeps its folder and takes the new name
  P="$R/Executive summary.Page"
  pbir ls "$R" 2>/dev/null | grep -q "Home.Page" && q set "$R/Home.Page.displayName" --value "Executive summary"
  q rm "$P/*.Visual" -f
  q rm "$P/*.Filter" -f
  header "UK Group Finance: executive summary" \
    "GBP billions, nominal unless marked 2025-26 prices; departments on the current structure"
  pf "Display Unit" Unit "$BN"

  text note_a 24 130 900 38 "Latest full year, 2025-26, as the latest release states it"
  card a_outturn "Outturn, all budgets" 24 168 192 92 "Fact Outturn.Outturn" "Outturn of 2025-26 for all budgets, in billions of pounds"
  card a_basis "On the plan's basis" 232 168 192 92 "$CMP" "Outturn of 2025-26 on the basis the plan is published on, in billions of pounds"
  card a_plan "Plan" 440 168 192 92 "Fact Plan.Plan" "Published plan for 2025-26, in billions of pounds"
  card a_variance "Variance" 648 168 192 92 "$CMP" "Outturn on the plan's basis less the plan for 2025-26, in billions of pounds; below zero is favourable"
  card a_variance_pct "Variance %" 856 168 192 92 "$CMP" "Variance as a percentage of the plan for 2025-26"
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
    "GBP millions, nominal; 2025-26 against 2024-25; plan only where the source gives one"
  pf "Fiscal Year" "Financial Year" 2025-26
  pf "Display Unit" Unit "$MN"
  # the 39 lines do not fit one matrix at a readable size, so the statement is two matrices that split at line 200
  # (net resource expenditure). No line of the first has a plan in 2025-26 (the source publishes the plan for the net
  # lines and the total only, and at that level the Estimates give the total), so it shows the amount and the prior
  # year; the second carries the plan, the variance and the variance percentage as well.
  local m x w title op
  for m in pnl_left pnl_right; do
    if [ "$m" = "pnl_left" ]; then
      visual pivotTable "$m" "Income and resource expenditure" 24 136 480 444 \
        "Matrix of the income and resource expenditure lines of the group statement for 2025-26, with the amount and the amount a year earlier" \
        "Rows:Statement Line.Line" "Values:Fact Outturn.Statement Amount" "Values:Fact Outturn.Statement Amount PY (OFFSET)"
      op=LessThanOrEqual
    else
      visual pivotTable "$m" "Capital, other items and net expenditure" 520 136 736 444 \
        "Matrix of the capital, other and total lines of the group statement for 2025-26, with the amount, the plan, the variance, the variance percentage and the amount a year earlier" \
        "Rows:Statement Line.Line" "Values:Fact Outturn.Statement Amount" "Values:Fact Plan.Statement Plan" \
        "Values:Fact Outturn.Statement Variance" "Values:Fact Outturn.Statement Variance %" "Values:Fact Outturn.Statement Amount PY (OFFSET)"
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
  q fields rename "$R" "Fact Plan.Statement Plan" "Plan"
  q fields rename "$R" "Fact Outturn.Statement Variance" "Variance"
  q fields rename "$R" "Fact Outturn.Statement Variance %" "Var %"
  q fields rename "$R" "Fact Outturn.Statement Amount PY (OFFSET)" "Prior year"
  badge pnl_badge 24 588 760 108 "The plan source and the grain it is published at for 2025-26" 2025-26
  text pnl_note 800 588 456 108 "Plan is published on the net resource, net capital and total lines only, and only for a year at that level."
}

variance_page() {
  page_new "Variance"
  header "UK Group Finance: outturn against plan" \
    "GBP billions, 2024-25; variance is outturn on the plan basis less plan, below zero is favourable"
  pf "Fiscal Year" "Financial Year" 2024-25
  pf "Display Unit" Unit "$BN"
  visual waterfallChart wf_plan_outturn "From outturn to plan: the gap by Spending Review group" 24 140 612 296 \
    "Waterfall chart with Plan and Outturn as the two categories and the Spending Review groups as the breakdown, in billions of pounds, for 2024-25" \
    "Category:Scenario.Scenario" "Breakdown:Spending Review Group.Spending Review Group" "Y:Fact Plan.Plan and Outturn by Scenario"
  vf wf_plan_outturn "Scenario" Scenario Plan Outturn
  q set "$P/wf_plan_outturn.Visual.valueAxis.labelDisplayUnits" --value 1
  q visuals sort "$P/wf_plan_outturn.Visual" -f "Scenario.Scenario" -d Ascending
  visual clusteredBarChart bar_variance_pct "Variance % by Spending Review group (blue favourable, orange adverse)" 652 140 604 296 \
    "Bar chart of the variance as a percentage of plan for each Spending Review group in 2024-25, blue where below plan and orange where above" \
    "Category:Spending Review Group.Spending Review Group" "Y:Fact Outturn.Comparison Amount"
  vf bar_variance_pct "Scenario Comparison" Comparison "Variance %"
  q visuals sort "$P/bar_variance_pct.Visual" -f "Fact Outturn.Comparison Amount" -d Ascending
  q visuals cf "$P/bar_variance_pct.Visual" --rules --field "Fact Outturn.Comparison Amount" --rule "gt 0 bad" --rule "lte 0 good" --on dataPoint.fill
  visual decompositionTreeVisual tree_variance "Decomposition of the variance by group and plan measure (opens collapsed: click +)" 24 452 760 244 \
    "Decomposition tree of the 2024-25 variance to plan, explained by Spending Review group and then by plan measure; it opens collapsed" \
    "Analyze:Fact Outturn.Comparison Amount" "ExplainBy:Spending Review Group.Spending Review Group" "ExplainBy:Fact Plan.Plan Measure"
  vf tree_variance "Scenario Comparison" Comparison Variance
  badge var_badge 800 452 456 76 "The plan source and the grain it is published at for 2024-25" 2024-25
  text var_note 800 536 456 100 "No department breakdown: plan is published by Spending Review group. The tree opens collapsed; click +."
  button btn_dept "Department detail" 800 648 224 40 Drillthrough "Department detail"
  button btn_group "Group detail" 1032 648 224 40 Drillthrough "Group detail"
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
  header "Group detail: outturn and phased plan" "GBP millions, 2025-26; the monthly plan is derived, not published; opens by drill-through" no
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

# ----------------------------------------------------------------------------------------------------- driver
order() {
  q pages move "$R/Executive summary.Page" --to 1
  q pages move "$R/P&L statement.Page" --to 2
  q pages move "$R/Variance.Page" --to 3
  q pages move "$R/Restatements.Page" --to 4
  q pages move "$R/Data controls.Page" --to 5
}

case "${1:-}" in
  exec) exec_page ;;
  pnl) pnl_page ;;
  variance) variance_page ;;
  dept) dept_page ;;
  group) group_page ;;
  restate) restate_page ;;
  controls) controls_page ;;
  order) order ;;
  all) exec_page; pnl_page; variance_page; restate_page; controls_page; dept_page; group_page; order ;;
  *) echo "usage: build_report.sh exec|pnl|variance|dept|group|restate|controls|order|all" >&2; exit 2 ;;
esac
cat "$ERR" 2>/dev/null | head -20
