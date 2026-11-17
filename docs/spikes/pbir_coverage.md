# pbir coverage spike

Before designing the report pages, I wanted to know which report features the `pbir` CLI can author on this machine
and how each one renders in Power BI Desktop. Report JSON is never edited by hand in this project, so anything `pbir`
cannot create either changes the design or becomes a recorded manual step. This note records what I ran and what I
saw. Every row is labelled **tested** (with its screenshot) or **not tested** (with the reason).

Setup: `pbir` 0.9.33, Power BI Desktop Store build 2.159.1231.0, nobody signed in, no Desktop options changed. I built a
throwaway project (`Cov`, not committed) with hand-written TMDL at compatibility level 1702 and no data source: M
`#table` partitions generate 36 fiscal months (April 2023 to March 2026), 12 departments in 4 groups, 15 accounts in 4
groups with an income/expenditure flag, 3 scenarios, 19,440 fact rows, and a 9-line statement-layout table with
subtotals and two spacer rows. Measures: Actual, Plan, Forecast, Variance, Variance %, Actual YTD, a dynamic-format
measure, a dynamic title measure and a colour measure. A calculation group (Current, YTD, PY), a measure field
parameter (Actual, Plan, Variance) and a dimension field parameter (Department, Account Group). After
`tools/run_dax.ps1 -Refresh`, a check query returned 6,480 rows and about £247.5m Actual per fiscal year before any page
was built.

The report was created with `pbir new report Cov.Report --thick --no-title` and
`pbir report rebind Cov.Report --local ../Cov.SemanticModel`. The loop for every item was: `pbir` command,
`pbir validate`, `pbir desktop refresh Cov.Report`, a 20 s wait, `pbir desktop screenshot <page> -o <file>`, then I
looked at the image. Screenshots are under [`evidence/pbir/`](evidence/pbir/), cropped to the canvas.

## Matrix

Result values: **works**, **works with caveat**, **not supported by pbir**, **authored but Desktop does not render it**.

