# Copilot POC — Requirements Traceability

This document maps every requirement from `Copilot-POC.pdf` to the concrete
file, workflow step, or convention that delivers it. It is meant as a quick
audit / hand-off reference: pick a row, follow the link, see the code.

Repository roles:

- **Producer** — `agentic-automation-producer`, the system-of-record for the
  shared Key Vault wrapper. **All seven PDF requirements live here.**
- **Consumer** — `agentic-automation-consumer`, a reference downstream repo
  that proves the published module is consumable end-to-end. Out of scope of
  the PDF; included for completeness.

---

## Slide 3 — High-Level Vision

> "An end-to-end intelligent automation powered by GitHub Copilot that keeps
> the organization's KeyVault Shared Module perpetually up-to-date,
> validated, compliant, and documented — with zero manual intervention."

### #1 — Copilot **watches** for AVM Key Vault releases via the Public Bicep Registry

| What | Where |
|---|---|
| Daily cron trigger | [`avm-update-automation.yml`](.github/workflows/avm-update-automation.yml) — `on.schedule: '0 6 * * *'` |
| Manual override | Same file — `workflow_dispatch.inputs.force_version` |
| Registry call | [`scripts/check-avm-version.sh`](scripts/check-avm-version.sh) — `curl -fsSL "$REGISTRY/v2/$MODULE_PATH/tags/list"` against `mcr.microsoft.com` |
| Pinned baseline | [`avm.version`](avm.version) — single source of truth (currently `0.11.0`) |
| Comparison logic | `check-avm-version.sh` — semver-filtered `sort -V` against the pinned version, emits `current` / `latest` / `has_update` to `$GITHUB_OUTPUT` |

**How "perpetually" is achieved:** the workflow runs daily; concurrency group
`avm-update` prevents overlap; an open PR for the same target version
short-circuits the dispatch step (`gh pr list --state open --search "avm
key-vault $NEW in:title"`).

---

### #2 — It **understands the change diff** between old and new AVM version

| What | Where |
|---|---|
| Diff job | [`avm-update-automation.yml`](.github/workflows/avm-update-automation.yml) — `jobs.diff` |
| Diff engine | [`scripts/diff-avm-versions.sh`](scripts/diff-avm-versions.sh) |
| Method | Compiles `br/public:avm/res/key-vault/vault:<old>` and `<new>` through `az bicep build`, then `jq`-diffs the resulting ARM JSON `parameters` and `outputs` blocks |
| Outputs | `params.diff.json`, `outputs.diff.json`, `summary.md` (Markdown — added/removed/changed lists) |
| Hand-off to Copilot | The summary is written into the issue body so Copilot reads it as task context |
| Persistence | `actions/upload-artifact@v4` uploads `./.artifacts/avm-diff` so the diff is reviewable from the run |

The diff is structural (against the compiled ARM schema), not textual against
Bicep source — that means renames and type changes are detected reliably
even across formatting changes.

---

### #3 — It **intelligently updates** the wrapper module and example parameter file only where applicable

| What | Where |
|---|---|
| Hand-off mechanism | `dispatch-copilot` job in [`avm-update-automation.yml`](.github/workflows/avm-update-automation.yml) — `gh issue create --assignee copilot` |
| Guardrails | [`.github/copilot-instructions.md`](.github/copilot-instructions.md) — checked-in, code-reviewable rules |
| Allowed edit set | Steps 1–6 in `copilot-instructions.md` — exactly four target files: `avm.version`, `modules/keyvault.bicep`, `parameters/keyvault.example.bicepparam` *(only if affected)*, `README.md`, plus a new `CHANGELOG.md` entry |
| Hard constraints | "Hard Constraints (never violate)" table in `copilot-instructions.md` — locked SCF defaults (RBAC, purge protection, soft-delete=90, network ACLs, public network access) |
| Backward-compat policy | "Backward compatibility" section — never silently rename/remove a wrapper parameter; deprecate first |
| Off-limits | "What NOT to change" — `.github/workflows/`, `scripts/`, `tests/deploy.validation.sh`, `copilot-instructions.md` itself |

The intelligence comes from giving the agent a **narrow problem statement
(the diff summary) + an explicit policy file** rather than free-form prompts.
The same instructions can be reviewed by security like any other PR.

---

### #4 — It **validates** the update by deploying into a sandbox environment

