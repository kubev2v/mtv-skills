---
name: mtv-test
description: >-
  Generate bash e2e verification scripts for MTV/Forklift bugs and features
  through a guided workflow (gather context, write test plan, get approval,
  generate script). Use when the user asks to create a test, write a test
  script, verify a bug fix, build an e2e test, generate a verification
  script, or mentions an MTV/Forklift Jira ticket (MTV-<number>) together
  with testing.
---

# MTV Verification Script Generator

Generate self-contained bash e2e verification scripts for MTV/Forklift bugs and features.
Scripts follow a standard pattern: create namespace → create providers → run test steps → verify result → cleanup.

## Workflow

**Before starting, review existing examples for patterns and best practices:**
- Local: look for existing `test-mtv-*.sh` scripts in the test directory (`tests/scenarios/` or `MTV_TESTS_DIR`)
- Remote: https://github.com/kubev2v/mtv-skills/tree/main/examples/mtv-test
- Provider creation: see `examples/mtv-test/create-providers.sh` in the skill repository for CA cert fetching, skip-TLS, and per-type patterns

Use these as reference for structure, logging style, cleanup patterns, and provider creation.

---

### Mode: Headless vs Interactive

**Headless mode** -- Triggered when the user includes `--headless` in their message,
or when the phrasing implies immediate output without interaction (e.g., "generate test
for MTV-1234", "create test script for MTV-1234"):
- Skip all interactive prompts (Steps 1c, 2, 3 approval gate, 4 approval gate, 5)
- Fetch the ticket, evaluate if it has enough info, and either generate both files
  or report what's missing
- Use defaults from the table below for any information not found in the ticket
- Do NOT run the script automatically

**Interactive mode** -- The default when `--headless` is not specified and the user
uses collaborative phrasing (e.g., "help me write a test for MTV-1234", "let's create
a verification script"):
- Follow Steps 1-5 as documented below

---

### Headless Flow

When running in headless mode, execute these steps without prompting:

1. **Fetch the Jira ticket** using the instructions in [ref-jira.md](ref-jira.md).
2. **Evaluate sufficiency** -- the ticket must contain at minimum:
   - A clear description of what to test (bug fix, feature, regression)
   - Provider type (explicitly stated or inferable from context)
   - Steps to reproduce or acceptance criteria
3. **If insufficient** -- report what is missing and stop. Do NOT prompt interactively.
   Output format:
   ```
   Cannot generate test script for MTV-XXXX:
   - <field>: <why it is missing or ambiguous>
   - ...

   Provide this information or use interactive mode for guided test creation.
   ```
4. **If sufficient** -- generate both files directly into the test directory
   (`tests/scenarios/` or `MTV_TESTS_DIR`):
   - `<test-dir>/test-mtv-<number>.md` (test plan)
   - `<test-dir>/test-mtv-<number>.sh` (test script)
5. **Report result** -- show the user what was generated and where the files are.

#### Headless Defaults

| Field | Default |
|-------|---------|
| Namespace | `mtv-<number>-test` |
| Provider name | `<type>-test` |
| Plan name | `mtv-<number>-plan` |
| TLS mode | `--provider-insecure-skip-tls` |
| VM name | `${VM:-my-test-vm}` |
| SKIP_CLEANUP | `${SKIP_CLEANUP:-false}` |
| Credentials | Environment variable references (never hardcoded) |

---

## Interactive Mode

**Follow these steps in order. Never skip a step. Never generate the bash script before the test plan is written and approved by the user.**

---

### Step 1 — Understand what to test

**Always ask the user what they want to test.** The user may provide context as a Jira
ticket, a GitHub PR, a free-text description, or any combination.

#### Flow

1. **If the trigger message mentions a Jira ticket or GitHub PR** — try to fetch it, then ask follow-up clarifying questions based on what
   the ticket/PR contains and the user request.
2. **If the trigger message is a free-text description with no reference** — ask 
   clarifying questions. If the user provides a ticket or PR, try to fetch it and ask follow-up questions.

#### 1a. Fetching a Jira ticket (e.g. `MTV-4911`)

> How to fetch and setup instructions: [ref-jira.md](ref-jira.md)

#### 1b. Fetching a GitHub PR

> How to fetch and setup instructions: [ref-github.md](ref-github.md)

#### 1c. Clarifying questions

After fetching (or if no reference was given), ask what is still unclear:

- What exactly should the test verify? (bug fix, new feature, regression, edge case)
- Which provider type is involved? (vSphere, oVirt, OpenStack, OVA, OpenShift, HyperV, EC2)
- Are there specific steps to reproduce or acceptance criteria?

Tailor questions to what is already known, try to get all the information needed for building the e2e test script.

Summarize what you learned from all available sources before proceeding to Step 2.

---

### Step 2 — Gather environment information

**If the test needs to explore provider inventory** (e.g., to discover available networks, VMs, storage, or other resources), create a temporary namespace and providers first to query the inventory:

1. Create a temporary namespace (e.g., `mtv-<number>-temp`)
2. Create temporary providers (source and destination)
3. Wait for providers to be Ready
4. Query inventory using `oc mtv get inventory` (network, vm, storage, etc.)
5. Collect the needed information (e.g., available network names, VM names)
6. Delete the temporary namespace
7. Proceed with the regular test plan using the gathered information

**Alternative exploration methods:**
- For vSphere: use `govc` commands directly (e.g., `govc ls`, `govc vm.info`, `govc network.info`)
- For AWS/EC2: use AWS CLI (e.g., `aws ec2 describe-instances`, `aws ec2 describe-vpcs`)
- For other providers: use their native CLI tools as appropriate

After exploration (if needed), ask the user for any information not found in the ticket. Collect only what is needed, no need to get specific string data — an environment variable name is good too:

| Information | When needed |
|---|---|
| Provider type (vsphere / ovirt / openstack / ova / openshift / hyperv / ec2) | Always |
| Source provider URL | Always (except OVA and EC2) |
| Credentials (username / password / token) | Always (except OVA) |
| VM name(s) to migrate | When the test involves a migration plan |
| TLS mode (cacert or insecure-skip-tls) | Always (except OVA) |
| Any custom image or setting to override | When the ticket references a fix image |

**Do not ask for information that has a clear default** (e.g. namespace name, plan name, provider name — these can be derived from the ticket number).

**Do not check for environment variables in the script** — just use them directly (e.g., `${GOVC_URL}`). Let bash fail naturally if they are unset.

Inform the user which environment variables they should set:
- vSphere: `GOVC_URL`, `GOVC_USERNAME`, `GOVC_PASSWORD`
- oVirt/RHV: `RHV_URL`, `RHV_USERNAME`, `RHV_PASSWORD`
- OpenStack: `OSP_URL`, `OSP_USERNAME`, `OSP_PASSWORD`, `OSP_DOMAIN_NAME`, `OSP_PROJECT_NAME`, `OSP_REGION_NAME`
- OVA: `OVA_URL`
- Remote OpenShift (source): `SOURCE_OCP_URL`, `SOURCE_OCP_TOKEN`
- HyperV: `HV_URL`, `HV_USERNAME`, `HV_PASSWORD`, `HV_SMB_URL`
- EC2: `EC2_REGION`, `EC2_ACCESS_KEY_ID`, `EC2_SECRET_ACCESS_KEY`, `EC2_TARGET_AZ`, `EC2_TARGET_REGION`

**Naming convention for OCP-to-OCP:** The remote OpenShift cluster is the *source* (where
VMs live), and the local cluster (running MTV) is the *target*. Use the `SOURCE_` prefix
to make this clear — `SOURCE_OCP_URL` and `SOURCE_OCP_TOKEN` refer to the remote source
cluster, not the local cluster the script runs on.

---

### Step 3 — Create and review the test plan

The default test directory is `tests/scenarios/` (relative to the repo root). If the
environment variable `MTV_TESTS_DIR` is set and non-empty, use its value instead.
Create the directory if it does not exist.

Write a test plan markdown file named `<test-dir>/test-mtv-<number>.md`.

**Note:** `tests/scenarios/` is gitignored — scripts and docs are private per developer
and are not committed to the repository. If you use a custom `MTV_TESTS_DIR`, ensure
it is also excluded from version control.

The plan must include:

```markdown
# Test Plan: MTV-<number> — <summary>

## Objective
<What this test verifies, in one paragraph>

## Prerequisites
- oc with mtv plugin installed (kubectl also works)
- MTV installed on the cluster
- Environment variables set: <list>
- <Any other prereqs: VM name, VDDK image, custom controller image, etc.>

## Test Steps
1. <Step description>
2. …

## Pass Criteria
- <Specific observable outcome that confirms the fix/feature works>

## Fail Criteria
- <What indicates the bug is still present or the feature does not work>

## Cleanup
- Namespace `<ns>` deleted
- Providers deleted
- Any settings overrides reverted
```

**Present the plan to the user and ask for review.** Wait for explicit approval ("looks good", "approved", etc.) or for requested changes before proceeding.

---

### Step 4 — Generate the test script

**STOP — Do not proceed unless `<test-dir>/test-mtv-<number>.md` exists and the user has explicitly approved the test plan from Step 3.**

After plan approval, generate a bash script named `<test-dir>/test-mtv-<number>.sh`.

> Full script template with preflight, cleanup, and step structure: [ref-script-template.md](ref-script-template.md)

> Provider creation commands for all types: [ref-providers.md](ref-providers.md)

> Bash helper functions (CA cert, plan health, polling, multi-scenario): [ref-helpers.md](ref-helpers.md)

#### Storage mapping

By default, `oc mtv create plan` auto-generates storage and network mappings from
provider inventory. **Omit `--storage-pairs` unless** the auto-mapping picks the wrong
target storage class. When you do need to override, use explicit `--storage-pairs`:

#### Rules for the script

- Always use `set -euo pipefail`
- Always register `trap cleanup EXIT` and call `cleanup` at the start
- Cleanup must be idempotent (`2>/dev/null || true` on all delete commands)
- Namespace name, provider name, and plan name are derived from the ticket number
- **Prefer `oc mtv` CLI commands** (e.g. `oc mtv create provider`, `oc mtv create plan`,
  `oc mtv start plan`, `oc mtv delete plan`) over raw YAML with `oc create`/`oc apply`.
  The CLI handles secrets, mappings, and labels automatically. Only fall back to YAML
  when the CLI does not support the required operation.
- **Prefer `oc wait`** over polling loops. Use `oc wait --for=condition=Ready` with explicit timeouts after each resource creation.
  **When a test expects a resource to NOT be Ready** (e.g. a plan that should be
  blocked by a validation condition), use the `wait_for_plan_condition` polling helper
  from [ref-helpers.md](ref-helpers.md) instead.
- Exit 0 = PASS, exit 1 = FAIL, exit 2 = INCONCLUSIVE (test ran but result is ambiguous)
- Add a clear `echo "TEST PASSED/FAILED/INCONCLUSIVE: <reason>"` before each exit
- **Continue on failure**: When a script has multiple scenarios, use the multi-scenario
  subshell pattern from [ref-helpers.md](ref-helpers.md) to record failures and continue.
- Use `==========================================` (42 chars) separators with step headers
- Use numbered `STEP N:` echo banners so logs are easy to follow
- Variables that users commonly override go at the top as constants with defaults
- Support `SKIP_CLEANUP=true` to skip cleanup and preserve all resources for forensic inspection
- Include a preflight section that verifies MTV is installed; for vSphere providers, also check that the VDDK image is configured (skip the VDDK check for other provider types)
- Use simple progress messages before each command (e.g., "Creating provider...", "Waiting for plan...")
- Do NOT use `>>>` prefix or echo full commands — let the actual command output speak for itself
- Keep logging minimal and focused on what's happening, not how it's being done

#### Reusing namespace and providers across scenarios

When a test has multiple scenarios (e.g. testing different flag combinations on the same
provider), **share a single namespace and set of providers** across all scenarios:

- Create the namespace and providers once at the start
- Run each scenario sequentially, cleaning up only the plan and migrated artifacts
  (VM, PVCs, DataVolumes) between scenarios — not the namespace or providers
- Only delete the namespace and providers in the final `trap cleanup EXIT`
- This avoids redundant provider creation/reconciliation and keeps tests faster
- Use the `cleanup_scenario` helper from [ref-helpers.md](ref-helpers.md) for between-run cleanup

**Present the script to the user and ask for permission to run it.** Do not run it automatically.

---

### Step 5 — Run and refine

After the user grants permission, run the script:

```bash
bash <test-dir>/test-mtv-<number>.sh 2>&1 | tee <test-dir>/test-mtv-<number>.log
```

After each run:
1. Read the full log output
2. Identify failures, unexpected output, or missing assertions
3. Propose specific fixes to the script
4. Ask the user whether to apply the fix and re-run

Repeat until the user is satisfied with the result or declares the test complete.
