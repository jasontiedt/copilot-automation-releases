# Copilot Coding Agent Instructions

This file is loaded automatically by the GitHub Copilot coding agent whenever
it works in this repository. It is the **single source of truth** for the
rules, guardrails, and conventions the agent must follow. Treat it like code:
review changes in PRs, keep it concise, prefer bullet points over prose.

> **How to use this file:** each numbered section below has a short purpose
> statement followed by the current rules. To add your own rule, append a
> bullet under the matching section. If a section is empty, the agent has no
> additional constraints in that area — that's fine, leave it blank.

---

## 1. Repository purpose

This repo hosts the **organization-standard Key Vault shared module**, a thin
wrapper around `br/public:avm/res/key-vault/vault`. An automated workflow
(`.github/workflows/avm-update-automation.yml`) detects new AVM releases and
opens an issue assigned to Copilot. The agent's job is to apply the bump
under the rules below.

**Mission statement:** Keep `modules/keyvault.bicep` in sync with the latest
AVM Key Vault module without breaking consumers and without weakening
security posture.

<!-- Add repo-purpose context here (e.g. additional modules this repo will
own, links to architecture docs, escalation contacts). -->

---

## 2. Hard Constraints — *never* violate

These are dictated by the Secure Cloud Foundation (SCF) policy set. Do
**not** lower, remove, or expose them as caller-overridable in a weaker form.
If the upstream AVM module renames or restructures any of these, **map** them
into the new shape — do not drop them.

| Parameter                     | Required value           |
| ----------------------------- | ------------------------ |
| `enableRbacAuthorization`     | `true`                   |
| `enablePurgeProtection`       | `true`                   |
| `softDeleteRetentionInDays`   | `90` (min and max)       |
| `publicNetworkAccess`         | `Disabled` (default)     |
| `networkAcls.defaultAction`   | `Deny` (default)         |

<!-- Add additional non-negotiable security/compliance rules here.
Examples:
- Diagnostic settings must always include category group `audit`.
- Network ACLs must include the corporate egress prefix list.
- Customer-managed keys must be required when SKU is `premium`.
-->

---

## 3. Files Copilot must NOT touch

The agent has read access to the whole repo but **may not modify** these
files. If a change here looks necessary, stop and leave a comment on the
issue requesting human intervention instead of editing.

- `.github/workflows/**` — CI pipelines (only platform team edits)
- `.github/copilot-instructions.md` — this file (must be reviewed like policy)
- `scripts/**` — automation scripts that drive the workflows
- `tests/deploy.validation.sh` — the validation harness CI runs
- `LICENSE`, `CODE_OF_CONDUCT.md`, `SECURITY.md` (if present)

<!-- Add more "off-limits" files or globs here.
Examples:
- `infra/baseline/**` — owned by platform team
- `docs/architecture/*.png` — generated, do not hand-edit
- Anything under `vendor/` or `third_party/`
-->

---

## 4. Files Copilot MAY change

Edits should be confined to the list below. Anything outside this list
requires a clear justification in the PR description.

- `avm.version`
- `modules/keyvault.bicep`
- `parameters/keyvault.example.bicepparam` — only when an example parameter
  was renamed or removed upstream
- `README.md` — parameter / output tables only
- `CHANGELOG.md` — new entry per version

<!-- Add additional editable paths here if the repo grows beyond a single
module (e.g. a new `modules/storage.bicep`). -->

---

## 5. Required content for every updated module

Every change to a Bicep module under `modules/` must keep the following
present and correct. The PR is not ready for review until all boxes are
ticked.

- [ ] `metadata name`, `metadata description`, and `metadata owner` blocks
      at the top of the file.
- [ ] `targetScope = 'resourceGroup'` declared explicitly.
- [ ] Every `param` has an `@description(...)` decorator.
- [ ] Every SCF-locked parameter has the value-range decorators that prevent
      the caller from weakening it (`@allowed`, `@minValue`/`@maxValue`).
- [ ] The AVM module call's `params: { ... }` block reconciles all renames /
      removals / type changes from the diff summary attached to the issue.
- [ ] Outputs `resourceId`, `name`, `uri`, and `resourceGroupName` are still
      exposed and unchanged in name.
