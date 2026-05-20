#!/usr/bin/env bash
# =============================================================================
# deploy.validation.sh — Validates the Key Vault wrapper module against a
# sandbox subscription. Used by the avm-update-automation workflow.
#
# Required env:
#   AZURE_SUBSCRIPTION_ID  — sandbox subscription
#   SANDBOX_RESOURCE_GROUP — pre-created RG in the sandbox subscription
#   SANDBOX_LOCATION       — region (e.g. eastus2)
# Optional env:
#   DEPLOY                 — "true" to perform a real deployment after what-if
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE="$REPO_ROOT/modules/keyvault.bicep"
PARAMS="$REPO_ROOT/parameters/keyvault.example.bicepparam"

: "${AZURE_SUBSCRIPTION_ID:?must be set}"
: "${SANDBOX_RESOURCE_GROUP:?must be set}"
: "${SANDBOX_LOCATION:?must be set}"

DEPLOY="${DEPLOY:-false}"
RUN_ID="${GITHUB_RUN_ID:-$(date +%s)}"
DEPLOYMENT_NAME="kv-avm-validate-${RUN_ID}"

az account set --subscription "$AZURE_SUBSCRIPTION_ID"

echo "==> bicep build"
az bicep build --file "$TEMPLATE"

echo "==> bicep lint"
az bicep lint --file "$TEMPLATE"

echo "==> what-if against $SANDBOX_RESOURCE_GROUP"
az deployment group what-if \
  --resource-group "$SANDBOX_RESOURCE_GROUP" \
  --template-file "$TEMPLATE" \
  --parameters "$PARAMS" \
  --result-format FullResourcePayloads

if [[ "$DEPLOY" == "true" ]]; then
  echo "==> deploying $DEPLOYMENT_NAME"
  az deployment group create \
    --name "$DEPLOYMENT_NAME" \
    --resource-group "$SANDBOX_RESOURCE_GROUP" \
    --template-file "$TEMPLATE" \
    --parameters "$PARAMS" \
    --output json | tee "$REPO_ROOT/.artifacts/deploy-${RUN_ID}.json" >/dev/null

  echo "==> deployment succeeded: $DEPLOYMENT_NAME"
fi

echo "==> validation complete"