| # | Feature | Result | Command(s) that worked, or the error | Screenshot | Consequence for the page designs |
|---|---|---|---|---|---|
| 1a | New card, three measures | works (tested) | `pbir add visual cardVisual <page> -n card_multi -d "Data:Fact.Actual" -d "Data:Fact.Plan" -d "Data:Fact.Variance"` | [01](evidence/pbir/01_core.png) | Use for headline numbers. |
| 1b | KPI | works (tested) | `pbir add visual kpi <page> -d "Indicator:Fact.Actual" -d "Goal:Fact.Plan" -d "TrendLine:Date.Month Year"` | 01 | Shows the last month's value against goal, not a year total. |
| 1c | Clustered bar | works (tested) | `pbir add visual clusteredBarChart <page> -d "Category:Department.Department" -d "Y:Fact.Variance"`; sorts by the measure, descending | 01 | |
| 1d | Line on a fiscal-month axis | works with caveat (tested) | `add visual` sorts by the first measure; the axis needs `pbir visuals sort <visual> -f "Date.Month Year" -d Ascending` (Month Year has a sort-by column) | 01 | Every time axis needs an explicit sort command. |
| 1e | Table | works (tested) | `pbir add visual tableEx <page> -d "Values:..."` | 01 | |
| 1f | Matrix with row hierarchy | works (tested) | `pbir add visual pivotTable <page> -d "Rows:Department.Department Group" -d "Rows:Department.Department" -d "Values:..."`; `pbir set <visual>.blankRows.showBlankRows --value true` adds a native blank row after each group | [02](evidence/pbir/02_matrix.png) | |
| 1g | Statement-layout matrix (subtotals, spacer rows) | works with caveat (tested) | rows on `Statement Line.Line`, then `pbir visuals sort <visual> -f "Statement Line.Line" -d Ascending`, `pbir visuals show-all <visual> --role Rows` (spacer rows have blank values) and `pbir set <visual>.subTotals.rowSubtotals --value false` | 02 | Spacer labels must differ: the engine treats `" "` and `"  "` as one value, and the sort-by refresh failed. Zero-width spaces (one, then two) work. |
| 1h | Matrix with the calculation group on columns | works (tested) | `-d "Columns:Time Calc.Time Calc"` | 02 | |
| 1i | `,,` scaled format on the canvas | **does not render** (tested) | static `£#,0,,"m"` prints `£247,524,226m` (unscaled, with "m"); `£#,0.0,,"m"`, `#,0.0,,` and `£#,0.0,,\m` print the commas literally; the dynamic version prints `£742.5,,Mm` on a card | [03](evidence/pbir/03_formats.png), 02 | Do not use `,,`. For £m use a measure divided by 1,000,000 with `£#,0.0"m"`, or card display units (`labels.labelDisplayUnits`). pbir has no display-units property for table or matrix values. |
| 2 | Waterfall, Plan to Actual with a breakdown | works (tested) | `pbir add visual waterfallChart <page> -d "Category:Scenario.Scenario" -d "Breakdown:Department.Department" -d "Y:Fact.Net Amount"`, `pbir add filter Scenario Scenario -v <visual> --values Plan --values Actual`, `pbir visuals sort <visual> -f "Scenario.Scenario"` (Plan first via a sort-by column), `pbir set <visual>.breakdown.maxBreakdowns --value 12` | [04](evidence/pbir/04_variance.png) | Native Plan-to-Actual bridge by department, no DAX needed. |
| 3 | Decomposition tree | works with caveat (tested) | `pbir add visual decompositionTreeVisual <page> -d "Analyze:Fact.Variance" -d "ExplainBy:Department.Department Group" -d "ExplainBy:Department.Department" -d "ExplainBy:Account.Account Group"` | 04 | Renders the root bar only. No pbir command writes `expansionStates`, so the levels cannot be pre-expanded. The reader clicks "+". |
| 4a | Dropdown slicer | works (tested) | `pbir add visual slicer ...` then `pbir set <visual>.data.mode --value Dropdown` | [05](evidence/pbir/05_slicers.png) | |
| 4b | Tile slicer | works (tested) | `pbir add visual advancedSlicerVisual <page> -d "Values:Account.Account Group"` | 05 | Needs 120 px height or the tiles clip. |
| 4c | Between-dates and fiscal-year slicers | works with caveat (tested) | `data.mode Between` on `Date.Date` works. `data.mode HorizontalList` on Fiscal Year was accepted but still draws a vertical list | 05 | Use a tile slicer for fiscal year. |
| 4d | Slicer on the measure field parameter that switches a chart's measure | **not supported by pbir** (tested) | `-d "Y:Measure Picker.Measure Picker"` and `visuals bind -a ... -t Column` both fail: `Field type 'Column' not allowed for role 'Y'`. In a table, pbir binds it as a plain column and Desktop shows "Can't determine relationships between the fields" | 05 | No measure switching through pbir. The single-select slicer itself renders (`selection.strictSingleSelect`). |
| 4e | Slicer on the dimension field parameter that switches an axis | **authored but Desktop does not render it** as a parameter (tested) | `-d "Category:Dimension Picker.Dimension Picker"` is accepted, but pbir writes no `queryState.<role>.fieldParameters`. The chart shows one bar labelled "Department". The model metadata is right: `INFO.EXTENDEDPROPERTIES()` returns `ParameterMetadata {"version": 3, "kind": 2}` for both parameters | 05 | Field parameters need a manual step in Desktop, or a different design. |
| 5 | Synced slicers (sync groups) | **not supported by pbir** (tested) | `pbir set <slicer>.syncGroup.groupName --value fy --dry-run` reports success; the real call fails: `Validation error: Unknown component: syncGroup` | none | Use report-level filters (`pbir add filter <T> <F> -r Cov.Report`), which apply to every page, or a manual sync step. |
| 6a | Drill-through page | works (tested) | `pbir pages drillthrough "Cov.Report/Detail.Page" --table Department --field Department`; `--show` reports `Drillthrough: Yes` with the field | [06](evidence/pbir/06_detail_drillthrough.png) | |
| 6b | Back button | works (tested) | `pbir add visual actionButton <page> -n btn_back`, `pbir visuals action <visual> --type Back`, `pbir set <visual>.text.show/text.text`, `pbir visuals title <visual> --no-show` | 06 | Hide the visual title on buttons, or it takes the space and hides the button text. |
| 6c | Drill-through button | works (tested in files, visible as disabled) | `pbir visuals action <btn> --type Drillthrough --target "Detail"` | 01 (greyed button, correct with no selection) | Right-click drill-through and the button click are **not tested**: I cannot click. The page metadata and the action are in the files. |
| 7 | Report-page tooltip | works with caveat (tested in files and as a page) | `pbir pages set-tooltip "Cov.Report/Tip.Page" --width 320 --height 240`; `pbir visuals tooltip <visual> --type Canvas` (`--type ReportPage`, as the help says, fails: `Value 'ReportPage' not in ['Default', 'Canvas']`); `pbir set <visual>.visualTooltip.section --value <page name id>` | [07](evidence/pbir/07_tooltip_page.png) | The hover itself is **not tested** (no mouse). The page captures. At 320x240 a line chart under a 100 px card was too small to draw. |
| 8a | Create bookmarks | **works with caveat**: the bookmarks are empty (tested) | `pbir add bookmark Cov.Report "Table hidden"`, `pbir bookmarks page Cov.Report "Table hidden" Core`. The file holds only `activeSection` and `"sections": {}`, with no visibility or filter state, even though the visual was hidden when it was created | [08](evidence/pbir/08_nav_bookmarks.png) | Bookmarks need "Update" in Desktop to capture anything. |
| 8b | Bookmark navigator and buttons | works (tested) | `pbir add visual bookmarkNavigator`, `pbir visuals action <btn> --type Bookmark --target "Table hidden"` | 08 | Clicks **not tested**. |
| 8c | Page-navigation button and page navigator | works with caveat (tested) | `pbir visuals action <btn> --type PageNavigation --target "Variance"`; `pbir add visual pageNavigator` (it rejects `title`: `Unknown component: title`, and needs about 80 px height) | 08 | |
| 9a | Background colour scale on a matrix | works (tested) | `pbir visuals cf <matrix> --gradient --field "Fact.Variance" --on values.backColor --min-color "#2166AC" --max-color "#B2182B"` | 02 | Use light end colours; dark ones hide the numbers. |
| 9b | Font colour by rule (favourable/adverse) | works (tested) | `pbir visuals cf <table> --rules --field "Fact.Variance" --rule "gt 0 #D55E00" --rule "lte 0 #0072B2" --on values.fontColor` | 01 | |
| 9c | Data bars | works (tested) | `pbir visuals cf <table> --data-bars --field "Fact.Actual"` | 01 | Set a lighter colour; the default bar hides the value. |
| 9d | Icon set | works (tested) | `pbir visuals cf <matrix> --icons --field "Fact.Statement Variance" --rule "gt 0 triangle_up" --rule "lte 0 triangle_down"` (`down` is refused with the list of valid names) | 02 | The icons are red/green: pair them with the direction of the shape, not the colour. |
| 9e | Colour driven by a measure | works (tested) | `pbir visuals cf <bar> --measure "dataPoint.fill Fact.Variance Colour"` (measure returns a hex code) | 01 | |
| 10a | Visual title and subtitle | works (tested) | `pbir visuals title`, `pbir visuals subtitle <v> --text "..." --show`; page subtitle textbox `pbir add subtitle <page> "..."` | [09](evidence/pbir/09_layout.png) | |
| 10b | Dynamic title bound to a measure | works (tested) | `pbir visuals cf <v> --measure "title.text Fact.Report Title"`, rendered "Actual vs plan: all departments, all years" | 09 | |
| 10c | Borders and shadows off | works (tested) | `pbir visuals border <v> --no-show`, `pbir visuals shadow <v> --no-show`; report-wide through the theme `visualStyles` | 09 | Set in the theme, not per visual. |
| 10d | Grid alignment | works (tested) | `pbir visuals snap "<page>/*.Visual" --grid 8`, `pbir visuals position`, `pbir validate --qa` (overlap check) | 09 | Moving several visuals can trip the overlap check part-way; `PBIR_ALLOW_OVERLAP=1` for the moves, then `validate --qa`. |
| 10e | Page size | works (tested) | `pbir add page <path> -n Layout --width 1280 --height 800` | 09 | |
| 10f | Canvas background | works with caveat (tested) | `pbir pages background <page> --color "#F3F6FA"`: invisible under the starting theme, visible after the custom theme | 09 | Set the page background in the theme. |
| 10g | Text box | works (tested) | every `pbir add page` adds a title textbox (480x120 at 20,20); `pbir add title` / `add subtitle` | 09 | Title textboxes need about 56 px height at the default size or the text clips. |
| 10h | Shape | works (tested) | `pbir add visual shape` | 09 | |
| 10i | Image | **authored but Desktop does not render it** (tested) | `pbir add image Cov.Report logo.png` then `pbir add visual image <page> --image logo.png`: Desktop shows "Select Image in the format pane under Style". pbir writes a legacy `image.image` object, registers the file a second time, and `pbir set <v>.image.sourceType --value image` did not help | 09 | No images on pages. A logo could go in a theme or be left out. |
| 10j | Visual-level and page-level filters | works (tested) | `pbir add filter Scenario Scenario -v <visual> --values Plan --values Actual`; `pbir add filter Account "Account Type" -p <page> --values Expenditure` (shown in the filter pane) | 04, 09 | `pbir bpa` warns on visual-level filters (PBIR_VISUAL_LEVEL_FILTERS). |
| 10k | Top N filter | works (tested) | `pbir add filter Department Department -v <visual> --type TopN --n 5 --by-table Fact --by-field Actual` | 09 | |
| 10l | Sort by a measure; sort by a sort-by column | works (tested) | `pbir visuals sort <v> -f "Fact.Actual" -d Descending`; axis on `Date.Month Year` / `Scenario.Scenario` uses the model's sort-by column | 01, 04, 09 | |
| 10m | Small multiples | works (tested) | `-d "Rows:Department.Department Group"` on a clustered column chart | 09 | |
| 11a | Custom theme through pbir | works (tested) | Theme JSON written as tool input, then `pbir theme create-template --new-template <file> --name ukfr-accessible` and `pbir theme apply-template Cov.Report ukfr-accessible`; Okabe-Ito palette, text classes, wildcard `dropShadow` off and border on | [10](evidence/pbir/10_theme_after_reload.png) | Theme-first formatting is possible. |
| 11b | Does a theme apply on reload? | works (tested): yes | Both `apply-template` and an in-place `pbir theme set-colors Cov.Report --data-colors '[...]'` showed after `pbir desktop refresh`, with no restart (the Actual line turned purple, then back) | 10, [10b](evidence/pbir/10b_theme_edit_after_reload.png) | The older note that themes need a restart did not hold with this build; reload is enough. |
| 11c | Does pbir validate theme files? | works with caveat (tested) | `pbir theme validate <file>` passed a copy with `"notacolour"` and `42` in `dataColors` and `"show": "nope"` | none | Structure only. Check theme values by eye on a screenshot. |
| 12a | Alt text on visuals | works (tested) | `pbir visuals general <v> --altText "Bar chart of variance against plan by department, largest overspend first"`, written as `visualContainerObjects.general.altText` | none (not visible on the canvas) | Alt text can be authored. `pbir bpa` flags every visual without it (PBIR_NO_ALT_TEXT). |
| 12b | Tab order | **not supported by pbir** (tested) | `pbir set <v>.tabOrder --value 1` fails: `Property path must be component.property format`; `<v>.position.tabOrder` fails: `Component 'position' has no property 'tabOrder'`. Only `pbir visuals mobile --tab-order` exists (mobile layout) | none | Tab order follows creation order; set it in Desktop (Selection pane, Tab order) as a manual step. |
| 12c | `pbir bpa` | works (tested) | `pbir bpa run Cov.Report`: passed, 12 warnings, 46 info. Rule list below | [bpa_run.txt](evidence/pbir/bpa_run.txt) | |
| 13 | Mobile (phone) layout | works with caveat; **not verified visually** | `pbir visuals mobile <v> --x 0 --y 0 --width 100 --height 20` (and two more) writes `mobile.json` next to each visual; `pbir validate` passes | none | The help says positions are 0-100 percentages and the file stores 0-100 as written, while Desktop's phone layout uses pixel positions. Neither the bridge nor the screenshot command has a mobile view. Treat it as designed, not run, until someone opens View > Mobile layout. |
| 14a | Visual calculation on a table (running total) | works with caveat (tested) | `pbir dax viscalcs add <table> -n "Running actual" -e "RUNNINGSUM([Actual])"` | [01](evidence/pbir/01_core.png) | Renders, but unformatted (`303,284,762.00`) and accumulated in alphabetical department order, not the visual's sort. |
| 14b | Visual calculation on a matrix (share of parent) | **authored but Desktop does not render it** (tested) | `pbir dax viscalcs add <matrix> -n "Share of parent" -e "DIVIDE([Actual], COLLAPSE([Actual], ROWS))"` validates; no column appears | 02 | Use model measures for percent of parent. |
| 15a | Edit interactions | works (tested in files) | `pbir pages interactions <page> --source bar_variance --target kpi_actual --type NoFilter` | none | Click behaviour **not tested**. |
| 15b | Drill-down hierarchy | works (tested) | `-d "Category:Department.Department Hierarchy"` binds both levels (the `.Hierarchy` suffix shown in the help fails: "not found in model") | 09 | |
| 15c | Expand to next level by default | **not supported by pbir** (tested) | no command writes `expansionStates` | none | Matrices open collapsed; the reader expands. |
| 15d | Visual header icons off | works (tested) | `pbir visuals header <v> --no-show` | none | |
| 15e | Hide a page | works (tested) | `pbir pages hide <page>` | none | Hide the drill-through and tooltip pages. |
| 15f | Page order | works (tested) | `pbir pages move <page> --to 1` | 08 (navigator order) | |
| 15g | Rename a page's display name | works (tested) | `pbir set "<page>.displayName" --value "Core"` (not `pages rename`, see the local notes) | 01 | |
| 15h | Duplicate a page | works with caveat (tested) | `pbir cp "<R>/Variance.Page" "<R>/Variance copy.Page"`: the copied visuals get hex names | none | Rename duplicates' visuals by recreating them if names matter. |
| 15i | Copy a visual between pages | works (tested) | `pbir cp <Core>/card_multi.Visual <Nav>/card_copy.Visual` (keeps its position) | 08 | |
| 15j | Group visuals | works with caveat (tested) | `pbir visuals group <page> --create "BookmarkButtons"` creates `bookmarkbuttons-shape-<hex>`; `--add` on that name worked and moved the members on the canvas | 08 | Group before final positioning, then re-check positions. |
| 15k | Layer order | works (tested) | `pbir visuals z-order <v> --front` | none | |
| 16a | Resolution | tested | `--scale 1` gives 1317x751 (30-92 KB per page); `--scale 2` gives 2634x1502 (86-252 KB). The size does not follow the page size: the capture is the canvas area plus the filter pane | evidence images | Crop to the canvas; 1016 px wide at scale 1. |
| 16b | Per-page and full-report capture | tested | `pbir desktop screenshot <page> -o <file>`; `pbir desktop screenshot Cov.Report --all --output-dir <dir> --settle 20000` captured 10 pages in 47 s (33 s with `--settle 5000` at scale 2) | | `--settle` is milliseconds and is ignored without `--all`: wait about 20 s yourself before a single-page capture after a refresh. |
| 16c | Tooltip and drill-through pages | tested: both capture, also when hidden | `--all` includes hidden pages | 06, 07 | A drill-through page captures unfiltered. |
| 16d | Set slicer state before a capture | **not supported by pbir** (tested) | `pbir set <slicer>.general.filter --value 2024-25` fails: `Component 'general' has no property 'filter'` | none | For README captures, set a page or report filter with `--values` (that does show, see 09), not a slicer selection. |
| 16e | Window chrome in captures | tested | captures contain the canvas and filter pane, never the title bar; `pbir filters pane-hide` does not remove the pane from the edit-mode capture | all | No account name or path is visible. Crop off the pane. |