- [ ] `// DEPRECATED:` markers added for any parameter that will be removed
      in a future release. Existing markers whose removal condition is met
      by the new AVM version are removed in this PR.

<!-- Add module-specific "must include" rules here.
Examples:
- Every module must accept a `tags object` parameter and forward it.
- Every module must emit an `output principalId string` if it provisions a
  managed identity.
- All modules must register a diagnostic setting when
  `logAnalyticsWorkspaceResourceId` is provided.
-->

---

## 6. Backward compatibility

- Never silently rename or remove a wrapper parameter. If the upstream AVM
  module forces a rename, keep the old parameter name as a **deprecated alias**
  for one release with a `// DEPRECATED:` comment, and forward it to the new
  shape via a coalescing `var`.
- New AVM parameters that are optional should be added to the wrapper **only**
  if they are useful to consumers; otherwise leave them at the AVM default.
- Outputs that already exist must keep their names.

<!-- Add additional compatibility rules here.
Examples:
- Never change the default of a parameter that already shipped.
- Never tighten an `@allowed` list without a major-version bump.
-->

---

## 7. Coding style

- Two-space indentation in Bicep. Trailing commas where syntactically valid.
- Comments use `//` (not block comments) and stay above the line they
  describe.
- Names follow camelCase for parameters and variables, PascalCase for types.
- One module per file. Helpers live in `modules/_shared/` (create on demand).
- Markdown files use ATX-style headings (`#`, `##`, ...) and reference-style
  links where the URL is reused.

<!-- Add style rules specific to your team here.
Examples:
- Prefer `var` over inline expressions when the expression is reused.
- Always quote string defaults even when single-token.
-->

---

## 8. Validation the agent must run locally before opening a PR

The agent has shell access in its sandbox. Before pushing, run:

```bash
az bicep build --file modules/keyvault.bicep
az bicep lint  --file modules/keyvault.bicep
```

Both must exit 0. CI will additionally run sandbox `what-if` + an SCF
compliance scan; address those failures iteratively in the PR.

<!-- Add additional required local checks here.
Examples:
- `bash scripts/diff-avm-versions.sh <old> <new>` and attach the summary.
- `pre-commit run --all-files`.
- A unit-test command if one is added to the repo.
-->

---

## 9. Commit and PR conventions

- **Branch name:** `bot/avm-bump-<new-version>`
- **Commit message format:** Conventional Commits, e.g.
  `chore(avm): bump key-vault to 0.12.0`
- **PR title:** matches the lead commit message.
- **PR body must include:**
  - A link back to the originating issue (`Closes #<issue>`).
  - The diff summary that was attached to the issue.
  - A short "What changed" bullet list (added / removed / changed params).
- Open the PR as **draft** until validation jobs pass green; then mark
  ready-for-review and request the `@platform` team.

<!-- Add additional PR rules here.
Examples:
- PR description must include a "Blast radius" section if any output changed.
- Squash-merge only; no merge commits.
-->

---

## 10. When in doubt — escalate, don't guess

If any of the following are true, **stop editing** and leave a comment on
the issue explaining the situation rather than guessing:

- A Hard Constraint (Section 2) can't be preserved under the new AVM shape.
- The diff summary in the issue body is missing or empty.
- The AVM module appears to have been yanked or replaced by a different module.
- `az bicep build` fails with an error you cannot resolve in three attempts.
- A consumer-breaking output rename appears unavoidable.

<!-- Add additional escalation triggers here.
Examples:
- The change requires editing a file listed in Section 3.
- The required new parameter would expose a secret in plaintext.
-->

---

## 11. Custom rules

Use this section to capture one-off rules that don't fit anywhere above.
Keep entries short, dated, and authored so future maintainers know context.

<!--
Template:
- YYYY-MM-DD (@author): <rule>

Examples:
- 2026-05-21 (@jasontiedt): Until ACR firewall is reconfigured, do not add
  `firewallRules` parameters that reference public IP ranges.
- 2026-06-01 (@platform): When AVM `>= 0.13.0`, switch `sku` from string to
  the new object type and remove the `vaultSku` alias permanently.
-->

(none yet)
