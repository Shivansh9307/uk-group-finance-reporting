"""Minimal streaming reader for OpenDocument spreadsheets (.ods).

I parse `content.xml` myself instead of going through a spreadsheet library because the libraries
hand numbers back as floats, and I want the exact text that the file stores in `office:value`.
Rows that the file compresses with `table:number-rows-repeated` are expanded, so identical
consecutive data rows are not lost; long runs of empty rows are reported as a count only.
"""

from __future__ import annotations

import io
import zipfile
from collections.abc import Iterator
from dataclasses import dataclass
from typing import IO
from xml.etree.ElementTree import iterparse

_T = "{urn:oasis:names:tc:opendocument:xmlns:table:1.0}"
_O = "{urn:oasis:names:tc:opendocument:xmlns:office:1.0}"
_X = "{urn:oasis:names:tc:opendocument:xmlns:text:1.0}"

TABLE = _T + "table"
ROW = _T + "table-row"
CELL = _T + "table-cell"
COVERED = _T + "covered-table-cell"
NAME = _T + "name"
ROWS_REPEATED = _T + "number-rows-repeated"
COLS_REPEATED = _T + "number-columns-repeated"
VALUE_TYPE = _O + "value-type"
VALUE = _O + "value"


@dataclass(frozen=True, slots=True)
class Cell:
    """One cell: `kind` is the ODS value type ('float', 'string', ...) or '' when empty."""

    kind: str
    text: str


EMPTY = Cell("", "")


@dataclass(frozen=True, slots=True)
class SheetRow:
    sheet: str
    cells: tuple[Cell, ...]  # trailing empty cells removed
    repeat: int  # how many identical rows this stands for (>1 only for runs of blank rows)

    @property
    def blank(self) -> bool:
        return not any(c.text.strip() for c in self.cells)


def _paragraph_text(p) -> str:
    out = [p.text or ""]
    for child in p:
        tag = child.tag
        if tag == _X + "s":
            out.append(" " * int(child.get(_X + "c", "1")))
        elif tag == _X + "tab":
            out.append("\t")
        elif tag == _X + "line-break":
            out.append("\n")
        else:  # text:span, text:a and the like hold text of their own
            out.append(_paragraph_text(child))
        out.append(child.tail or "")
    return "".join(out)


def _cell(el) -> Cell:
    kind = el.get(VALUE_TYPE, "")
    if kind in ("float", "percentage", "currency"):
        return Cell(kind, el.get(VALUE, ""))
    if kind in ("date",):
        return Cell(kind, el.get(_O + "date-value", ""))
    if kind in ("time",):
        return Cell(kind, el.get(_O + "time-value", ""))
    if kind in ("boolean",):
        return Cell(kind, el.get(_O + "boolean-value", ""))
    paras = [_paragraph_text(p) for p in el.findall(_X + "p")]
    text = "\n".join(paras)
    if kind == "string" and not paras:
        text = el.get(_O + "string-value", "")
    return Cell(kind if (kind or text) else "", text)


def iter_rows(stream: IO[bytes], max_cols: int = 64) -> Iterator[SheetRow]:
    """Yield every row of every sheet from an ODS file object, in document order.

    `max_cols` caps how far repeated cells are expanded; the OSCAR sheets have 16 or 17 columns.
    """
    with zipfile.ZipFile(stream) as z, z.open("content.xml") as f:
        sheet = ""
        for event, el in iterparse(f, events=("start", "end")):
            if event == "start":
                if el.tag == TABLE:
                    sheet = el.get(NAME, "")
                continue
            if el.tag != ROW:
                if el.tag == TABLE:
                    el.clear()
                continue
            cells: list[Cell] = []
            for c in el:
                if c.tag not in (CELL, COVERED):
                    continue
                n = int(c.get(COLS_REPEATED, "1"))
                value = _cell(c)
                room = max_cols - len(cells)
                if room <= 0:
                    if value.text.strip():
                        raise ValueError(f"sheet {sheet!r}: data beyond column {max_cols}")
                    continue
                cells.extend([value] * min(n, room))
            while cells and not cells[-1].text.strip():
                cells.pop()
            repeat = int(el.get(ROWS_REPEATED, "1"))
            el.clear()
            row = SheetRow(sheet, tuple(cells), 1)
            if row.blank:
                yield SheetRow(sheet, (), repeat)
            else:
                for _ in range(repeat):  # identical data rows compressed by the writer
                    yield row


def iter_rows_from_bytes(data: bytes, max_cols: int = 64) -> Iterator[SheetRow]:
    return iter_rows(io.BytesIO(data), max_cols=max_cols)
