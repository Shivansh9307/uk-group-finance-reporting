"""Write a minimal xlsx (shared strings, numbers stored as text the way Excel stores them) so the
exact cell reader can be tested on cells copied from the real workbooks."""

from __future__ import annotations

import zipfile
from pathlib import Path
from xml.sax.saxutils import escape


def _col(i: int) -> str:
    s = ""
    i += 1
    while i:
        i, r = divmod(i - 1, 26)
        s = chr(65 + r) + s
    return s


def write_xlsx(path: Path, sheets: dict[str, list[list]]) -> Path:
    """`sheets`: name -> rows; a cell is None (blank), str (text) or ('n', '16.128999999999998') (number)."""
    strings: list[str] = []
    index: dict[str, int] = {}

    def sid(s: str) -> int:
        if s not in index:
            index[s] = len(strings)
            strings.append(s)
        return index[s]

    sheet_xml = []
    for rows in sheets.values():
        out = []
        for r, row in enumerate(rows, start=1):
            cells = []
            for c, v in enumerate(row):
                ref = f"{_col(c)}{r}"
                if v is None:
                    continue
                if isinstance(v, tuple):
                    cells.append(f'<c r="{ref}"><v>{v[1]}</v></c>')
                else:
                    cells.append(f'<c r="{ref}" t="s"><v>{sid(v)}</v></c>')
            out.append(f'<row r="{r}">{"".join(cells)}</row>')
        sheet_xml.append(
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
            f"<sheetData>{''.join(out)}</sheetData></worksheet>"
        )
    ns = 'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"'
    rns = 'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
    wb = (
        f'<?xml version="1.0" encoding="UTF-8"?><workbook {ns} {rns}><sheets>'
        + "".join(f'<sheet name="{escape(n)}" sheetId="{i + 1}" r:id="rId{i + 1}"/>' for i, n in enumerate(sheets))
        + "</sheets></workbook>"
    )
    rels = (
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        + "".join(
            f'<Relationship Id="rId{i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/'
            f'relationships/worksheet" Target="worksheets/sheet{i + 1}.xml"/>'
            for i in range(len(sheets))
        )
        + "</Relationships>"
    )
    sst = (
        f'<?xml version="1.0" encoding="UTF-8"?><sst {ns} count="{len(strings)}">'
        + "".join(f"<si><t>{escape(s)}</t></si>" for s in strings)
        + "</sst>"
    )
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as z:
        z.writestr("xl/workbook.xml", wb)
        z.writestr("xl/_rels/workbook.xml.rels", rels)
        z.writestr("xl/sharedStrings.xml", sst)
        for i, x in enumerate(sheet_xml):
            z.writestr(f"xl/worksheets/sheet{i + 1}.xml", x)
    return path
