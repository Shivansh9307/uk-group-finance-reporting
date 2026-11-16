"""Rewrite an RFC 4180 CSV as tab-separated text that bcp can load without quoting rules.

Fails if any field contains a tab or a line break, because bcp would split on it.
Usage: python csv_to_tsv.py <in.csv> <out.tsv>
"""

import csv
import sys

src, dst = sys.argv[1], sys.argv[2]
with open(src, encoding="utf-8", newline="") as fin, open(dst, "w", encoding="utf-8", newline="") as fout:
    reader = csv.reader(fin)
    next(reader)  # header; bcp is told nothing about it, so drop it here
    for row in reader:
        for field in row:
            if "\t" in field or "\n" in field or "\r" in field:
                raise SystemExit(f"field cannot be tab-delimited: {field!r}")
        fout.write("\t".join(row) + "\n")
