"""Expected rows for tests/dax/773_real_terms_2025_26_is_nominal.dax. In the price base year the factor is exactly 1 (the
index of 2025-26 divided by itself), so every real-terms measure equals its nominal twin and none is blank. Written
out; the one number the test relies on, the index of 2025-26, is checked against the pinned workbook first."""

from decimal import Decimal

from ukfr import model_expected

COLUMNS = ["measure", "real_minus_nominal", "real_is_blank"]
MEASURES = [
    "Outturn",
    "Plan",
    "Plan (phased)",
    "Outturn (plan basis)",
    "Outturn (current structure)",
    "Statement Amount",
    "Statement Plan",
]


def generate(root):
    factor = model_expected.real_terms_factors(root)
    assert factor[model_expected.REAL_BASE_YEAR] == Decimal(1), factor[model_expected.REAL_BASE_YEAR]
    return COLUMNS, [[m, Decimal(0), 0] for m in MEASURES]