| What | Where |
|---|---|
| Validation script | [`tests/deploy.validation.sh`](tests/deploy.validation.sh) |
| Steps | `az bicep build` → `az bicep lint` → `az deployment group what-if` → optional `az deployment group create` when `DEPLOY=true` |
| CI wiring | [`.github/workflows/pr-validate.yml`](.github/workflows/pr-validate.yml) — runs on every PR touching `avm.version`, `modules/**`, `parameters/**`, `tests/**`, `scripts/**`, or itself |
| Auth | OIDC (`azure/login@v2`) with `secrets.AZURE_CLIENT_ID` / `AZURE_TENANT_ID` / `AZURE_SUBSCRIPTION_ID` — no long-lived credentials |
| Sandbox target | Repo variables `SANDBOX_RESOURCE_GROUP` / `SANDBOX_LOCATION` |
| Evidence | Validation log uploaded as the `validation-log` artifact; pass/fail comment posted on the PR by `actions/github-script@v7` |
| Real-deploy escape hatch | `workflow_dispatch.inputs.deploy: true` flips the script's `DEPLOY` env var |

Copilot's bump PRs go through this gate automatically; humans can't bypass it
without disabling the workflow.

---

### #5 — It **enforces governance** via SCF policy compliance checks

| What | Where | Status |
|---|---|---|
| Policy intent (locked defaults in code) | [`modules/keyvault.bicep`](modules/keyvault.bicep) — `enableRbacAuthorization`, `enablePurgeProtection`, `softDeleteRetentionInDays` (constrained to `@minValue(90) @maxValue(90)`), `publicNetworkAccess: 'Disabled'`, `networkAcls.defaultAction: 'Deny'` | ✅ |
| Agent-level enforcement | [`.github/copilot-instructions.md`](.github/copilot-instructions.md) — "Hard Constraints (never violate)" + "If the upstream AVM module renames or restructures any of these, **map** them into the new shape" | ✅ |
| Runtime policy scan (`az policy state list` against the sandbox RG) | Not yet implemented | ❌ Gap |

**Implementation plan for the gap:** add a `compliance` job to
`pr-validate.yml` that runs after the optional sandbox deploy:

```yaml
- name: SCF policy state
  run: |
    NONCOMPLIANT=$(az policy state list \
      --resource-group "$SANDBOX_RESOURCE_GROUP" \
      --filter "ComplianceState eq 'NonCompliant'" \
      --query "length([?contains(policyDefinitionAction,'deny') || contains(policyDefinitionAction,'audit')])" -o tsv)
    [[ "$NONCOMPLIANT" -gt 0 ]] && { echo "::error::$NONCOMPLIANT non-compliant policy states"; exit 1; }
```

Two layers of defence — schema-level (the wrapper rejects bad input at
compile time) and runtime (the policy scan catches drift). The first layer
is in place; the second is the only outstanding PDF requirement.

---

### #6 — It **self-documents** any parameter-level changes in the README

