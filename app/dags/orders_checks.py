"""Pure validation helpers for the orders pipeline (unit-tested, no Airflow/AWS imports)."""
import csv

EXPECTED_COLUMNS = ["order_id", "region", "unit_price", "quantity"]


class InputValidationError(ValueError):
    pass


def validate_orders_csv(path):
    """Validate the input file; return (total_rows, rows_with_positive_price)."""
    with open(path, newline="", encoding="utf-8") as fh:
        reader = csv.reader(fh)
        header = next(reader, None)
        if header != EXPECTED_COLUMNS:
            raise InputValidationError(f"bad header {header!r}, expected {EXPECTED_COLUMNS!r}")
        total = 0
        positive = 0
        for lineno, row in enumerate(reader, start=2):
            if len(row) != len(EXPECTED_COLUMNS):
                raise InputValidationError(f"line {lineno}: expected 4 fields, got {len(row)}")
            try:
                int(row[0])
                price = float(row[2])
                int(row[3])
            except ValueError as exc:
                raise InputValidationError(f"line {lineno}: non-numeric value ({exc})") from exc
            total += 1
            if price > 0:
                positive += 1
    if total == 0:
        raise InputValidationError("input has no data rows")
    return total, positive


def count_output_rows(path):
    with open(path, newline="", encoding="utf-8") as fh:
        return max(sum(1 for _ in fh) - 1, 0)  # minus header


def assert_output_matches(expected_rows, path):
    """Fail unless the Hop output has exactly the expected number of rows and a line_total column."""
    with open(path, newline="", encoding="utf-8") as fh:
        header = next(csv.reader(fh), [])
    if "line_total" not in header:
        raise AssertionError(f"output missing line_total column: {header!r}")
    actual = count_output_rows(path)
    if actual != expected_rows:
        raise AssertionError(f"output rows {actual} != expected {expected_rows}")
    return actual
