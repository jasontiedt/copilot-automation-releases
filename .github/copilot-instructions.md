# Copilot Coding Agent Instructions

This repo hosts the **organization-standard Key Vault shared module**, a thin
wrapper around `br/public:avm/res/key-vault/vault`. An automated workflow
(`avm-update-automation.yml`) detects new AVM releases and assigns a bump task
to you. Follow the rules below for **every** change.

## Mission

Keep `modules/keyvault.bicep` in sync with the latest AVM Key Vault module
without breaking consumers and without weakening security posture.

## Hard Constraints (never violate)

The following defaults are dictated by the Secure Cloud Foundation (SCF)
policy set. Do **not** lower, remove, or expose them as caller-overridable in a
weaker form:

| Parameter                     | Required value           |
| ----------------------------- | ------------------------ |
| `enableRbacAuthorization`     | `true`                   |
| `enablePurgeProtection`       | `true`                   |
| `softDeleteRetentionInDays`   | `90` (min and max)       |
| `publicNetworkAccess`         | `Disabled` (default)     |
| `networkAcls.defaultAction`   | `Deny` (default)         |

If the upstream AVM module renames or restructures any of these, **map** them
into the new shape — do not drop them.

## Backward compatibility

- Never silently rename or remove a wrapper parameter. If the upstream AVM
  module forces a rename, keep the old parameter name as a deprecated alias for
  one release with a `// DEPRECATED:` comment, and forward it to the new shape.
- New AVM parameters that are optional should be added to the wrapper **only**
  if they are useful to consumers; otherwise leave them at the AVM default.
- Outputs that already exist must keep their names.

## What to change

For each AVM bump issue:

1. Read `avm.version` and the diff in the issue body.
2. Update `avm.version` to the new version.
3. Update the `br/public:avm/res/key-vault/vault:<version>` reference in
   `modules/keyvault.bicep`.
4. Reconcile the `params: { ... }` block of the AVM module call against the
   diff (handle renames, removals, type changes).
5. Update `parameters/keyvault.example.bicepparam` **only** if it references a
   parameter that was renamed/removed.
6. Regenerate the parameter and output tables in `README.md`.
7. Add a `CHANGELOG.md` entry under a new `## <new-version>` heading
   summarising the change (added / removed / changed parameters and outputs).

## What NOT to change

- Workflow files under `.github/workflows/`.
- Scripts under `scripts/`.
- This file.
- The `tests/deploy.validation.sh` script.
- Any file outside the four targets in step 3–6 above unless strictly required.

## Validation

Before opening the PR, ensure:

- `az bicep build --file modules/keyvault.bicep` succeeds.
- `az bicep lint --file modules/keyvault.bicep` reports no errors.
- Existing example parameters still satisfy the wrapper's required parameters.

The CI pipeline will additionally run a sandbox what-if and SCF policy
compliance scan. Address any failures iteratively.

## PR Conventions

- Branch name: `bot/avm-bump-<new-version>`
- PR title: `chore(avm): bump key-vault to <new-version>`
- PR body: include the diff summary and link the originating issue.
- Always open as **draft** until validation jobs pass.
