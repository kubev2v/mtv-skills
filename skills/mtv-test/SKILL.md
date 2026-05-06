---
name: mtv-test
description: >-
  Generate, review, and run bash e2e test scripts for MTV/Forklift bugs and
  features through a guided multi-step workflow (gather context, write test
  plan, get approval, generate script, run and refine). Use when the user
  asks to create a test, write a test script, verify a bug fix, build an e2e
  test, generate a verification script, or mentions an MTV/Forklift Jira
  ticket (MTV-<number>) together with testing.
---

# MTV Verification Script Generator

Generate self-contained bash e2e verification scripts for MTV/Forklift bugs and features.
Scripts follow a standard pattern: create namespace → create providers → run test steps → verify result → cleanup.

## Workflow

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

Ask the user for any information not found in the ticket. Collect only what is needed, no need to get specific string data an enviornment variable name is good too:

| Information | When needed |
|---|---|
| Provider type (vsphere / ovirt / openstack / ova / openshift / hyperv / ec2) | Always |
| Source provider URL | Always (except OVA and EC2) |
| Credentials (username / password / token) | Always (except OVA) |
| VM name(s) to migrate | When the test involves a migration plan |
| TLS mode (cacert or insecure-skip-tls) | Always (except OVA) |
| Any custom image or setting to override | When the ticket references a fix image |

**Do not ask for information that has a clear default** (e.g. namespace name, plan name, provider name — these can be derived from the ticket number).

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

Write a test plan markdown file named `tests/scenarios/test-mtv-<number>.md` (relative to
the repo root). Create the `tests/scenarios/` directory if it does not exist.

**Note:** `tests/scenarios/` is gitignored — scripts and docs are private per developer
and are not committed to the repository.

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

**STOP — Do not proceed unless `tests/scenarios/test-mtv-<number>.md` exists and the user has explicitly approved the test plan from Step 3.**

After plan approval, generate a bash script named `tests/scenarios/test-mtv-<number>.sh`.

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
- Use `oc wait --for=condition=Ready` with explicit timeouts after each resource creation.
  **When a test expects a resource to NOT be Ready** (e.g. a plan that should be
  blocked by a validation condition), use the `wait_for_plan_condition` polling helper
  from [ref-helpers.md](ref-helpers.md) instead.
- Exit 0 = PASS, exit 1 = FAIL, exit 2 = INCONCLUSIVE (test ran but result is ambiguous)
- Add a clear `echo "TEST PASSED/FAILED/INCONCLUSIVE: <reason>"` before each exit
- **Continue on failure**: When a script has multiple scenarios, use the multi-scenario
  subshell pattern from [ref-helpers.md](ref-helpers.md) to record failures and continue.
- Use numbered `STEP N:` echo banners so logs are easy to follow
- Variables that users commonly override go at the top as constants with defaults
- Support `SKIP_CLEANUP=true` to skip cleanup and preserve all resources for forensic inspection
- Include a preflight section that verifies MTV is installed and checks VDDK image is configured
- **Be verbose**: echo key `oc` commands before executing them, prefixed with `>>>`, so users
  can follow along, reproduce steps manually, and debug failures. Key commands to echo:
  - Provider creation (`oc mtv create provider ...`)
  - Inventory queries (`oc mtv get inventory storage ...`)
  - Plan creation (`oc mtv create plan ...`) — show the full command with all flags
  - Plan start (`oc mtv start plan ...`)
  - PVC listing (`oc get pvc -n ...`) — show the full table output, not just names
  - Mask secrets/tokens in echoed commands (use `${VAR_NAME}` instead of the value)

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
bash tests/scenarios/test-mtv-<number>.sh 2>&1 | tee tests/scenarios/test-mtv-<number>.log
```

After each run:
1. Read the full log output
2. Identify failures, unexpected output, or missing assertions
3. Propose specific fixes to the script
4. Ask the user whether to apply the fix and re-run

Repeat until the user is satisfied with the result or declares the test complete.
