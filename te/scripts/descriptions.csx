// descriptions.csx
//
// Checks that every visible object of the model has a description and fails, listing the offenders,
// when one has not. It never writes a description: the text is written by hand in the TMDL file
// (a /// line above the object), so the description is reviewed where the object is defined.
//
// Checked: visible tables, visible columns, visible measures, calculation items, functions,
// perspectives. Hidden columns and hidden measures are left alone (keys and technical columns).
//
// Run (from the repository root, Windows PowerShell 5.1 or PowerShell 7):
//   powershell.exe -NoProfile -File tools\run_te_script.ps1 -Script te\scripts\descriptions.csx
// Exit code 1 and a list of "Table[Column]" style names when anything is missing. The script changes
// nothing, so the wrapper reports "No file changed".

var offenders = new List<string>();

foreach (var t in Model.Tables)
{
    if (!t.IsHidden && string.IsNullOrWhiteSpace(t.Description)) offenders.Add("table " + t.Name);
    foreach (var c in t.Columns)
        if (!c.IsHidden && string.IsNullOrWhiteSpace(c.Description))
            offenders.Add("column " + t.Name + "[" + c.Name + "]");
    foreach (var m in t.Measures)
        if (!m.IsHidden && string.IsNullOrWhiteSpace(m.Description))
            offenders.Add("measure " + t.Name + "[" + m.Name + "]");
}
foreach (var ci in Model.AllCalculationItems)
    if (string.IsNullOrWhiteSpace(ci.Description))
        offenders.Add("calculation item " + ci.CalculationGroupTable.Name + "[" + ci.Name + "]");
foreach (var f in Model.Functions)
    if (string.IsNullOrWhiteSpace(f.Description)) offenders.Add("function " + f.Name);
foreach (var p in Model.Perspectives)
    if (string.IsNullOrWhiteSpace(p.Description)) offenders.Add("perspective " + p.Name);

if (offenders.Count > 0)
{
    throw new Exception(offenders.Count + " object(s) without a description:\n  " + string.Join("\n  ", offenders));
}
Info("Every visible table, column, measure, calculation item, function and perspective has a description.");
