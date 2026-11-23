"""Expected rows for tests/dax/777_perspective_measures.dax: the measures that te/scripts/perspectives.csv puts in each
perspective. A row `Table` of the file adds the visible measures of that table (read here from the table's file); a row
`Table[Measure]` adds that one measure."""

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
                text = (root / MODEL / f"{obj}.tmdl").read_text(encoding="utf-8").replace("\r\n", "\n")
                for name in re.findall(r"^\tmeasure (.+?) =", text, flags=re.MULTILINE):
                    rows.append([r["perspective"], name.strip("'")])
    return COLUMNS, rows
