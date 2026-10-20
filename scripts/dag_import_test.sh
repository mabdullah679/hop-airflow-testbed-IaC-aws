#!/bin/bash
# Runs the DAG import test with real Airflow inside the app image. Usage: dag_import_test.sh [image]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
docker run --rm -v "$ROOT/tests:/t:ro" -v "$ROOT/app/dags:/opt/airflow/dags:ro" \
  -e DAGS_DIR=/opt/airflow/dags -e PYTHONPATH=/opt/airflow/dags "${1:-pf-hop-airflow:local}" \
  bash -c "airflow db migrate >/dev/null 2>&1; pip install -q pytest >/dev/null 2>&1; cd /tmp && pytest -q /t/test_dag_import.py -p no:cacheprovider"
