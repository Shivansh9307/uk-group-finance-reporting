"""Expected values for tests/dax/732: the format strings of the display unit, written out as a rule.

Nothing in the warehouse holds a format string, so the truth here is the rule that the model's description states:
Favourable/Adverse takes the words that go with the indicator, Variance % and YoY % of anything take a percentage, and
every other combination is an amount with the unit suffix. The pound sign is written as GBP, as in the DAX test.
"""

COLUMNS = [
    "Comparison",
    "Time Calculation",
    "kind",
    "format_k",
    "format_m",
    "format_bn",
]
COMPARISONS = ["Actual", "Plan", "Variance", "Variance %", "Favourable/Adverse"]
TIME_CALCULATIONS = [
    "Current",
    "MTD",
    "QTD",
    "YTD",
    "PY",
    "YoY",
    "YoY %",
    "Rolling 12 months",
]
INDICATOR = '[=1]"Favourable";[=-1]"Adverse";"On plan"'
PERCENT = "0.0%;-0.0%;0.0%"
AMOUNT = {
    "k": 'GBP#,##0"k";-GBP#,##0"k";GBP0"k"',
    "m": 'GBP#,##0.0"m";-GBP#,##0.0"m";GBP0.0"m"',
    "bn": 'GBP#,##0.00"bn";-GBP#,##0.00"bn";GBP0.00"bn"',
}


def generate(root):
    rows = []
    for comparison in COMPARISONS:
        for time_calculation in TIME_CALCULATIONS:
            if comparison == "Favourable/Adverse":
                kind = "indicator"
            elif comparison == "Variance %" or time_calculation == "YoY %":
                kind = "percent"
            else:
                kind = "amount"
            fixed = {"indicator": INDICATOR, "percent": PERCENT}.get(kind)
            rows.append(
                [comparison, time_calculation, kind]
                + [fixed or AMOUNT[unit] for unit in ("k", "m", "bn")]
            )
    return COLUMNS, rows
