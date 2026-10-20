#!/bin/bash
# Tear everything down: main stack, instance-created SSM secrets, then (optionally) bootstrap.
# Usage: scripts/destroy.sh [--with-bootstrap]
set -euo pipefail
cd "$(dirname "$0")/../infra"
terraform init -input=false >/dev/null
terraform destroy -auto-approve -input=false -var "allowed_cidr=${ALLOWED_CIDR:-203.0.113.1/32}"
for p in airflow-admin-password postgres-password; do
  aws ssm delete-parameter --region ap-southeast-2 --name "/pf-hop-airflow/$p" 2>/dev/null || true
done
if [ "${1:-}" = "--with-bootstrap" ]; then
  cd bootstrap && terraform init -input=false >/dev/null && terraform destroy -auto-approve -input=false
fi
