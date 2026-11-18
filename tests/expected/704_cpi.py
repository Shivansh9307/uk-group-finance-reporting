"""Expected values for tests/dax/704_cpi.dax: the pinned local copies of the two ONS CPI files."""

from ukfr import model_expected

COLUMNS = ["series_id", "month", "value"]


def generate(root):
    items, latest = model_expected.cpi_values(root)
    if latest != "2026-09-01":
        raise ValueError(
            f"the pinned files end at {latest}; tests/dax/704_cpi.dax and 705 hold 2026-09-01 as a literal"
        )
    return COLUMNS, [[i[c] for c in COLUMNS] for i in items]
