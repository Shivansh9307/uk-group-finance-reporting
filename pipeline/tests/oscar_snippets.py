"""A few lines cut from the published OSCAR in-year files (Open Government Licence v3.0).

Kept as bytes literals, not as fixture files, so that git's line-ending handling cannot change
them: the CRLF record ends, the bare LF inside a quoted field and the Windows-1252 bytes are exactly
as published. Each snippet is the header plus a few data lines from the release named.
"""

from __future__ import annotations

import io
import zipfile
from xml.sax.saxutils import escape

# 2019-06 (layout v2019, 17 columns): thousands separators, a Windows-1252 right quote (0x92), a
# "Period 0" line, and the blank trailing rows the early files carry.
V2019_JUN19 = (
    b"Organisation Code,Organisation,Control Budget Code,Control Budget Detail Code,Segment Department Long Name,"
    b"Sub Segment Code,Sub Segment Long Name,Economic Category Code,Economic Category Long Name,Economic Budget Code,"
    b"PESA Economic Group Code,PESA Economic Group Long Name,Version,Year,Quarter,Month,Amount\r\n"
    b'ACA084,"ADVISORY, CONCILIATION AND ARBITRATION SERVICE",DEL,DEL ADMIN,"Department for Business, Energy and '
    b'Industrial Strategy",X084A160,X084A160-ACAS DEL ADMIN VOTED,A101,PAY,RESOURCE,STAFF COSTS,Staff costs,OUTTURN,'
    b'2018-19,Qtr1 - 18-19,Apr-18,"2,394"\r\n'
    b"CAB010,CABINET OFFICE,DEL,DEL ADMIN,Cabinet Office,X010GPM1,X010GPM1 - Ensure the delivery of the Government"
    b"\x92s programme and the Prime Minister\x92s priorities.,A101,PAY,RESOURCE,STAFF COSTS,Staff costs,OUTTURN,"
    b'2018-19,Qtr1 - 18-19,Apr-18,"2,871"\r\n'
    b"CES014,CROWN ESTATE OFFICE,AME,DEPT AME,Crown Estate Office,X014A001,X014A001-CROWN ESTATE OFFICE (CEO) "
    b"(DEPT AME/VOTED),C301,SUBSIDIES TO PUBLIC CORPORATIONS,RESOURCE,SUBSIDIES TO PUBLIC CORPORATIONS,Subsidies to "
    b"public corporations,OUTTURN,2018-19,Period 0 - 18-19,Period 0 - 18-19,-8\r\n"
    b",,,,,,,,,,,,,,,,\r\n"
    b",,,,,,,,,,,,,,,,\r\n"
)

# 2019-09 (layout v2019): a line break inside a quoted sub-segment name.
V2019_SEP19 = (
    b"Organisation Code,Organisation,Control Budget Code,Control Budget Detail Code,Segment Department Long Name,"
    b"Sub Segment Code,Sub Segment Long Name,Economic Category Code,Economic Category Long Name,Economic Budget Code,"
    b"PESA Economic Group Code,PESA Economic Group Long Name,Version,Year,Quarter,Month,Amount\r\n"
    b'EWR004,EAST WEST RAIL,DEL,DEL ADMIN,Department for Transport,X004D388,"X004D388-East West Rai Ltd (ALB) DEL '
    b'Admin Voted\n",A101,PAY,RESOURCE,STAFF COSTS,Staff costs,RETURN4_AUG,2019-20,Qtr1 - 19-20,Apr-19,19\r\n'
)

# 2021-09 (layout v2021sep): "Organisation Name", "Control Budget Code", "Version Snapshot".
V2021SEP = (
    b"Organisation Code,Organisation Name,Control Budget Code,Control Budget Detail,Department,Sub-segment Code,"
    b"Sub-segment Name,Economic Category Code,Economic Category Name,Economic Budget,PESA Economic Group Code,"
    b"Version Snapshot,Year,Quarter,Month,Amount\r\n"
    b'ACA084,"Advisory, Conciliation and Arbitration Service",AME,DEPT AME,"Department for Business, Energy and '
    b'Industrial Strategy",X084A162,X084A162-ACAS DEPT AME VOTED,L101,TAKE UP OF PROVISION,RESOURCE,TAKE UP OF '
    b"PROVISIONS,MFO_202122_R04_PSF_v6,2021-22,Qtr1 - 21-22,Apr-21,0\r\n"
    b"YJB047,Youth Justice Board,DEL,DEL PROG,Ministry of Justice,X047A077,X047A077-YJB CENTRAL DEL PROG VOTED,"
    b"P101,DEPRECIATION/AMORTISATION,RESOURCE,DEPRECIATION,MFO_202122_R04_PSF_v6,2021-22,Qtr1 - 21-22,Jun-21,138\r\n"
)

