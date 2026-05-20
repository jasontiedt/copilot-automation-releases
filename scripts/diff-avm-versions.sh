#!/usr/bin/env bash
# =============================================================================
# diff-avm-versions.sh
# Produces a human + machine readable diff between two AVM key-vault versions
# by pulling each module from the public registry, restoring it with the Bicep
# CLI, and diffing the resulting ARM JSON parameter/output schemas.
#
# Usage:
#   ./diff-avm-versions.sh <old-version> <new-version> [output-dir]
#
# Outputs in <output-dir> (default: ./.artifacts/avm-diff):
#   old.json, new.json          — compiled ARM templates
#   params.diff.json            — added/removed/changed parameters
#   outputs.diff.json           — added/removed/changed outputs
#   summary.md                  — markdown summary suitable for PR/Issue body
# =============================================================================
set -euo pipefail

OLD="${1:?old version required}"
NEW="${2:?new version required}"
OUT="${3:-./.artifacts/avm-diff}"
MODULE="br/public:avm/res/key-vault/vault"

mkdir -p "$OUT"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

build_one() {
  local version="$1"
  cat > "$WORK/probe-${version}.bicep" <<EOF
module m '${MODULE}:${version}' = {
  name: 'probe'
  params: {
    name: 'probe'
    location: 'eastus2'
  }
}
EOF
  az bicep build --file "$WORK/probe-${version}.bicep" --outfile "$WORK/probe-${version}.json" >/dev/null

  # The compiled ARM contains the nested module's parameters/outputs; extract them.
  jq '{
        parameters: (.. | objects | select(.type? == "Microsoft.Resources/deployments") | .properties.template.parameters // {}),
        outputs:    (.. | objects | select(.type? == "Microsoft.Resources/deployments") | .properties.template.outputs    // {})
      } | first(.[])' "$WORK/probe-${version}.json" 2>/dev/null \
    || jq '{ parameters: .parameters, outputs: .outputs }' "$WORK/probe-${version}.json"
}

echo "==> compiling old version $OLD"
build_one "$OLD" > "$OUT/old.json"
echo "==> compiling new version $NEW"
build_one "$NEW" > "$OUT/new.json"

diff_section() {
  local section="$1"
  jq -n --slurpfile a "$OUT/old.json" --slurpfile b "$OUT/new.json" --arg s "$section" '
    ($a[0][$s] // {}) as $old
    | ($b[0][$s] // {}) as $new
    | {
        added:   ($new | to_entries | map(select(.key as $k | ($old | has($k)) | not)) | map(.key)),
        removed: ($old | to_entries | map(select(.key as $k | ($new | has($k)) | not)) | map(.key)),
        changed: (
          $old
          | to_entries
          | map(select(.key as $k | ($new | has($k))))
          | map({ name: .key, old: .value, new: ($new[.key]) })
          | map(select(.old != .new))
        )
      }'
}

diff_section parameters > "$OUT/params.diff.json"
diff_section outputs    > "$OUT/outputs.diff.json"

# -- markdown summary ---------------------------------------------------------
{
  echo "# AVM Key Vault: \`$OLD\` → \`$NEW\`"
  echo
  for section in parameters outputs; do
    case "$section" in
      parameters) file="$OUT/params.diff.json" ;;
      outputs)    file="$OUT/outputs.diff.json" ;;
    esac
    echo "## ${section^}"
    added="$(jq -r '.added | length' "$file")"
    removed="$(jq -r '.removed | length' "$file")"
    changed="$(jq -r '.changed | length' "$file")"
    echo "- Added: $added"
    echo "- Removed: $removed"
    echo "- Changed: $changed"
    if [[ "$added" -gt 0 ]];   then echo; echo "**Added:**";   jq -r '.added[]   | "- `\(.)`"' "$file"; fi
    if [[ "$removed" -gt 0 ]]; then echo; echo "**Removed:**"; jq -r '.removed[] | "- `\(.)`"' "$file"; fi
    if [[ "$changed" -gt 0 ]]; then
      echo
      echo "**Changed:**"
      jq -r '.changed[] | "- `\(.name)`"' "$file"
    fi
    echo
  done
} > "$OUT/summary.md"

echo "==> diff written to $OUT"