| What | Where |
|---|---|
| README parameter table | [`README.md`](README.md) — "## Parameters" and "## Outputs" sections |
| Update obligation | Step 6 of [`.github/copilot-instructions.md`](.github/copilot-instructions.md) — "Regenerate the parameter and output tables in `README.md`" |
| Changelog obligation | Step 7 — "Add a `CHANGELOG.md` entry under a new `## <new-version>` heading summarising the change" |
| Source of truth | The diff summary written into the Copilot issue (#2 above) is what the agent reads to know which rows to add/remove/change |

The PR diff itself becomes the audit trail: README + CHANGELOG land in the
same commit as the wrapper change, never lag behind.

---

### #7 — It **opens a PR, summarizes the changes, and notifies the team**

| What | Where |
|---|---|
| Issue creation | `dispatch-copilot` job in [`avm-update-automation.yml`](.github/workflows/avm-update-automation.yml) — `gh issue create --title "chore(avm): bump key-vault to <new>" --assignee copilot` |
| Issue body | Diff summary inlined verbatim from `summary.md`, plus the constraint reminders |
| PR creation | The Copilot Coding Agent itself, on branch `bot/avm-bump-<new-version>` (per `copilot-instructions.md` "PR Conventions") |
| PR title | `chore(avm): bump key-vault to <new-version>` |
| PR draft state | Per instructions: "Always open as **draft** until validation jobs pass" |
| Teams notification — issue opened | "Notify Teams" step in [`avm-update-automation.yml`](.github/workflows/avm-update-automation.yml) — Adaptive Card with link to issue |
| Teams notification — PR validated | "Notify Teams" step in [`pr-validate.yml`](.github/workflows/pr-validate.yml) — Adaptive Card with PR + run-log links, pass/fail emoji |
| Teams notification — module published | "Notify Teams" step in [`publish.yml`](.github/workflows/publish.yml) — Adaptive Card with release + commit links |
| Webhook secret | `secrets.TEAMS_WEBHOOK_URL` — gated `if: env.TEAMS_WEBHOOK_URL != ''` so workflows degrade silently when unset |
| Card format | Adaptive Card 1.4 wrapped in `attachments[]` — compatible with the modern Teams **Workflows** "incoming webhook" trigger |

---

## Slide 4 — Tech Stack Coverage

| PDF row | Tool / technology | Where in this implementation |
|---|---|---|
| IaC Language | Azure Bicep | [`modules/keyvault.bicep`](modules/keyvault.bicep), [`parameters/keyvault.example.bicepparam`](parameters/keyvault.example.bicepparam) |
| Module Standard | Azure Verified Modules (AVM) | `modules/keyvault.bicep` line referencing `br/public:avm/res/key-vault/vault:0.11.0` |
| Automation Engine | GitHub Actions | [`.github/workflows/`](.github/workflows/) — `avm-update-automation`, `pr-validate`, `publish`, `consumer-deploy`, `consumer-module-update-check` |
| Copilot Integration | GitHub Copilot Coding Agent | `gh issue create --assignee copilot` in `avm-update-automation.yml`; behavior governed by [`.github/copilot-instructions.md`](.github/copilot-instructions.md) |
| Azure Deployment | Azure CLI / `az deployment` | `tests/deploy.validation.sh`, `pr-validate.yml`, `consumer-deploy.yml` |
| Compliance Check | Azure Policy / `az policy state` | **Not yet wired.** Plan documented in #5 above |
| Notification | Microsoft Teams Webhook / GitHub Mentions | GitHub: `--assignee copilot`, PR comments via `actions/github-script@v7`. Teams: Adaptive Cards in three workflows |
| Documentation | Auto-generated Markdown README update | `README.md` parameter/output tables, regenerated by Copilot per step 6 of `copilot-instructions.md`; `CHANGELOG.md` per step 7 |
| Version Detection | Bicep Public Registry API + `br/public` feed | `scripts/check-avm-version.sh` — `mcr.microsoft.com/v2/bicep/avm/res/key-vault/vault/tags/list`; the wrapper itself uses the `br/public:` reference |

---

## Slide 5 — Repo Structure Coverage

PDF-prescribed layout, mapped to the actual repo:

```
keyvault-shared-module/                          ← agentic-automation-producer
├── modules/keyvault.bicep                       ✅ AVM wrapper
├── parameters/keyvault.example.bicepparam       ✅ Example parameter file
├── tests/deploy.validation.sh                   ✅ Validation script
├── .github/
│   └── workflows/
│       └── avm-update-automation.yml            ✅ Main Copilot automation
└── README.md                                    ✅ Auto-updated documentation
```

**Additions beyond the PDF (intentional):**

| File | Why it was added |
|---|---|
| [`avm.version`](avm.version) | Single source of truth; lets every script and workflow agree on "current" without parsing Bicep |
| [`scripts/check-avm-version.sh`](scripts/check-avm-version.sh) | Encapsulates the registry query so it's testable and reusable |
| [`scripts/diff-avm-versions.sh`](scripts/diff-avm-versions.sh) | Diff engine called by the workflow's `diff` job |
| [`CHANGELOG.md`](CHANGELOG.md) | Required by `copilot-instructions.md` step 7 |
| [`.github/copilot-instructions.md`](.github/copilot-instructions.md) | Guardrails for the coding agent |
| [`.github/workflows/pr-validate.yml`](.github/workflows/pr-validate.yml) | Gates Copilot's bump PRs through `tests/deploy.validation.sh` |
| [`.github/workflows/publish.yml`](.github/workflows/publish.yml) | Publishes the validated wrapper to ACR on tag push (not in the PDF, but the consumers need a registry-published artifact) |
| [`.github/workflows/consumer-deploy.yml`](.github/workflows/consumer-deploy.yml) | Reusable workflow for downstream consumer repos (scale lever) |
| [`.github/workflows/consumer-module-update-check.yml`](.github/workflows/consumer-module-update-check.yml) | Reusable Renovate fallback for consumers |

Nothing from the PDF layout is **missing**; the additions extend the spec to
cover publishing and downstream consumption that the PDF didn't address.

---

## Summary scoreboard

| PDF requirement | Status |
|---|---|
| 1. Watch AVM releases | ✅ Done |
| 2. Understand the diff | ✅ Done |
| 3. Intelligently update wrapper + example | ✅ Done |
| 4. Validate via sandbox deployment | ✅ Done (`pr-validate.yml`) |
| 5. SCF policy compliance | ⚠️ Code-level enforcement done; runtime `az policy state` scan still to add |
| 6. Self-document changes | ✅ Done |
| 7. Open PR + summarize + notify | ✅ Done (Copilot PR + Teams webhook on three triggers) |

One outstanding item: the runtime SCF policy scan (#5). Plan and snippet are
in place; estimate is a single 10-line job appended to `pr-validate.yml`.