## What the report can be designed around

Core visuals (new card, KPI, bar, column, line, table, matrix with hierarchy), the statement-layout matrix with
subtotals and spacer rows, the calculation group on matrix columns, the native waterfall for Plan to Actual by
department, the decomposition tree (collapsed), dropdown / tile / date-range slicers, drill-through pages with Back and
drill-through buttons, report-page tooltips, page-navigation buttons and the page navigator, all five conditional
formatting types, dynamic titles from a measure, Top N and visual / page / report filters, small multiples, drill-down
hierarchies, a custom accessible theme (applies on reload), alt text, hidden pages, page order, edit interactions,
header icons off, and `pbir bpa` as a gate.

## What needs one manual step in Desktop

Each step means pressing Save in Desktop, so the full diff must then be reviewed and the `$schema` lines restored (Desktop strips them on save).
Where a design alternative exists, I would use it instead.

1. **Field parameters.** For each visual: select it, remove the parameter field from its well, drag
   `Measure Picker` (or `Dimension Picker`) from the Data pane back into Y-axis (or X-axis), File > Save. The
   alternative with no manual step is fixed measure columns, or one page per view.
2. **Synced slicers.** View > Sync slicers, select the slicer, tick "Sync" on every page and "Visible" on the
   pages where it should show, File > Save. The alternative is a report-level filter in the filter pane.
