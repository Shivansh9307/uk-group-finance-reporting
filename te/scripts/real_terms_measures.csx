// real_terms_measures.csx
//
// Creates or updates "<name> (real terms)" for each amount measure in the list below. Each twin is
// one line, Real.Deflate ( [<name>] ), in the same table as its source, with the display folder
// "Real Terms", the format string of the source and a description. The deflation itself is written
// once, in the DAX function Real.Deflate (functions.tmdl), and the index lookup once in
// Real.IndexTable. To add a real-terms measure, add its name to the list and run the script.
//
// Real terms here means 2025-26 prices: for each financial year in context the amount is multiplied
// by (index of 2025-26) / (index of that year), from the chained index of the default vintage of the
// GDP deflators (October 2026 Budget); a month takes the index of its financial year; a year that
// has an amount but no index makes the result BLANK, never the nominal figure.
//
// Display Unit and the real-terms measures: the calculation group Display Unit scales the measures
// it lists by name (ISSELECTEDMEASURE). Tabular Editor cannot write that file back (see
// tools\run_te_script.ps1), so the names of the real-terms measures are added to the lists in
// Display Unit.tmdl by hand; pipeline/tests/test_model_measures.py fails when a real-terms measure
// is missing from them.
//
// Run (from the repository root):
//   powershell.exe -NoProfile -File tools\run_te_script.ps1 -Script te\scripts\real_terms_measures.csx
// Running it twice gives no second change.

// The amount measures that get a real-terms twin. Edit this list only.
var sources = new List<string>
{
    "Outturn",
    "Plan",
    "Plan (phased)",
    "Outturn (plan basis)",
    "Outturn (current structure)",
    "Statement Amount",
    "Statement Plan"
};
const string Suffix = " (real terms)";
const string Folder = "Real Terms";

var problems = new List<string>();
foreach (var name in sources)
{
    var src = Model.AllMeasures.FirstOrDefault(x => x.Name == name);
    if (src == null) { problems.Add("source measure not found: " + name); continue; }

    var twinName = name + Suffix;
    var twin = src.Table.Measures.FirstOrDefault(x => x.Name == twinName);
    if (twin == null) twin = src.Table.AddMeasure(twinName);

    var expression = "Real.Deflate ( [" + name + "] )";
    if (twin.Expression != expression) twin.Expression = expression;
    if (twin.FormatString != src.FormatString) twin.FormatString = src.FormatString;
    if (twin.DisplayFolder != Folder) twin.DisplayFolder = Folder;

    var description =
        "[" + name + "] in 2025-26 prices, in GBP thousands, spending positive and income negative as in the nominal measure. " +
        "Each financial year in context is multiplied by the GDP deflator index of 2025-26 divided by the index of that year " +
        "(HM Treasury, default vintage October 2026 Budget, chained index: forecast years are chained from that one vintage), " +
        "and the years are added. A month takes the index of its financial year. BLANK when a year that has an amount has no " +
        "index, never the nominal figure. Under Time Intelligence, PY is the previous year in 2025-26 prices, YoY is the real " +
        "change and YoY % the real growth rate. The Deflator table is related to nothing; the index is matched to the year " +
        "with TREATAS inside Real.Deflate.";
    if (src.Table.Name.EndsWith("(derived)"))
        description = "DERIVED, not published: the phased plan is my allocation of the published annual plan. " + description;
    if (twin.Description != description) twin.Description = description;

    // A fixed tag per name, so that rebuilding the twin gives the same tag.
    if (string.IsNullOrEmpty(twin.LineageTag))
    {
        var md5 = System.Security.Cryptography.MD5.Create();
        var bytes = md5.ComputeHash(System.Text.Encoding.UTF8.GetBytes("ukfr-real-terms:" + twinName));
        twin.LineageTag = new Guid(bytes).ToString();
    }
}

if (problems.Count > 0)
    throw new Exception(problems.Count + " problem(s):\n  " + string.Join("\n  ", problems));
Info("Real-terms measures written for " + sources.Count + " measures.");
