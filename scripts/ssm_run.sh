#!/bin/bash
# Run a shell command on an instance via SSM and print its stdout. Fails if the command fails.
# Usage: ssm_run.sh <instance-id> <timeout-seconds> <command>
set -euo pipefail
IID="$1"; LIMIT="$2"; CMD="$3"; R=ap-southeast-2
cid=$(aws ssm send-command --region $R --instance-ids "$IID" --document-name AWS-RunShellScript \
      --timeout-seconds 3600 --parameters "commands=[\"$CMD\"]" --query Command.CommandId --output text)
end=$((SECONDS + LIMIT))
while [ $SECONDS -lt $end ]; do
  st=$(aws ssm get-command-invocation --region $R --command-id "$cid" --instance-id "$IID" --query Status --output text 2>/dev/null || echo Pending)
  case "$st" in
    Success) aws ssm get-command-invocation --region $R --command-id "$cid" --instance-id "$IID" --query StandardOutputContent --output text; exit 0;;
    Failed|Cancelled|TimedOut) echo "ssm command $st" >&2
      aws ssm get-command-invocation --region $R --command-id "$cid" --instance-id "$IID" --query StandardErrorContent --output text | tail -25 >&2; exit 1;;
  esac
  sleep 5
done
echo "ssm command still running after ${LIMIT}s" >&2; exit 1