3. **Bookmarks.** For each bookmark: set the page to the state it should hold, View > Bookmarks, "..." next to the
   bookmark > Update, File > Save. The alternative is page navigation buttons and separate pages.
4. **Tab order.** View > Selection > Tab order, drag the visuals into reading order, File > Save.
5. **Decomposition tree or matrix opened at a level.** Click "+" on the levels (or "Expand all down one level"),
   File > Save. Otherwise leave them collapsed and say so on the page.
6. **Mobile layout check.** View > Mobile layout, look at the visuals `pbir visuals mobile` placed, fix sizes,
   File > Save. Until then, mobile is "designed, not run".

## What to drop

- `,,` scaled number formats (they print wrong numbers); use divided measures with `"m"` / `"bn"` text instead.
- Image visuals.
- Matrix visual calculations (percent of parent): use model measures.
- Slicer selections set for screenshots: use filters with `--values`.
- `data.mode HorizontalList` on the classic slicer: use the tile slicer.

## pbir bpa rules

`pbir bpa rules list` (pbir 0.9.33) has 30 rules: PBIR_TOO_MANY_PAGES, PBIR_NO_THEME,
PBIR_UNUSED_EXTENSION_MEASURE, PBIR_TOO_MANY_VISUALS, PBIR_TOO_MANY_TOPN_FILTERS, PBIR_TOO_MANY_ADVANCED_FILTERS,
PBIR_VISUAL_OVERLAP, PBIR_INVALID_PAGE_FOLDER, PBIR_INVALID_PAGE_FOLDER_PERIODS, PBIR_DEFAULT_PAGE_NAME,
PBIR_HIDDEN_VISUAL, PBIR_VISUAL_LEVEL_FILTERS, PBIR_TOO_MANY_FIELDS, PBIR_HIDDEN_FIELDS, PBIR_MISSING_TITLE,
PBIR_OVERSIZED_CARD, PBIR_VISUAL_UNDERSIZED, PBIR_VISUAL_OFF_CANVAS, PBIR_NO_ALT_TEXT, PBIR_DROP_SHADOW,
PBIR_UNUSED_CUSTOM_VISUAL, PBIR_SHOW_ALL_ITEMS, PBIR_EXPOSED_UTILITY_PAGE, PBIR_HARDCODED_COLOR,
PBIR_PAGE_EXCEEDS_VIEWPORT, PBIR_BESPOKE_CONTAINER_FORMAT, PBIR_ACTIVE_PAGE_NOT_FIRST, PBIR_HIDDEN_FILTER,
PBIR_NONSTANDARD_FONT, PBIR_THEME_NONSTANDARD_FONT. Errors: off-canvas visuals and non-built-in fonts. None checks tab
order.

