"""Expected rows for tests/dax/750_statement_measure_parameter_rows.dax: the four values of the Statement Measure field
parameter and the measure each one points at. This is what the parameter is meant to be, written out; no warehouse
table holds it."""

COLUMNS = ["Statement Measure", "fields", "measure_order"]

ROWS = [
    ["Outturn", "'Fact Outturn'[Statement Amount]", 0],
    ["Plan", "'Fact Plan'[Statement Plan]", 1],
    ["Variance", "'Fact Outturn'[Statement Variance]", 2],
    ["Variance %", "'Fact Outturn'[Statement Variance %]", 3],
]


def generate(root):
    return COLUMNS, [list(r) for r in ROWS]
