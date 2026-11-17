"""ukfr.readers.oscar_bud on a tiny workbook built from two published rows of BUD_24-25.xlsx (Nov 2025)."""

from __future__ import annotations

import io
import zipfile
from decimal import Decimal
from xml.sax.saxutils import escape

import pytest
from python_calamine import CalamineWorkbook

from ukfr.readers.oscar_bud import BUD_COLUMNS, BudFormatError, BudStats, read_bud_workbook

# Two rows of BUD_24-25.xlsx (OGL v3.0); columns not listed here are blank in the source.
_COMMON = {
    "YEAR_NO": 202425, "YEAR_SHORT_NAME": 202425, "QUARTER_SHORT_NAME": "P00", "MONTH_SHORT_NAME": "P00",
    "DEPARTMENT_GROUP_CODE": "DID030.GROUP",
    "DEPARTMENT_GROUP_LONG_NAME": "FOREIGN, COMMONWEALTH AND DEVELOPMENT OFFICE (GROUP)",
    "ORGANISATION_CODE": "DID030", "ORGANISATION_LONG_NAME": "Foreign, Commonwealth and Development Office",
    "ORGANISATION_TYPE_CODE": "CG", "ORGANISATION_TYPE_LONG_NAME": "CENTRAL GOVERNMENT",
    "ORGANISATION_TYPE_L1_CODE": "DEPT", "ORGANISATION_TYPE_L1_LONG_NAME": "DEPARTMENT",
    "PESA_GROUP_CODE": "PESA_030", "PESA_GROUP_LONG_NAME": "Foreign, Commonwealth and Development Office",
    "SR_GROUP_CODE": "SR_030", "SR_GROUP_LONG_NAME": "Foreign, Commonwealth and Development Office",
    "CONTROL_BUDGET_L0_LONG_NAME": "NON-BUDGET", "CONTROL_BUDGET_L1_LONG_NAME": "NON-BUDGET",
    "USAGE_CODE": "BOTH", "STATUS_CODE": "Submitted", "TYPE_CODE": "TYPE_NONBUDGET", "TYPE_LONG_NAME": "NON-BUDGET",
    "TYPE_GROUP_CODE": "CONTROL", "TYPE_GROUP_LONG_NAME": "Control Totals", "VERSION_CODE": "Outturn",
}  # fmt: skip
ROWS = [
    {**_COMMON, "SEGMENT_L4_CODE": "X030A215",
     "SEGMENT_L4_LONG_NAME": "X030A215-UNALLOCATED - UNALLOCATED CFER - NON-BUDGET NON-VOTED",
     "CHART_OF_ACCOUNTS_L5_CODE": 61514000,
     "CHART_OF_ACCOUNTS_L5_LONG_NAME": "FI - INTEREST RECEIVABLE FROM PUBLIC CORPORATIONS (PC)",
     "ECONOMIC_BUDGET_CODE": "RESOURCE", "ECONOMIC_GROUP_CODE": "S3", "ECONOMIC_CATEGORY_CODE": "S302",
     "AMOUNT": -15260},
    {**_COMMON, "SEGMENT_L4_CODE": "X030A368", "SEGMENT_L4_LONG_NAME": "X030A368-OTHER NON-BUDGET",
     "CHART_OF_ACCOUNTS_L5_CODE": 91873000, "CHART_OF_ACCOUNTS_L5_LONG_NAME": "AI - CFER CASH RECEIPTS - NON-BUDGET",
     "ECONOMIC_BUDGET_CODE": "n/a", "ECONOMIC_GROUP_CODE": "n/a", "ECONOMIC_CATEGORY_CODE": "n/a", "AMOUNT": -15828},
]  # fmt: skip


def _col(i: int) -> str:
    s = ""
    i += 1
    while i:
        i, r = divmod(i - 1, 26)
        s = chr(65 + r) + s
    return s


