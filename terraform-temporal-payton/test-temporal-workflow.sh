#!/usr/bin/env bash
set -euo pipefail

# Simple Temporal workflow smoke test for this environment.
#
# Usage:
#   ./test-temporal-workflow.sh
#
# Optional env overrides:
#   REGION=us-east-2
#   CLUSTER_NAME=payton-temporal-eks
#   AWS_PROFILE=TemporalSelfHostingAdmin
#   NAMESPACE=temporal
#   TEMPORAL_NAMESPACE=temporal-system
#   TASK_QUEUE=temporal-sys-tq-scanner-taskqueue-0
#   WORKFLOW_TYPE=temporal-sys-tq-scanner-workflow

REGION="${REGION:-us-east-2}"
CLUSTER_NAME="${CLUSTER_NAME:-payton-temporal-eks}"
AWS_PROFILE="${AWS_PROFILE:-TemporalSelfHostingAdmin}"
NAMESPACE="${NAMESPACE:-temporal}"
TEMPORAL_NAMESPACE="${TEMPORAL_NAMESPACE:-temporal-system}"
TASK_QUEUE="${TASK_QUEUE:-temporal-sys-tq-scanner-taskqueue-0}"
WORKFLOW_TYPE="${WORKFLOW_TYPE:-temporal-sys-tq-scanner-workflow}"

echo "==> Updating kubeconfig"
aws eks update-kubeconfig \
  --region "$REGION" \
  --name "$CLUSTER_NAME" \
  --profile "$AWS_PROFILE" >/dev/null

echo "==> Locating admin-tools pod"
ADMIN_POD="$(kubectl -n "$NAMESPACE" get pod -l app.kubernetes.io/component=admintools -o jsonpath='{.items[0].metadata.name}')"

if [[ -z "$ADMIN_POD" ]]; then
  echo "ERROR: Could not find temporal admintools pod in namespace '$NAMESPACE'." >&2
  exit 1
fi

echo "==> Checking Temporal health"
kubectl -n "$NAMESPACE" exec "$ADMIN_POD" -- \
  tctl --address temporal-frontend:7233 cluster health

WORKFLOW_ID="smoke-$(date +%s)"

echo "==> Starting workflow"
START_OUT="$(kubectl -n "$NAMESPACE" exec "$ADMIN_POD" -- \
  tctl --address temporal-frontend:7233 --namespace "$TEMPORAL_NAMESPACE" workflow start \
    --taskqueue "$TASK_QUEUE" \
    --workflow_type "$WORKFLOW_TYPE" \
    --workflow_id "$WORKFLOW_ID" \
    --execution_timeout 300 2>&1)"

echo "$START_OUT"

RUN_ID="$(echo "$START_OUT" | sed -n 's/.*run Id:[[:space:]]*\([^[:space:]]*\).*/\1/p' | tail -n1)"

if [[ -z "$RUN_ID" ]]; then
  echo "ERROR: Could not parse run ID from tctl output." >&2
  exit 1
fi

echo "==> Workflow started"
echo "workflow_id=$WORKFLOW_ID"
echo "run_id=$RUN_ID"

echo "==> Describing workflow"
kubectl -n "$NAMESPACE" exec "$ADMIN_POD" -- \
  tctl --address temporal-frontend:7233 --namespace "$TEMPORAL_NAMESPACE" workflow describe \
    --workflow_id "$WORKFLOW_ID" \
    --run_id "$RUN_ID"

echo "✅ Smoke test complete"
