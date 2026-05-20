# Copilot POC — Demo Walkthrough

A guided, paste-ready walkthrough you can follow during a live demo. Each
step says **what to show**, **where it lives**, and **what to say** — in
that order. Times assume one presenter, one screen.

> Total run-time: ~25 minutes. Sections marked *(optional)* are deep-dives
> you can skip if time-boxed.

---

## Setup before the room arrives

| Need | How |
|---|---|
| Both repos cloned side-by-side | `c:/GitRepos/agentic-automation-producer` and `c:/GitRepos/agentic-automation-consumer` |
| VS Code window per repo | One on the left, one on the right (split monitor or two windows) |
| Terminal open in producer | For the optional live-execution moments in steps 4 and 5 |
| The PDF visible | Slide deck open on a second screen if possible — you'll cross-reference |
| Internet *(optional)* | Only needed if you live-call the public registry in step 4 |
| Azure CLI + Bicep *(optional)* | Only if you do the live diff in step 5 |

> **Demo state:** the wrapper is intentionally pinned to AVM `0.10.0` (one
> minor behind current) and seeded with three deprecated parameters
> (`vaultSku`, `enableSoftDelete`, `accessPolicies`). This guarantees the
> manual workflow run produces a real reconciliation task — see Step 5b.

> **Required repo secret:** `COPILOT_ASSIGN_TOKEN` — a fine-grained PAT
> with `Issues: read & write` on this repo. Assigning the Copilot coding
> agent goes through the GraphQL `replaceActorsForAssignable` mutation,
> which rejects the default `GITHUB_TOKEN` (it's an installation token).
> Without this secret the workflow falls back to `GITHUB_TOKEN` and the
> assignment step will fail.

---

## Step 1 — Frame the problem (1 min)

**Show:** the PDF, slide 3 ("High Level Idea").

**Say:**
> Every time Microsoft ships a new AVM Key Vault version, somebody on the
> platform team has to bump our wrapper, run validation, check policy,
> update docs, and open the PR. That's a recurring tax on a small team.
> The PoC's goal is to make that loop run itself, end-to-end, with Copilot
> doing the editing under fixed guardrails.

**Then:** flip to the producer repo in VS Code.

---

## Step 2 — Tour the producer repo (2 min)

**Show:** the file tree of `agentic-automation-producer`.

```
agentic-automation-producer/
├── avm.version                              ← single source of truth
├── modules/keyvault.bicep                   ← AVM wrapper, SCF defaults locked
├── parameters/keyvault.example.bicepparam   ← example used by validation
├── tests/deploy.validation.sh               ← bicep build/lint + what-if
├── scripts/
│   ├── check-avm-version.sh                 ← detects new AVM releases
│   └── diff-avm-versions.sh                 ← compiles old/new + emits diff
├── .github/
│   ├── copilot-instructions.md              ← guardrails for the agent
│   └── workflows/
│       ├── avm-update-automation.yml        ← detect → diff → open issue
│       ├── pr-validate.yml                  ← gates Copilot's bump PRs
│       ├── publish.yml                      ← v*.*.* tag → ACR push
│       ├── consumer-deploy.yml              ← reusable for consumers
│       └── consumer-module-update-check.yml ← reusable Renovate fallback
├── CHANGELOG.md
├── DESIGN.md                                ← architecture + scaling
├── POC-COVERAGE.md                          ← PDF requirement traceability
└── README.md
```

**Say:**
> The PDF prescribed five files. Everything beyond that — the scripts, the
> instructions file, the publish/consumer-deploy workflows — is a deliberate
> addition documented in `POC-COVERAGE.md`. Nothing the PDF asked for is
> missing.

---

## Step 3 — The single source of truth (30 sec)

**Open:** [`avm.version`](avm.version).

**Say:**
> One file, one line, one semver string. Every workflow and every script
> reads this. We never grep Bicep source to figure out "current version" —
> that's how scripts diverge from reality.

```
$ cat avm.version
0.11.0
```

---

## Step 4 — PDF #1: Watch the registry (3 min)

**Open:** [`scripts/check-avm-version.sh`](scripts/check-avm-version.sh).

**Highlight these three things:**

1. The endpoint — `mcr.microsoft.com/v2/bicep/avm/res/key-vault/vault/tags/list`.
2. The semver filter — `grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1`.
3. The `$GITHUB_OUTPUT` writes — `current`, `latest`, `has_update`.

**Open:** [`.github/workflows/avm-update-automation.yml`](.github/workflows/avm-update-automation.yml).

Point at:

```yaml
on:
  schedule:
    - cron: '0 6 * * *'
  workflow_dispatch:
    inputs:
      force_version:
```

**Say:**
> Daily at 06:00 UTC, plus a manual override if we ever need to force a
> specific version. The whole "watching" is one cron line and one curl.

### *(optional)* Live registry call

If you have internet, run from the terminal:

```bash
cd c:/GitRepos/agentic-automation-producer
bash scripts/check-avm-version.sh
```

Expected output:

```
current=0.10.0
latest=0.11.0
has_update=true
```

> Because the wrapper is intentionally pinned one minor behind for this
> demo, `has_update=true` and the rest of the workflow kicks in.

---

## Step 5 — PDF #2: Understand the diff (3 min)

**Open:** [`scripts/diff-avm-versions.sh`](scripts/diff-avm-versions.sh).

**Highlight:**

- The `build_one()` function — compiles `br/public:avm/res/key-vault/vault:<version>`
  through `az bicep build` for **both** versions.
- The `diff_section()` function — `jq`-diffs the resulting ARM JSON
  parameter and output blocks (added / removed / changed).
- The Markdown summary at the end — that's what becomes the issue body.

**Say:**
> We diff the **compiled ARM schema**, not the Bicep source. That means
> renames, type changes, and structural reshapes all surface — formatting
> changes don't trigger noise.

### *(optional)* Live diff

```bash
cd c:/GitRepos/agentic-automation-producer
bash scripts/diff-avm-versions.sh 0.10.0 0.11.0 ./.artifacts/avm-diff
cat .artifacts/avm-diff/summary.md
```

You'll see something like:

```markdown
# AVM Key Vault: `0.10.0` → `0.11.0`

## Parameters
- Added:   2
- Removed: 0
- Changed: 1

**Added:**
- `secretsExportConfiguration`
- `enableTelemetry`
...
```

---

## Step 5b — The planted drift (2 min)

For this demo the wrapper has been deliberately seeded with three pieces of
**stale code** that the agent is expected to clean up during the bump. This
is what turns "version-pin update" into a real reconciliation task.

**Open:** [`modules/keyvault.bicep`](modules/keyvault.bicep) and point at
each of these:

| # | Location | What's stale | What Copilot must do |
|---|---|---|---|
| 1 | `param vaultSku` (deprecated alias for `skuName`) | Old AVM accepted both names; current AVM only accepts `sku`. Wrapper still exposes both via the `effectiveSku` coalescing var. | Remove the `vaultSku` param **and** the `effectiveSku` var; pass `skuName` directly. Note the removal in `CHANGELOG.md`. |
| 2 | `param enableSoftDelete bool = true` | AVM 0.9+ enforces soft-delete unconditionally — this knob is a no-op. | Remove the param. Note the removal in `CHANGELOG.md`. |
| 3 | `param accessPolicies array = []` (with `@maxLength(0)`) | RBAC-only auth is a Hard Constraint; this param can never be used. | Remove the param. Note the removal in `CHANGELOG.md`. |

**Say:**
> All three are tagged with `// DEPRECATED:` comments so the agent can find
> them grep-style. Step 5 of `.github/copilot-instructions.md` explicitly
> tells Copilot to remove deprecated wrapper params whose stated removal
> condition is met by the new AVM version. After the bump, the wrapper
> should be ~25 lines shorter and the README parameters table should drop
> three rows.

> Validation is what enforces this: `pr-validate.yml` runs `az bicep build`
> and `az bicep lint` against the post-bump wrapper. If Copilot leaves a
> dangling `effectiveSku` reference or forgets to update `README.md`,
> reviewers see a ❌ on the PR before they even open the diff.

---

## Step 6 — PDF #3: The guardrails Copilot follows (3 min)

**Open:** [`.github/copilot-instructions.md`](.github/copilot-instructions.md).

This is the most important file in the demo. Walk through these sections in order:

### 6a. Hard Constraints

```
| Parameter                   | Required value     |
| ---------------------------- | ------------------ |
| enableRbacAuthorization      | true               |
| enablePurgeProtection        | true               |
| softDeleteRetentionInDays    | 90 (min and max)   |
| publicNetworkAccess          | Disabled (default) |
| networkAcls.defaultAction    | Deny (default)     |
```

**Say:**
> These are the SCF defaults. If the upstream AVM module renames
> `softDeleteRetentionInDays` to `softDelete.retentionDays`, Copilot's job
> is to **map** the value into the new shape — never to drop or weaken it.

### 6b. Backward compatibility

> If an AVM rename forces a wrapper rename, Copilot keeps the old parameter
> name as a **deprecated alias** with a `// DEPRECATED:` comment for one
> release before removing it. Consumers never break silently.
>
> The flip side is **step 5** of "What to change": when a deprecated alias's
> removal condition is met by the new AVM version, the agent must actually
> remove it (and any coalescing `var`) — that's exactly what triggers the
> reconciliation work shown in Step 5b above.

### 6c. What to change vs. what NOT to change

> Edits are limited to four files. Workflows, scripts, the validation
> harness, and this instructions file itself are off-limits to the agent.
> The agent can't lower its own bar.

### 6d. PR conventions

> Branch `bot/avm-bump-<new-version>`, title `chore(avm): bump key-vault to
> <new-version>`, opened **as draft** until validation passes.

**Say:**
> The intelligence isn't a clever prompt — it's a narrow problem statement
> (the diff summary) plus an explicit, code-reviewable rules file.

---

## Step 7 — The auto-opened Copilot issue (2 min)

**Open:** [`.github/workflows/avm-update-automation.yml`](.github/workflows/avm-update-automation.yml),
scroll to the `dispatch-copilot` job.

**Highlight the `gh issue create` step.**

```yaml
- name: Create issue and assign Copilot
  id: issue
  if: steps.existing.outputs.count == '0'
  run: |
    DIFF_BODY="$(cat ./.artifacts/avm-diff/summary.md)"
    BODY=$(cat <<EOF
    ## Task
    Bump the AVM Key Vault module from \`$OLD\` to \`$NEW\`.
    ...
    ### Constraints (do NOT violate)
    See \`.github/copilot-instructions.md\`.
    ...
    ### Diff summary
    $DIFF_BODY
    EOF
    )
    URL=$(gh issue create \
      --title "chore(avm): bump key-vault to $NEW" \
      --body "$BODY" \
      --assignee "copilot")
```

**Say:**
> Three things go into the issue body: the task description, a pointer to
> the rules file, and the diff summary. That's the entire prompt the agent
> sees. Concurrency-guard step right above prevents duplicate issues.

---

## Step 8 — PDF #4: Sandbox validation (3 min)

**Open:** [`tests/deploy.validation.sh`](tests/deploy.validation.sh).

```bash
echo "==> bicep build"
az bicep build --file "$TEMPLATE"

echo "==> bicep lint"
az bicep lint --file "$TEMPLATE"

echo "==> what-if against $SANDBOX_RESOURCE_GROUP"
az deployment group what-if \
  --resource-group "$SANDBOX_RESOURCE_GROUP" \
  --template-file "$TEMPLATE" \
  --parameters "$PARAMS"
```

**Open:** [`.github/workflows/pr-validate.yml`](.github/workflows/pr-validate.yml).

**Highlight:**

```yaml
on:
  pull_request:
    paths:
      - 'avm.version'
      - 'modules/**'
      - 'parameters/**'
      - 'tests/deploy.validation.sh'
      - 'scripts/**'
```

**Say:**
> Every PR that touches the wrapper goes through the same script Copilot
> would run locally. Auth is OIDC — no long-lived secrets. The job posts a
> ✅/❌ comment back on the PR and uploads the full log as an artifact.

---

## Step 9 — PDF #5: Compliance enforcement (1 min)

**Two layers of defence:**

### Layer 1 (in place) — schema-level locks

**Open:** [`modules/keyvault.bicep`](modules/keyvault.bicep), point at:

```bicep
@minValue(90)
@maxValue(90)
param softDeleteRetentionInDays int = 90
```

> A consumer literally cannot pass anything other than 90. The Bicep
> compiler rejects it before any cloud call happens.

### Layer 2 (planned) — runtime policy scan

> Outstanding gap. The plan, documented in `POC-COVERAGE.md` §#5, is a
> 10-line job appended to `pr-validate.yml`:

```bash
az policy state list \
  --resource-group "$SANDBOX_RESOURCE_GROUP" \
  --filter "ComplianceState eq 'NonCompliant'" \
  --query "[?contains(policyDefinitionAction,'deny')]"
```

> Job fails on any non-compliant result. That's the only PDF requirement
> still open.

---

## Step 10 — PDF #6: Self-documenting (1 min)

**Open:** [`README.md`](README.md), scroll to "## Parameters" and "## Outputs".

**Open:** [`CHANGELOG.md`](CHANGELOG.md).

**Say:**
> Step 6 of the agent instructions makes Copilot regenerate these tables on
> every bump. Step 7 makes it write a CHANGELOG entry under the new
> version. The PR diff is the audit trail — docs land in the same commit as
> the wrapper change, never lag behind.

---

## Step 11 — PDF #7: PR + Teams notifications (2 min)

The PR itself is opened by the Copilot agent. The team gets pinged in Teams
at three moments. Open these three workflows and point at the `Notify Teams`
step in each:

| Trigger | File | Card content |
|---|---|---|
| New AVM version detected, issue opened | [`avm-update-automation.yml`](.github/workflows/avm-update-automation.yml) | "AVM Key Vault `0.x` → `0.y` available" + link to issue |
| PR validated (pass or fail) | [`pr-validate.yml`](.github/workflows/pr-validate.yml) | ✅/❌ + PR link + run-log link |
| Module published to ACR | [`publish.yml`](.github/workflows/publish.yml) | "`keyvault-shared:0.y` published" + release + commit links |

**Say:**
> All three are gated on `secrets.TEAMS_WEBHOOK_URL`. If the secret isn't
> set, the workflows skip the step silently — safe to merge before the
> webhook exists.

> Card format is **Adaptive Card 1.4** wrapped in `attachments[]` — that's
> the format the modern Teams Workflows incoming-webhook trigger expects,
> not the deprecated O365 connector format.

---

## Step 12 — Publish to ACR (1 min)

**Open:** [`.github/workflows/publish.yml`](.github/workflows/publish.yml).

**Highlight:**

```yaml
- name: Publish module to ACR
  run: |
    TARGET="br:${ACR_NAME}.azurecr.io/${MODULE_REPO}:${VERSION}"
    az bicep publish \
      --file "$MODULE_PATH" \
      --target "$TARGET" \
      --documentation-uri "..." \
      --with-source
```

**Say:**
> Triggered by pushing a `v*.*.*` tag after the PR merges. `--with-source`
> means consumers can debug-step into the module from VS Code. The
> wrapper's version is intentionally decoupled from the AVM version — the
> wrapper can iterate without forcing a no-op AVM bump.

---

## Step 13 — Switch to the consumer (3 min)

**Switch VS Code to** `agentic-automation-consumer`.

```
agentic-automation-consumer/
├── bicepconfig.json                        ← ACR alias
├── main.bicep                              ← pins keyvault-shared:<ver>
├── parameters/main.bicepparam
├── .github/
│   ├── CODEOWNERS                          ← platform owns the pin line
│   └── workflows/
│       ├── deploy.yml                      ← 3-line caller
│       └── module-update-check.yml         ← 3-line caller
└── README.md
```

### 13a. The pin

**Open:** [`main.bicep`](../agentic-automation-consumer/main.bicep), point at:

```bicep
module kv 'br/shared:keyvault-shared:0.11.0' = {
```

### 13b. The thin caller

**Open:** [`.github/workflows/deploy.yml`](../agentic-automation-consumer/.github/workflows/deploy.yml).
The whole file:

```yaml
on:
  pull_request: { paths: [ 'main.bicep', 'parameters/**', 'bicepconfig.json' ] }
  push: { branches: [ main ] }

jobs:
  deploy:
    uses: adusa/agentic-automation-producer/.github/workflows/consumer-deploy.yml@v1
    secrets: inherit
```

**Say:**
> That's it. No copy-pasted Azure-login, no copy-pasted bicep build, no
> copy-pasted what-if. All the logic lives in the producer. When the
> platform team improves the deploy flow, every consumer picks it up.

### 13c. CODEOWNERS

**Open:** [`.github/CODEOWNERS`](../agentic-automation-consumer/.github/CODEOWNERS).

**Say:**
> The pinned-version line and the registry config are owned by the platform
> team. The app team can't merge a bypass without platform approval.

---

## Step 14 — How it scales to N consumers (1 min)

**Open:** producer's [`.github/workflows/consumer-deploy.yml`](.github/workflows/consumer-deploy.yml).

**Highlight the `workflow_call` interface — inputs and required secrets.**

**Say:**
> Onboarding a new app team is: clone the consumer template, set five
> repo secrets/variables, edit `main.bicep`. Five files, no copy-pasted
> CI. The full onboarding checklist is in `DESIGN.md` §8.5.

---

## Step 15 — End-to-end recap (1 min)

Show this diagram (also in `DESIGN.md` §4):

```
┌──────────┐  ┌────────────┐  ┌────────────┐  ┌────────────────┐  ┌──────────────┐
│ Cron     │─▶│ check      │─▶│ diff       │─▶│ gh issue       │─▶│ Copilot      │
│ 06:00    │  │ -avm-      │  │ -avm-      │  │ --assignee     │  │ Coding Agent │
│ UTC      │  │ version.sh │  │ versions.sh│  │ copilot        │  │              │
└──────────┘  └────────────┘  └─────┬──────┘  └────────────────┘  └──────┬───────┘
                                    │  Teams card #1                     │
                                    ▼                                    ▼
                              summary.md                           draft PR opened
                                                                         │
                                                                         ▼
                                                                ┌──────────────────┐
                                                                │ pr-validate.yml  │
                                                                │ build/lint/whatif│
                                                                │ Teams card #2    │
                                                                └────────┬─────────┘
                                                                         │
                                                                  human review +
                                                                  merge + tag
                                                                         │
                                                                         ▼
                                                                ┌──────────────────┐
                                                                │ publish.yml      │
                                                                │ → ACR            │
                                                                │ Teams card #3    │
                                                                └────────┬─────────┘
                                                                         │
                                                                         ▼
                                                            Renovate / module-update-
                                                            check fans out PRs to
                                                            every consumer repo
```

**Say:**
> One trigger, one source of truth, one Copilot agent, three pings, N
> consumers updated. Six PDF requirements green; the SCF policy scan is
> the only remaining gap, and the plan is documented.

**Then:** open `POC-COVERAGE.md` for any audit follow-ups; open `DESIGN.md`
for any architecture follow-ups.

---

## Q&A pocket answers

> **"Why decouple wrapper version from AVM version?"**
> The wrapper sometimes needs a fix that doesn't correspond to an AVM bump
> (a new pass-through parameter, a doc fix, a default tweak). Independent
> semver lets us ship that without forcing a no-op AVM bump.

> **"What if Copilot's PR is wrong?"**
> It's a draft PR. `pr-validate.yml` runs build + lint + what-if before any
> human review. CODEOWNERS ensures the platform team is on every review.
> Bad PR = closed, no production impact.

> **"What if the AVM module makes a breaking change Copilot can't map?"**
> The instructions tell the agent to keep the old parameter as a
> `// DEPRECATED:` alias for one release. If even that's impossible, the
> agent is supposed to flag it in the PR description rather than silently
> drop the parameter — and the human reviewer makes the call.

> **"Can other module wrappers reuse this?"**
> Yes — replicate the producer repo per AVM module (App Service, Storage,
> etc.). Scripts and workflow shapes are generic; only `MODULE_PATH` and
> the parameter mappings differ.
