// display_folders.csx
//
// Applies the display-folder convention of the model: one folder per measure family, the folder
// "Derived" on every visible column of a table that is labelled derived, and the folder "Authored"
// on every visible column of the authored tables listed below (names and descriptions I wrote; no
// amount in them). The convention is in this file, nothing else decides a folder.
//
//   Base                          the plain outturn
//   Plan                          plan, outturn on the plan's basis, the comparison measure
//   Plan\Derived                  the phased plan (derived, never published)
//   Plan\Ranking                  ranks over the plan variance
//   Statement                     the group income and expenditure statement
//   Statement\Windows             window, offset and rank measures of the statement
//   Restatement                   how a figure changed from release to release
//   Restatement\Excluding flagged rows
//   Current Structure             department structure as reported and as it is now
//   Real Terms                    every measure whose name ends in " (real terms)"
//   Report Labels                 text for page headers (the latest release in view)
//   Audit and control             the data-controls tables (file, plan coverage, annual, PSS and load controls)
//
// A visible measure that is neither in the table nor a real-terms measure makes the script fail
// with the list of such measures, and so does a name in the table that is not a measure of the
// model. Hidden measures are left alone.
//
// Run (from the repository root):
//   powershell.exe -NoProfile -File tools\run_te_script.ps1 -Script te\scripts\display_folders.csx
// Running it twice gives no second change.

var folderOf = new Dictionary<string, string>
{
    { "Outturn", "Base" },
    { "Outturn (plan basis)", "Plan" },
    { "Comparison Amount", "Plan" },
    { "Plan", "Plan" },
    { "Plan Below Grain", "Plan" },
    { "Plan (phased)", @"Plan\Derived" },
    { "Department Group Rank (YTD Variance %)", @"Plan\Ranking" },
    { "Statement Amount", "Statement" },
    { "Statement Amount (plan basis)", "Statement" },
    { "Statement Variance", "Statement" },
    { "Statement Variance %", "Statement" },
    { "Statement Plan", "Statement" },
    { "Statement Amount PY (OFFSET)", @"Statement\Windows" },
    { "Statement Amount Running (WINDOW)", @"Statement\Windows" },
    { "Statement Amount Moving 3 Months (WINDOW)", @"Statement\Windows" },
    { "Department Rank (Statement Amount)", @"Statement\Windows" },
    { "Outturn as at Release", "Restatement" },
    { "Outturn as First Reported", "Restatement" },
    { "Revision since First Reported", "Restatement" },
    { "Revision %", "Restatement" },
    { "Revision in Release", "Restatement" },
    { "Restatement in Release", "Restatement" },
    { "Gross Revision in Release", "Restatement" },
    { "Gross Restatement in Release", "Restatement" },
    { "Gross Revision in Release (excl. flagged)", @"Restatement\Excluding flagged rows" },
    { "Gross Restatement in Release (excl. flagged)", @"Restatement\Excluding flagged rows" },
    { "Outturn (current structure)", "Current Structure" },
    { "Outturn (as reported structure)", "Current Structure" },
    { "Machinery of Government Transfer", "Current Structure" },
    { "Outturn (estimated mapping)", "Current Structure" },
    { "Estimated Mapping Share", "Current Structure" },
    { "Plan Source and Grain", "Plan" },
    { "Plan and Outturn by Scenario", "Plan" },
    { "Variance to Phased Plan", @"Plan\Derived" },
    { "Variance to Phased Plan %", @"Plan\Derived" },
    { "Latest Release in View", "Report Labels" },
    { "File Total (4 decimals)", "Audit and control" },
    { "Outturn as at Release (own year)", "Audit and control" },
    { "Difference to File Total", "Audit and control" },
    { "Plan Coverage Total", "Audit and control" },
    { "Rows Read", "Audit and control" },
    { "Rows Loaded", "Audit and control" },
    { "Rows Quarantined", "Audit and control" },
    { "Web Rows Quarantined", "Audit and control" }
};
const string RealTermsSuffix = " (real terms)";
const string RealTermsFolder = "Real Terms";
const string DerivedSuffix = "(derived)";
const string DerivedFolder = "Derived";
// Authored dimension tables (see the README register). Statement Measure, an authored field parameter, is
// labelled in its description only: its one visible column is what a slicer shows.
var authoredTables = new List<string> { "Scenario", "Spending Review Group", "Plan Source", "Plan Grain", "Statement Line" };
const string AuthoredFolder = "Authored";

var problems = new List<string>();
var seen = new HashSet<string>();

foreach (var m in Model.AllMeasures)
{
    if (m.IsHidden) continue;
    string folder;
    if (m.Name.EndsWith(RealTermsSuffix)) folder = RealTermsFolder;
    else if (!folderOf.TryGetValue(m.Name, out folder))
    {
        problems.Add("no folder for measure " + m.Table.Name + "[" + m.Name + "]");
        continue;
    }
    seen.Add(m.Name);
    if (m.DisplayFolder != folder) m.DisplayFolder = folder;
}
foreach (var name in folderOf.Keys)
    if (!seen.Contains(name)) problems.Add("the convention names a measure that does not exist or is hidden: " + name);

foreach (var t in Model.Tables)
{
    if (!t.Name.EndsWith(DerivedSuffix)) continue;
    foreach (var c in t.Columns)
        if (!c.IsHidden && c.DisplayFolder != DerivedFolder) c.DisplayFolder = DerivedFolder;
}

foreach (var name in authoredTables)
{
    var t = Model.Tables.FirstOrDefault(x => x.Name == name);
    if (t == null) { problems.Add("the convention names an authored table that does not exist: " + name); continue; }
    foreach (var c in t.Columns)
        if (!c.IsHidden && c.DisplayFolder != AuthoredFolder) c.DisplayFolder = AuthoredFolder;
}

if (problems.Count > 0)
    throw new Exception(problems.Count + " problem(s):\n  " + string.Join("\n  ", problems));
Info("Display folders applied to " + seen.Count + " measures.");
