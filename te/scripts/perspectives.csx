// perspectives.csx
//
// Builds the perspectives of the model from te/scripts/perspectives.csv and nothing else. The file has the columns
//
//   perspective,object,description
//
// A row with an empty object names a perspective and gives its description. Any other row puts one object in it:
//   Table             the table with every visible column, measure and hierarchy
//   Table[Name]       one column or measure (the table comes with it)
// Hidden objects are never put in a perspective, and a path that does not resolve, or names a hidden object, makes the
// script fail. A perspective in the model that is not in the file is deleted, and the contents of the ones in the file
// are rebuilt from the file, so the file is the whole truth.
//
// A perspective narrows the field list a report author sees. It does not secure anything: a query can still name an
// object outside it (docs/model.md, "Perspectives").
//
// Run (from the repository root):
//   powershell.exe -NoProfile -File tools\run_te_script.ps1 -Script te\scripts\perspectives.csx
// Running it twice gives no second change.

var root = Environment.GetEnvironmentVariable("UKFR_REPO_ROOT");
if (string.IsNullOrEmpty(root)) throw new Exception("UKFR_REPO_ROOT is not set: run this script through tools\\run_te_script.ps1");
var csvPath = System.IO.Path.Combine(root, "te", "scripts", "perspectives.csv");

// One CSV line into cells (double quotes protect commas; "" is a quote).
Func<string, List<string>> splitLine = delegate(string line)
{
    var cells = new List<string>();
    var cur = new System.Text.StringBuilder();
    var quoted = false;
    for (int i = 0; i < line.Length; i++)
    {
        var ch = line[i];
        if (quoted)
        {
            if (ch == '"' && i + 1 < line.Length && line[i + 1] == '"') { cur.Append('"'); i++; }
            else if (ch == '"') quoted = false;
            else cur.Append(ch);
        }
        else if (ch == '"') quoted = true;
        else if (ch == ',') { cells.Add(cur.ToString()); cur.Clear(); }
        else cur.Append(ch);
    }
    cells.Add(cur.ToString());
    return cells;
};

var descriptions = new Dictionary<string, string>();
var order = new List<string>();
var members = new List<string[]>();
var problems = new List<string>();
var lines = System.IO.File.ReadAllLines(csvPath, System.Text.Encoding.UTF8);
for (int n = 1; n < lines.Length; n++)
{
    if (string.IsNullOrWhiteSpace(lines[n])) continue;
    var c = splitLine(lines[n]);
    if (c.Count != 3) { problems.Add("line " + (n + 1) + ": expected 3 cells, found " + c.Count); continue; }
    var p = c[0].Trim();
    if (!order.Contains(p)) order.Add(p);
    if (c[1].Trim() == "") descriptions[p] = c[2];
    else members.Add(new string[] { p, c[1].Trim() });
}
foreach (var p in order)
    if (!descriptions.ContainsKey(p) || string.IsNullOrWhiteSpace(descriptions[p]))
        problems.Add("perspective " + p + " has no description row");

// Remove perspectives that are not in the file, create the ones that are missing.
foreach (var existing in Model.Perspectives.ToList())
    if (!order.Contains(existing.Name)) existing.Delete();
foreach (var p in order)
{
    var persp = Model.Perspectives.FirstOrDefault(x => x.Name == p);
    if (persp == null) persp = Model.AddPerspective(p);
    if (descriptions.ContainsKey(p) && persp.Description != descriptions[p]) persp.Description = descriptions[p];
    // Start from empty so that the file decides.
    foreach (var t in Model.Tables) t.InPerspective[p] = false;
}

foreach (var m in members)
{
    var p = m[0];
    var path = m[1];
    var open = path.IndexOf('[');
    if (open < 0)
    {
        var t = Model.Tables.FirstOrDefault(x => x.Name == path);
        if (t == null) { problems.Add(p + ": no table " + path); continue; }
        if (t.IsHidden) { problems.Add(p + ": table " + path + " is hidden"); continue; }
        foreach (var col in t.Columns.Where(x => !x.IsHidden)) col.InPerspective[p] = true;
        foreach (var me in t.Measures.Where(x => !x.IsHidden)) me.InPerspective[p] = true;
        foreach (var h in t.Hierarchies.Where(x => !x.IsHidden)) h.InPerspective[p] = true;
        // A table with only hidden columns and no measure would otherwise not be in the perspective at all.
        t.InPerspective[p] = true;
        foreach (var col in t.Columns.Where(x => x.IsHidden)) col.InPerspective[p] = false;
        foreach (var me in t.Measures.Where(x => x.IsHidden)) me.InPerspective[p] = false;
        foreach (var h in t.Hierarchies.Where(x => x.IsHidden)) h.InPerspective[p] = false;
    }
    else
    {
        if (!path.EndsWith("]")) { problems.Add(p + ": " + path + " is not Table or Table[Name]"); continue; }
        var tableName = path.Substring(0, open);
        var objName = path.Substring(open + 1, path.Length - open - 2);
        var t = Model.Tables.FirstOrDefault(x => x.Name == tableName);
        if (t == null) { problems.Add(p + ": no table " + tableName); continue; }
        var me = t.Measures.FirstOrDefault(x => x.Name == objName);
        var col = t.Columns.FirstOrDefault(x => x.Name == objName);
        if (me != null)
        {
            if (me.IsHidden) problems.Add(p + ": measure " + path + " is hidden");
            else me.InPerspective[p] = true;
        }
        else if (col != null)
        {
            if (col.IsHidden) problems.Add(p + ": column " + path + " is hidden");
            else col.InPerspective[p] = true;
        }
        else problems.Add(p + ": no measure or column " + path);
    }
}

if (problems.Count > 0)
    throw new Exception(problems.Count + " problem(s):\n  " + string.Join("\n  ", problems));
Info(order.Count + " perspective(s) built from perspectives.csv.");
