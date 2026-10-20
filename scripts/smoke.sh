#!/bin/bash
# Smoke test run from CI (or a laptop) via SSM: triggers the DAG on the instance, waits for SUCCESS,
# then checks the output object in S3. Never prints secrets. Usage: smoke.sh <instance-id> <bucket>
set -euo pipefail
IID="$1"; BUCKET="$2"; R=ap-southeast-2
run_ssm() { "$(dirname "$0")/ssm_run.sh" "$IID" 120 "$1"; }
echo "== waiting for webserver health"
for _ in $(seq 1 60); do
  out=$(run_ssm "curl -s -o /dev/null -w %{http_code} http://localhost:8080/health" || true)
  [ "$out" = "200" ] && break; sleep 10
done
[ "$out" = "200" ] || { echo "webserver not healthy: $out"; exit 1; }
RUN="smoke_$(date +%s)"
echo "== trigger DAG run $RUN"
run_ssm "cd /opt/pf/app && docker compose exec -T scheduler airflow dags unpause orders_hop_pipeline >/dev/null && docker compose exec -T scheduler airflow dags trigger orders_hop_pipeline -r $RUN >/dev/null && echo triggered" >/dev/null
for _ in $(seq 1 40); do
  st=$(run_ssm "cd /opt/pf/app && docker compose exec -T scheduler airflow dags list-runs -d orders_hop_pipeline -o json" | python3 -c "
import json,sys
runs=[r for r in json.load(sys.stdin) if r['run_id']=='$RUN']
print(runs[0]['state'] if runs else 'none')")
  echo "state=$st"
  case "$st" in success) break;; failed) echo "DAG run failed"; exit 1;; esac
  sleep 15
done
[ "$st" = "success" ] || { echo "DAG did not finish"; exit 1; }
aws s3 cp --region $R "s3://$BUCKET/output/latest/orders_enriched.csv" - | python3 -c "
import sys
n=len(sys.stdin.read().splitlines())-1
print('output rows:',n); assert n==18, n"
echo "SMOKE OK"