# 2021-12 (layout v2021dec): as 2021-09 but "Control Budget".
V2021DEC = (
    b"Organisation Code,Organisation Name,Control Budget,Control Budget Detail,Department,Sub-segment Code,"
    b"Sub-segment Name,Economic Category Code,Economic Category Name,Economic Budget,PESA Economic Group Code,"
    b"Version Snapshot,Year,Quarter,Month,Amount\r\n"
    b"YJB047,Youth Justice Board,DEL,DEL PROG,Ministry of Justice,X047A077,X047A077-YJB CENTRAL DEL PROG VOTED,"
    b"P101,DEPRECIATION/AMORTISATION,RESOURCE,DEPRECIATION,MFO_202122_R07_PSF_v6,2021-22,Qtr2 - 21-22,Sep-21,138\r\n"
)

# 2026-09 (layout v2023): en dash (0x96) and no-break space (0xA0), scientific notation, decimals.
V2023_SEP26 = (
    b"Organisation Code,Organisation,Control Budget Code,Control Budget Detail Code,Segment Department Long Name,"
    b"Sub Segment Code,Sub Segment Long Name,Economic Category Code,Economic Category Long Name,Economic Budget Code,"
    b"PESA Economic Group Code,Version,Year,Quarter,Month,Amount\r\n"
    b'EFR003,"Department for Environment, Food and Rural Affairs",TOTAL DEL,DEL ADMIN,"Department for Environment, '
    b'Food and Rural Affairs",X003A103,X003A103-FARMING DIRECTORATE \x96 SCHEME COSTS DEL ADMIN VOTED,B101,PURCHASE '
    b"OF GOODS AND SERVICES,RESOURCE,PURCHASE OF GOODS AND SERVICES,MFO_2026-27_R05_PSF_v5 - WD10 1530,2026-27,"
    b"Qtr1 - 26-27,Apr-26,2\r\n"
    b'AHD003,Agriculture & Horticulture Development Board,TOTAL AME,DEPT AME,"Department for Environment, Food and '
    b'Rural Affairs",X003D108,X003D108-FOOD BIOSECURITY AND TRADE\xa0DG SPONSORED ALBS DIRECTORATE - AHDB DEPT AME '
    b"VOTED,E101,CAPITAL ADDITIONS - FIXED ASSETS (GENERAL),CAPITAL,PURCHASE OF ASSETS,MFO_2026-27_R05_PSF_v5 - "
    b"WD10 1530,2026-27,Qtr1 - 26-27,Apr-26,87\r\n"
    b"SCT075,Scottish Government,TOTAL NON-BUDGET,NON-BUDGET,Scottish Government,X075A400,X075A400-SCOTLAND RESERVE "
    b"NON-BUDGET,E101,CAPITAL ADDITIONS - FIXED ASSETS (GENERAL),CAPITAL,PURCHASE OF ASSETS,MFO_2026-27_R05_PSF_v5 - "
    b"WD10 1530,2026-27,Qtr1 - 26-27,Apr-26,-8.33E-05\r\n"
    b"YJB047,Youth Justice Board for England and Wales,TOTAL DEL,DEL PROG,Ministry of Justice,X047A077,X047A077-YJB "
    b"CENTRAL DEL PROG VOTED,B102,SALES OF GOODS AND SERVICES,RESOURCE,INCOME FROM SALES OF GOODS AND SERVICES,"
    b"MFO_2026-27_R05_PSF_v5 - WD10 1530,2026-27,Qtr1 - 26-27,Jun-26,-6.62978\r\n"
)

V2023_HEADER = (
    "Organisation Code", "Organisation", "Control Budget Code", "Control Budget Detail Code",
    "Segment Department Long Name", "Sub Segment Code", "Sub Segment Long Name", "Economic Category Code",
    "Economic Category Long Name", "Economic Budget Code", "PESA Economic Group Code", "Version", "Year", "Quarter",
    "Month", "Amount",
)  # fmt: skip

