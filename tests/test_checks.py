import os
import sys

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "app", "dags"))
from orders_checks import InputValidationError, assert_output_matches, validate_orders_csv

SAMPLE = os.path.join(os.path.dirname(__file__), "..", "app", "data", "orders.csv")


def w(tmp_path, text):
    p = tmp_path / "f.csv"
    p.write_text(text)
    return str(p)


def test_sample_counts():
    assert validate_orders_csv(SAMPLE) == (20, 18)


def test_bad_header_rejected(tmp_path):
    with pytest.raises(InputValidationError):
        validate_orders_csv(w(tmp_path, "id,region,price,qty\n1,apac,2.0,3\n"))


def test_non_numeric_rejected(tmp_path):
    with pytest.raises(InputValidationError):
        validate_orders_csv(w(tmp_path, "order_id,region,unit_price,quantity\n1,apac,abc,2\n"))


def test_short_row_rejected(tmp_path):
    with pytest.raises(InputValidationError):
        validate_orders_csv(w(tmp_path, "order_id,region,unit_price,quantity\n1,apac,2\n"))


def test_empty_rejected(tmp_path):
    with pytest.raises(InputValidationError):
        validate_orders_csv(w(tmp_path, "order_id,region,unit_price,quantity\n"))


def test_output_row_count_guard(tmp_path):
    p = w(tmp_path, "order_id,line_total\n1,2\n2,3\n")
    assert assert_output_matches(2, p) == 2
    with pytest.raises(AssertionError):
        assert_output_matches(3, p)


def test_output_requires_line_total(tmp_path):
    with pytest.raises(AssertionError):
        assert_output_matches(1, w(tmp_path, "order_id\n1\n"))
