"""Expected values for tests/dax/703_deflators.dax: the pinned local copies of the three deflator workbooks."""

from ukfr import model_expected

COLUMNS = [
    "vintage_id",
    "financial_year",
    "year_status",
    "index_published",
    "per_cent_change",
    "chained_index",
]


def generate(root):
    rows = [
        [item[c] if item[c] is not None else "" for c in COLUMNS]
        for item in model_expected.deflator_values(root)
    ]
    return COLUMNS, rows
