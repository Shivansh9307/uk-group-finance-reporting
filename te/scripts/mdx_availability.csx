// mdx_availability.csx
//
// Sets IsAvailableInMDX on every column of the model by one rule:
//   a hidden column that is not used as a sort-by column, in a hierarchy or in a variation is false (an
//   attribute hierarchy for it would only cost memory: no client can pick a hidden column);
//   a column that is used as a sort-by column, in a hierarchy or in a variation is true (the engine needs it);
//   every other column is left as it is.
// This is the fix of two Best Practice Analyzer rules (ISAVAILABLEINMDX_FALSE_NONATTRIBUTE_COLUMNS and
// SET_ISAVAILABLEINMDX_TO_TRUE_ON_NECESSARY_COLUMNS) applied as a script, so that a new hidden key is dealt with by
// running it. DAX does not read the property; it changes what an MDX client such as Excel can see.
//
// Run (from the repository root):
//   powershell.exe -NoProfile -File tools\run_te_script.ps1 -Script te\scripts\mdx_availability.csx
// Running it twice gives no second change.

int off = 0, on = 0;
foreach (var c in Model.AllColumns)
{
    bool needed = c.UsedInSortBy.Any() || c.UsedInHierarchies.Any() || c.UsedInVariations.Any() || c.SortByColumn != null;
    if (needed)
    {
        if (!c.IsAvailableInMDX) { c.IsAvailableInMDX = true; on++; }
    }
    else if (c.IsHidden && c.IsAvailableInMDX)
    {
        c.IsAvailableInMDX = false;
        off++;
    }
}
Info("IsAvailableInMDX: " + off + " hidden column(s) set to false, " + on + " column(s) set to true.");
