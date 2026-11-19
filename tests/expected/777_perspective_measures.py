"""Expected rows for tests/dax/777_perspective_measures.dax: the measures that te/scripts/perspectives.csv puts in each
perspective. A row `Table` of the file adds the visible measures of that table, and no table named that way has one
(checked here), so the measures are the `Table[Measure]` rows."""

import csv
import re
from pathlib import Path

COLUMNS = ["CUBE_NAME", "MEASURE_NAME"]
MODEL = Path("model") / "UKGroupFinance.SemanticModel" / "definition" / "tables"


def generate(root):
    rows = []
    with (root / "te" / "scripts" / "perspectives.csv").open(encoding="utf-8", newline="") as fh:
        for r in csv.DictReader(fh):
            obj = r["object"].strip()
            if not obj:
                continue
            m = re.match(r"^(.+?)\[(.+)\]$", obj)
            if m:
                rows.append([r["perspective"], m.group(2)])
            else:
                text = (root / MODEL / f"{obj}.tmdl").read_text(encoding="utf-8")
                assert "\n\tmeasure " not in text, f"{obj} holds measures: list them as {obj}[Name] or extend this test"
    return COLUMNS, rows
