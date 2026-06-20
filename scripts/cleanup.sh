#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-floci-cicd-gitops}"

echo "Cleaning local CI/CD GitOps project resources..."

echo "Deleting kind cluster if it exists..."
if kind get clusters | grep -qx "$CLUSTER_NAME"; then
  kind delete cluster --name "$CLUSTER_NAME"
else
  echo "kind cluster $CLUSTER_NAME not found. Skipping."
fi

echo "Checking Floci containers..."
docker ps --format '{{.Names}}' | grep -E '^floci|floci-ecr-registry' || true

echo "Optional: stop Floci manually if you do not need it:"
echo "  floci stop"

echo "Cleanup complete."
