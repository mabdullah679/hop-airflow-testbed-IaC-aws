#!/bin/bash
# Runs the real Hop pipeline (hop-run) inside the app image on the sample data and asserts the output.
# Usage: scripts/hop_local_test.sh [image]
set -euo pipefail
IMG="${1:-pf-hop-airflow:local}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
docker run --rm -v "$ROOT/app/data:/data:ro" -e HOP_CONFIG_FOLDER=/opt/airflow/hop/config "$IMG" bash -c '
  set -e
  hop-run.sh --file=/opt/airflow/hop/orders_transform.hpl --runconfig=local \
    --parameters=INPUT_FILE=/data/orders.csv,OUTPUT_FILE=/tmp/out >/tmp/hop.log 2>&1 || { tail -30 /tmp/hop.log; exit 1; }
  python3 - <<PY
import csv
rows=list(csv.DictReader(open("/tmp/out.csv")))
assert len(rows)==18, len(rows)
r=[x for x in rows if x["order_id"]=="1001"][0]
assert abs(float(r["line_total"])-50.0)<1e-6, r
assert not any(float(x["unit_price"])<=0 for x in rows)
print("hop output OK: rows=%d, 1001.line_total=%s" % (len(rows), r["line_total"]))
PY
'