def xlsx_bytes(sheets: list[tuple[str, list[list]]]) -> bytes:
    """A minimal xlsx with inline strings; numbers are written as numeric cells."""
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml",
                   '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/'
                   '2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-'
                   'package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
                   '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-'
                   'officedocument.spreadsheetml.sheet.main+xml"/>'
                   + "".join(f'<Override PartName="/xl/worksheets/sheet{i}.xml" ContentType="application/'
                             f'vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
                             for i in range(1, len(sheets) + 1)) + "</Types>")  # fmt: skip
        z.writestr(
            "_rels/.rels",
            '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/'
            'package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/'
            'officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
        )
        z.writestr("xl/workbook.xml",
                   '<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/'
                   'spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/'
                   'relationships"><sheets>'
                   + "".join(f'<sheet name="{escape(n)}" sheetId="{i}" r:id="rId{i}"/>'
                             for i, (n, _) in enumerate(sheets, start=1)) + "</sheets></workbook>")  # fmt: skip
        z.writestr("xl/_rels/workbook.xml.rels",
                   '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/'
                   'package/2006/relationships">'
                   + "".join(f'<Relationship Id="rId{i}" Type="http://schemas.openxmlformats.org/officeDocument/'
                             f'2006/relationships/worksheet" Target="worksheets/sheet{i}.xml"/>'
                             for i in range(1, len(sheets) + 1)) + "</Relationships>")  # fmt: skip
        for i, (_, rows) in enumerate(sheets, start=1):
            body = []
            for r, row in enumerate(rows, start=1):
                cells = []
                for c, v in enumerate(row):
                    ref = f"{_col(c)}{r}"
                    if v is None or v == "":
                        continue
                    if isinstance(v, (int, float)):
                        cells.append(f'<c r="{ref}"><v>{v}</v></c>')
                    else:
                        cells.append(f'<c r="{ref}" t="inlineStr"><is><t>{escape(str(v))}</t></is></c>')
                body.append(f'<row r="{r}">{"".join(cells)}</row>')
            z.writestr(
                f"xl/worksheets/sheet{i}.xml",
                '<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/'
                f'spreadsheetml/2006/main"><sheetData>{"".join(body)}</sheetData></worksheet>',
            )
    return buf.getvalue()


def workbook(rows=ROWS, header=BUD_COLUMNS, extra_sheet=True) -> CalamineWorkbook:
    data = [list(header)] + [[r.get(c, "") for c in header] for r in rows]
    sheets = [("Transparency_report_BUD_REPORTI", data)] + ([("Sheet1", [])] if extra_sheet else [])
    return CalamineWorkbook.from_filelike(io.BytesIO(xlsx_bytes(sheets)))


def test_reads_rows_as_text_and_exact_amounts():
    stats = BudStats()
    rows = list(read_bud_workbook(workbook(), "2025-11", "test", stats))
    assert stats.sheet == "Transparency_report_BUD_REPORTI" and stats.other_sheets == ["Sheet1"]
    assert stats.data_rows == 2 and stats.amount_forms == {"number_integral": 2}
    assert [r.amount for r in rows] == [Decimal("-15260"), Decimal("-15828")]
    assert rows[0]["YEAR_NO"] == "202425" and rows[0].financial_year == "2024-25"
    assert rows[0]["CHART_OF_ACCOUNTS_L5_CODE"] == "61514000"
    assert rows[1]["ECONOMIC_CATEGORY_CODE"] == "n/a" and rows[1]["COUNTER_ORGANISATION_CODE"] == ""


def test_fractional_amount_is_kept_exactly_and_counted():
    rows = [{**ROWS[0], "AMOUNT": 0.1}]
    stats = BudStats()
    (r,) = read_bud_workbook(workbook(rows), "2025-11", "test", stats)
    assert r.amount == Decimal("0.1") and stats.amount_forms == {"number_fraction": 1}


def test_wrong_header_fails():
    header = list(BUD_COLUMNS)
    header[-2] = "AMOUNT_GBP"
    with pytest.raises(BudFormatError, match="header is not the BUD layout"):
        list(read_bud_workbook(workbook(header=header), "2025-11", "test"))


def test_missing_data_sheet_fails():
    wb = CalamineWorkbook.from_filelike(io.BytesIO(xlsx_bytes([("Sheet1", [])])))
    with pytest.raises(BudFormatError, match="no sheet"):
        list(read_bud_workbook(wb, "2025-11", "test"))
