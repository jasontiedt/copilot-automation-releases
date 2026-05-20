#!/usr/bin/env bash
# =============================================================================
# check-avm-version.sh
# Compares the AVM key-vault version pinned in `avm.version` against the latest
# tag published to the Microsoft public Bicep registry (mcr.microsoft.com).
#
# Outputs (when run under GitHub Actions, also written to $GITHUB_OUTPUT):
#   current=<x.y.z>
#   latest=<x.y.z>
#   has_update=<true|false>
# =============================================================================
set -euo pipefail

MODULE_PATH="${MODULE_PATH:-bicep/avm/res/key-vault/vault}"
REGISTRY="${REGISTRY:-https://mcr.microsoft.com}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_FILE="$REPO_ROOT/avm.version"

if [[ ! -f "$VERSION_FILE" ]]; then
  echo "::error::avm.version not found at $VERSION_FILE"
  exit 1
fi

current="$(tr -d '[:space:]' < "$VERSION_FILE")"

echo "Fetching tags for $MODULE_PATH from $REGISTRY ..."
tags_json="$(curl -fsSL "$REGISTRY/v2/$MODULE_PATH/tags/list")"

# semver sort, ignore non-semver tags (e.g. 'latest')
latest="$(
  echo "$tags_json" \
    | jq -r '.tags[]' \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
    | sort -V \
    | tail -n 1
)"

if [[ -z "$latest" ]]; then
  echo "::error::Could not determine latest semver tag"
  exit 1
fi

has_update="false"
if [[ "$current" != "$latest" ]]; then
  # only flag when latest > current
  newest="$(printf '%s\n%s\n' "$current" "$latest" | sort -V | tail -n 1)"
  if [[ "$newest" == "$latest" ]]; then
    has_update="true"
  fi
fi

echo "current=$current"
echo "latest=$latest"
echo "has_update=$has_update"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "current=$current"
    echo "latest=$latest"
    echo "has_update=$has_update"
  } >> "$GITHUB_OUTPUT"
fi
