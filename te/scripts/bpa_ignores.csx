// bpa_ignores.csx
//
// Writes the per-object ignore annotations of the Best Practice Analyzer from te/bpa/ignores.csv, and removes every
// other one. Each row is one rule that is right in general and wrong for one object, with the reason beside it:
//
//   object,rule_id,reason
//   table:Name              a table (also a calculated table)
//   column:Table[Name]      a column
//   measure:Table[Name]     a measure
//   partition:Table         the partition of a table (partitions carry the name of their table in this model)
//
// A row that names an object or a rule that does not exist makes the script fail, so an ignore cannot outlive its
// object. There is no model-level or blanket ignore. The README of te/bpa lists every row with its reason.
//
// Run (from the repository root):
//   powershell.exe -NoProfile -File tools\run_te_script.ps1 -Script te\scripts\bpa_ignores.csx
// Running it twice gives no second change.

const string Annotation = "BestPracticeAnalyzer_IgnoreRules";
var root = Environment.GetEnvironmentVariable("UKFR_REPO_ROOT");
if (string.IsNullOrEmpty(root)) throw new Exception("UKFR_REPO_ROOT is not set: run this script through tools\run_te_script.ps1");

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

// Rule ids that exist in the rules file.
var ruleIds = new HashSet<string>();
var rulesText = System.IO.File.ReadAllText(System.IO.Path.Combine(root, "te", "bpa", "rules.json"), System.Text.Encoding.UTF8);
foreach (var ruleDef in Newtonsoft.Json.Linq.JArray.Parse(rulesText))
    ruleIds.Add((string)ruleDef["ID"]);

var wanted = new Dictionary<TabularNamedObject, List<string>>();
var problems = new List<string>();
var lines = System.IO.File.ReadAllLines(System.IO.Path.Combine(root, "te", "bpa", "ignores.csv"), System.Text.Encoding.UTF8);
for (int n = 1; n < lines.Length; n++)
{
    if (string.IsNullOrWhiteSpace(lines[n])) continue;
    var c = splitLine(lines[n]);
    if (c.Count != 3 || string.IsNullOrWhiteSpace(c[2])) { problems.Add("line " + (n + 1) + ": object, rule_id and a reason are all needed"); continue; }
    var obj = c[0].Trim();
    var rule = c[1].Trim();
    if (!ruleIds.Contains(rule)) { problems.Add("line " + (n + 1) + ": no rule " + rule + " in te/bpa/rules.json"); continue; }
    var colon = obj.IndexOf(':');
    var kind = colon < 0 ? "" : obj.Substring(0, colon);
    var path = colon < 0 ? obj : obj.Substring(colon + 1);
    TabularNamedObject target = null;
    if (kind == "table") target = Model.Tables.FirstOrDefault(x => x.Name == path);
    else if (kind == "partition")
    {
        var t = Model.Tables.FirstOrDefault(x => x.Name == path);
        if (t != null) target = t.Partitions.FirstOrDefault();
    }
    else if (kind == "column" || kind == "measure")
    {
        var open = path.IndexOf('[');
        if (open > 0 && path.EndsWith("]"))
        {
            var t = Model.Tables.FirstOrDefault(x => x.Name == path.Substring(0, open));
            var name = path.Substring(open + 1, path.Length - open - 2);
            if (t != null && kind == "column") target = t.Columns.FirstOrDefault(x => x.Name == name);
            if (t != null && kind == "measure") target = t.Measures.FirstOrDefault(x => x.Name == name);
        }
    }
    if (target == null) { problems.Add("line " + (n + 1) + ": no object " + obj); continue; }
    if (!wanted.ContainsKey(target)) wanted[target] = new List<string>();
    if (!wanted[target].Contains(rule)) wanted[target].Add(rule);
}

// Clear every existing ignore annotation, then write the ones in the file.
var all = new List<TabularNamedObject>();
foreach (var t in Model.Tables)
{
    all.Add(t);
    foreach (var col in t.Columns) all.Add(col);
    foreach (var me in t.Measures) all.Add(me);
    foreach (var p in t.Partitions) all.Add(p);
}
foreach (var o in all)
{
    dynamic d = o;
    if (!wanted.ContainsKey(o) && d.GetAnnotation(Annotation) != null) d.RemoveAnnotation(Annotation);
}
foreach (var kv in wanted)
{
    var ids = kv.Value.OrderBy(x => x, StringComparer.Ordinal).ToList();
    var json = "{\"RuleIDs\":[" + string.Join(",", ids.Select(x => "\"" + x + "\"")) + "]}";
    dynamic d = kv.Key;
    if (d.GetAnnotation(Annotation) != json) d.SetAnnotation(Annotation, json);
}

if (problems.Count > 0)
    throw new Exception(problems.Count + " problem(s):\n  " + string.Join("\n  ", problems));
Info(wanted.Count + " object(s) carry an ignore annotation.");
