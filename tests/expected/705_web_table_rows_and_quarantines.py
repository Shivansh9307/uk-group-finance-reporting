"""Expected values for tests/dax/705: rows the Python reader parses from the pinned files, and no rejected rows."""

from ukfr import model_expected

COLUMNS = ["table_name", "row_count"]


def generate(root):
    cpi, _ = model_expected.cpi_values(root)
    deflators = model_expected.deflator_values(root)
    return COLUMNS, [
        ["CPI", len(cpi)],
        ["CPI Quarantine", 0],
        ["Deflator", len(deflators)],
        ["Deflator Quarantine", 0],
    ]
