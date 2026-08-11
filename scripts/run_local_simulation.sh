#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TF_PLAN_BINARY="tfplan"
TF_PLAN_JSON="tfplan.json"
SUBNET_ID="${1:-}"
BACKEND_KEY="${2:-local-simulation.tfstate}"
ENVIRONMENT_NAME="${3:-dev}"

if [[ -z "$SUBNET_ID" ]]; then
  echo "Usage: $0 <subnet_id> [backend-key] [environment-name]"
  exit 1
fi

if [[ ! -x "./.venv/Scripts/python.exe" ]]; then
  echo "ERROR: Virtual environment not found. Activate or create .venv first."
  exit 1
fi

PYTHON="./.venv/Scripts/python.exe"
TERRAFORM="terraform"

echo "=== Terraform init ==="
$TERRAFORM init -backend-config="key=$BACKEND_KEY"

echo "=== Terraform plan ==="
$TERRAFORM plan -var="environment_name=$ENVIRONMENT_NAME" -out="$TF_PLAN_BINARY"

echo "=== Terraform show JSON ==="
$TERRAFORM show -json "$TF_PLAN_BINARY" > "$TF_PLAN_JSON"

echo "=== Validate subnet IPs ==="
if ! $PYTHON python/scripts/validate_subnet_ips.py "$TF_PLAN_JSON" "$SUBNET_ID"; then
  echo "Subnet IP validation failed as expected. Continuing to failure simulation."
else
  echo "ERROR: Subnet IP validation unexpectedly passed."
  exit 1
fi

echo "=== Terraform apply (expected partial failure due to IP exhaustion) ==="
set +e
$TERRAFORM apply -auto-approve "$TF_PLAN_BINARY"
APPLY_EXIT_CODE=$?
set -e

if [[ $APPLY_EXIT_CODE -eq 0 ]]; then
  echo "WARNING: Terraform apply succeeded unexpectedly. The failure simulation may not be valid."
else
  echo "Terraform apply failed as expected with exit code $APPLY_EXIT_CODE."
fi

echo "=== Terraform destroy ==="
$TERRAFORM destroy -var="environment_name=$ENVIRONMENT_NAME" -auto-approve || true

echo "=== Checking for orphaned EBS volumes ==="
ORPHANED_OUTPUT=$($PYTHON - <<PY
import boto3
client = boto3.client('ec2')
volumes = client.describe_volumes(Filters=[
    {'Name': 'status', 'Values': ['available']},
    {'Name': 'tag:Environment', 'Values': ['$ENVIRONMENT_NAME']},
    {'Name': 'tag:Ephemeral', 'Values': ['true']},
])['Volumes']
print(len(volumes))
for v in volumes:
    print(v['VolumeId'], v['Size'])
PY
)
ORPHANED_VOLUMES=$(printf '%s\n' "$ORPHANED_OUTPUT" | head -n1)

if [[ "$ORPHANED_VOLUMES" -eq 0 ]]; then
  echo "No orphaned volumes found. Nothing to clean."
  exit 1
fi

echo "=== Running local janitor_engine cleanup ==="
set +e
$PYTHON - <<PY
import json
from python.scripts.janitor_engine import lambda_handler

result = lambda_handler({'environment_name': '$ENVIRONMENT_NAME'})
print(json.dumps(result, indent=2))

import boto3
client = boto3.client('ec2')
volumes = client.describe_volumes(Filters=[
    {'Name': 'status', 'Values': ['available']},
    {'Name': 'tag:Environment', 'Values': ['$ENVIRONMENT_NAME']},
    {'Name': 'tag:Ephemeral', 'Values': ['true']},
])['Volumes']
print('remaining_volumes=', len(volumes))
if volumes:
    for v in volumes:
        print(v['VolumeId'])
    raise SystemExit(1)
PY
CLEANUP_EXIT_CODE=$?
set -e

if [[ $CLEANUP_EXIT_CODE -ne 0 ]]; then
  echo "Janitor cleanup failed to remove orphaned volumes."
  exit 1
fi

echo "=== Local simulation complete: orphaned volumes cleaned. ==="
exit 0