On the finished spike report it passed with 12 warnings and 46 info: PBIR_NO_ALT_TEXT 37, PBIR_OVERSIZED_CARD 5,
PBIR_VISUAL_UNDERSIZED 5, PBIR_TOO_MANY_FIELDS 3, PBIR_VISUAL_LEVEL_FILTERS 3, PBIR_HARDCODED_COLOR 2 (the
conditional-format hex colours), PBIR_ACTIVE_PAGE_NOT_FIRST, PBIR_PAGE_EXCEEDS_VIEWPORT (the 800 px page),
PBIR_SHOW_ALL_ITEMS (the statement spacer rows). To pass cleanly, the real report needs alt text on every data visual,
theme colour tokens instead of hex in conditional formatting, 16:9 pages, hidden drill-through and tooltip pages
(PBIR_EXPOSED_UTILITY_PAGE did not fire because I hid them), and either filter-pane filters or an explicit ignore
(`pbir bpa rules ignore <ID> <report>`) for intended visual-level filters and show-all. Full output:
[bpa_run.txt](evidence/pbir/bpa_run.txt); `pbir validate --all`: [validate_all.txt](evidence/pbir/validate_all.txt)
(valid, 50 visuals, 20 warnings).

## Screenshot settings that give a clean capture

1. `pbir desktop refresh <Report>.Report`, then wait 20 s (`Start-Sleep 20`); for a whole report use
   `--all --settle 20000` instead.
2. `pbir desktop screenshot "<Report>.Report/<Page>.Page" -o <file> --scale 1` (scale 2 for README images).
3. Crop to the canvas: at scale 1 keep x 0-1016 (the filter pane starts there). The capture never includes the title
   bar.
4. Give title textboxes 56 px or more, slicers 120 px or more, and hide visual titles on buttons and navigators.

## Other findings

- A model-side trap: with M partitions, `pbir desktop refresh --model` followed by a TOM data refresh hung twice, with
  Desktop showing "Something went wrong: Could not find a PackageSession for the given session". Closing Desktop with
  `Stop-Process`, reopening and refreshing worked every time. After a TMDL edit I restart Desktop rather than reload
  the model.
- `scope` is a reserved word as a DAX variable name.
- `pbir add page` has no `--no-title` option, although its help mentions it.
