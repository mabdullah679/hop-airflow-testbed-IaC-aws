"""Imports the DAG with real Airflow (run inside the app image in CI)."""
import os
import sys

import pytest

airflow = pytest.importorskip("airflow")
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "app", "dags"))


def test_dag_loads_with_expected_shape():
    from airflow.models import DagBag
    bag = DagBag(os.path.join(os.path.dirname(__file__), "..", "app", "dags"), include_examples=False)
    assert not bag.import_errors, bag.import_errors
    dag = bag.get_dag("orders_hop_pipeline")
    assert [t.task_id for t in dag.topological_sort()] == [
        "fetch_and_validate", "run_hop_pipeline", "verify_and_publish"]
