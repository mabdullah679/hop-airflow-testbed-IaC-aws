"""Imports the DAG with real Airflow (run inside the app image in CI)."""
import os
import sys

import pytest

airflow = pytest.importorskip("airflow")
DAGS = os.environ.get("DAGS_DIR", os.path.join(os.path.dirname(__file__), "..", "app", "dags"))
sys.path.insert(0, DAGS)


def test_dag_loads_with_expected_shape():
    from airflow.models import DagBag
    bag = DagBag(DAGS, include_examples=False)
    assert not bag.import_errors, bag.import_errors
    dag = bag.get_dag("orders_hop_pipeline")
    assert [t.task_id for t in dag.topological_sort()] == [
        "fetch_and_validate", "run_hop_pipeline", "verify_and_publish"]