# 2026-03 (ODS, layout v2023): rows as they are in the published sheet; the amount is a float cell.
ODS_MAR26_ROWS = (
    ("AFS902", "Armed Forces Pension and Compensation Schemes", "TOTAL NON-BUDGET", "NON-BUDGET",
     "Armed Forces Pension and Compensation Schemes", "X902A001", "X902A001-AFPS RETIRED PAY AND PENSIONS NON-BUDGET",
     "NA", "N/A", "NA", "n/a", "MFO_2025-26_R11_PSF_v5 - WD9 1730", "2025-26", "Qtr1 - 25-26", "Apr-25", "16547"),
    ("AFS902", "Armed Forces Pension and Compensation Schemes", "TOTAL NON-BUDGET", "NON-BUDGET",
     "Armed Forces Pension and Compensation Schemes", "X902A001", "X902A001-AFPS RETIRED PAY AND PENSIONS NON-BUDGET",
     "NA", "N/A", "NA", "n/a", "MFO_2025-26_R11_PSF_v5 - WD9 1730", "2025-26", "Qtr1 - 25-26", "May-25", "-42528"),
    ("CAF047", "Children and Family Court Advisory and Support Service", "TOTAL DEL", "DEL ADMIN",
     "Ministry of Justice", "X047A134", "X047A134 - CHILDREN & YOUNG PEOPLE COURT ADVISORY BODIES DEL ADMIN VOTED",
     "Q102", "RENTAL INCOME", "RESOURCE", "RENTALS", "MFO_2025-26_R11_PSF_v5 - WD9 1730", "2025-26", "Qtr2 - 25-26",
     "Sep-25", "-7.0069999999999993E-2"),
)  # fmt: skip

_NS = (
    'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
    'xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" '
    'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"'
)


def _cell_text(v: str) -> str:
    return f'<table:table-cell office:value-type="string"><text:p>{escape(v)}</text:p></table:table-cell>'


def ods_bytes(sheets: list[tuple[str, list[list[tuple[str, str]]], int]]) -> bytes:
    """A minimal .ods: [(sheet name, rows, trailing blank rows)].

    A row is a list of (kind, value) cells, kind 'string' or 'float', or a tuple (cells, n) for a row
    the writer compressed with number-rows-repeated.
    """
    parts = [f'<?xml version="1.0" encoding="UTF-8"?><office:document-content {_NS}><office:body>'
             "<office:spreadsheet>"]  # fmt: skip
    for name, rows, blanks in sheets:
        parts.append(f'<table:table table:name="{escape(name)}">')
        for row in rows:
            cells, rep = row if isinstance(row, tuple) else (row, 1)
            parts.append(f'<table:table-row table:number-rows-repeated="{rep}">' if rep > 1 else "<table:table-row>")
            for kind, v in cells:
                if kind == "float":
                    parts.append(f'<table:table-cell office:value-type="float" office:value="{v}">'
                                 f"<text:p>{v}</text:p></table:table-cell>")  # fmt: skip
                else:
                    parts.append(_cell_text(v))
            parts.append('<table:table-cell table:number-columns-repeated="1008"/></table:table-row>')
        if blanks:
            parts.append(f'<table:table-row table:number-rows-repeated="{blanks}">'
                         '<table:table-cell table:number-columns-repeated="1024"/></table:table-row>')  # fmt: skip
        parts.append("</table:table>")
    parts.append("</office:spreadsheet></office:body></office:document-content>")
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("mimetype", "application/vnd.oasis.opendocument.spreadsheet")
        z.writestr("content.xml", "".join(parts))
    return buf.getvalue()


def ods_mar26(repeat_first_row: int = 1) -> bytes:
    """The 2026-03 layout: a pivot sheet first, then the data sheet with a long run of blank rows."""
    pivot = [[("string", "Control Budget Code"), ("string", "(All)")], [("string", "Grand Total"), ("float", "1.5")]]
    header = [("string", h) for h in V2023_HEADER]
    data = []
    for i, row in enumerate(ODS_MAR26_ROWS):
        cells = [("string", v) for v in row[:-1]] + [("float", row[-1])]
        data.append((cells, repeat_first_row) if i == 0 else cells)
    return ods_bytes([("Pivot", pivot, 0), ("OSCAR_in_year_dataset_Mar_2025", [header, *data], 1048000)])
