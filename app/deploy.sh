#!/bin/bash
# Idempotent: sync app bundle from S3, ensure secrets exist in SSM, (re)build image, (re)start stack.
# Secrets are generated on the host and stored in SSM; they are never echoed.
set -euo pipefail
exec 9>/var/lock/pf-deploy; flock 9   # serialise first-boot deploy and CI re-deploys
source /opt/pf/env
export AWS_DEFAULT_REGION=ap-southeast-2
APP=/opt/pf/app
mkdir -p "$APP"
aws s3 sync "s3://$BUCKET/app/" "$APP/" --delete --only-show-errors
cd "$APP"

get_or_create() {  # name -> value, generating a random one on first use
  local name="/$PREFIX/$1"
  if v=$(aws ssm get-parameter --name "$name" --with-decryption --query Parameter.Value --output text 2>/dev/null); then
    printf '%s' "$v"
  else
    v=$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24)
    aws ssm put-parameter --name "$name" --type SecureString --value "$v" --tags Key=project,Value=portfolio Key=repo,Value=hop-airflow-testbed-IaC-aws Key=managed-by,Value=terraform >/dev/null
    printf '%s' "$v"
  fi
}
umask 077
{
  echo "AIRFLOW_ADMIN_PASSWORD=$(get_or_create airflow-admin-password)"
  echo "PG_PASSWORD=$(get_or_create postgres-password)"
  echo "PIPELINE_BUCKET=$BUCKET"
} > .env
docker build -q -t pf-hop-airflow:local .
docker compose up -d --remove-orphans
echo "deploy.sh finished"
