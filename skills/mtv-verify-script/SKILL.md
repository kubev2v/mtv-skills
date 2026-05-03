---
name: mtv-verify-script
description: Generate and run a self-contained bash verification script for an MTV/Forklift bug or feature. Use this skill when the user asks to "create a verification script", "write a test script", "generate a bash test", "create an e2e test script", or "write a verification bash script" for an MTV/Forklift Jira ticket.
---

# MTV Verification Script Generator

Generate self-contained bash e2e verification scripts for MTV/Forklift bugs and features.
Scripts follow a standard pattern: create namespace → create providers → run test steps → verify result → cleanup.

## Workflow

Follow these steps in order. Never skip a step. Always wait for user confirmation before proceeding.

---

### Step 1 — Get the Jira ticket and related PRs

Ask the user for the Jira ticket number (e.g. `MTV-4911`).

#### 1a. Fetch the Jira ticket

```
WebFetch  url: "https://redhat.atlassian.net/browse/MTV-<number>"
```

Extract from the ticket:
- **Summary** — one-line description of the bug or feature
- **Description** — full problem statement and expected behavior
- **Acceptance criteria** — what "fixed" or "working" looks like
- **Component** — which part of MTV is affected (controller, UI, provider, plan, migration)
- **Provider types mentioned** — vSphere, oVirt, OpenStack, OVA, EC2, HyperV

If the ticket is not publicly accessible or the fetch fails, ask the user to paste the relevant description.

#### 1b. Search for related PRs in the forklift repo

Search GitHub for pull requests in `kubev2v/forklift` that reference this ticket:

```
WebFetch  url: "https://github.com/kubev2v/forklift/pulls?q=MTV-<number>"
```

For each PR found, fetch its detail page to extract:
- **PR title and description** — especially any "How to test" or "Testing" sections
- **Files changed** — which components were modified (controller, provider adapter, plan, UI, etc.)
- **Unit tests added** — what scenarios the unit tests cover (these reveal the edge cases to exercise)
- **Any "before/after" behavior** described in the PR body

```
WebFetch  url: "https://github.com/kubev2v/forklift/pull/<pr-number>"
```

Use the PR information to answer:
- What exact behavior changed? (informs the core test assertion)
- What are the edge cases or boundary conditions? (informs additional test scenarios)
- Are there "how to reproduce" steps in the PR? (informs the test steps)
- Which provider type(s) are involved?

If no PRs are found via the search page, also try:
```
WebFetch  url: "https://api.github.com/search/issues?q=MTV-<number>+repo:kubev2v/forklift+type:pr"
```

Summarize what you learned from the Jira ticket and PRs before proceeding to Step 2.

---

### Step 2 — Gather environment information

Ask the user for any information not found in the ticket. Collect only what is needed:

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

After plan approval, generate a bash script named `tests/scenarios/test-mtv-<number>.sh`.

#### Script structure

```bash
#!/bin/bash
#
# E2E test for <summary> (MTV-<number>).
#
# Prerequisites: oc, oc mtv plugin, <env vars>,
#   and a cluster with MTV installed (controller in konveyor-forklift by default).

set -euo pipefail

# --- Constants ---
NS="mtv-<number>-test"
PROVIDER="<type>-test"
PLAN="mtv-<number>-plan"
SKIP_CLEANUP="${SKIP_CLEANUP:-false}"
POLL=15
# <other ticket-specific constants>

# ===================================================================
#  Preflight: verify MTV is installed and provider prerequisites
# ===================================================================
echo "============================================================="
echo "PREFLIGHT: Checking MTV installation"
echo "============================================================="

if ! command -v oc &>/dev/null; then
  echo "ERROR: 'oc' CLI not found in PATH."
  exit 1
fi

if ! oc mtv settings get --setting vddk_image &>/dev/null; then
  echo "ERROR: Cannot read MTV settings. Is MTV installed on this cluster?"
  exit 1
fi
echo "MTV controller found."

VDDK_IMAGE=$(oc mtv settings get --setting vddk_image 2>/dev/null \
  | tail -1 | awk '{print $NF}')
if [[ -n "${VDDK_IMAGE}" && "${VDDK_IMAGE}" != "<none>" && "${VDDK_IMAGE}" != "VALUE" ]]; then
  echo "VDDK image configured: ${VDDK_IMAGE}"
else
  echo "ERROR: VDDK image not configured. Required for migrations."
  echo "Set it with: oc mtv settings set --setting vddk_image --value <image>"
  exit 1
fi

echo "Preflight passed."
echo ""

# ===================================================================
#  Cleanup (also runs on error via trap)
# ===================================================================
cleanup() {
  if [[ "${SKIP_CLEANUP}" == "true" ]]; then
    echo "SKIP_CLEANUP=true — preserving resources in namespace '${NS}' for forensic inspection."
    return 0
  fi
  echo "Cleaning up..."
  oc mtv delete plan     --name "${PLAN}" -n "${NS}" 2>/dev/null || true
  oc mtv delete provider --name "${PROVIDER}" -n "${NS}"            2>/dev/null || true
  oc mtv delete provider --name host -n "${NS}"                     2>/dev/null || true
  oc delete namespace "${NS}" --ignore-not-found                    2>/dev/null || true
  # <revert any settings overrides>
  echo "Cleanup done."
}
trap cleanup EXIT
cleanup

# ===================================================================
#  STEP 1: Create namespace
# ===================================================================
echo "STEP 1: Creating namespace '${NS}'"
oc create namespace "${NS}" --dry-run=client -o yaml | oc apply -f -

# ===================================================================
#  STEP 2: Create provider(s)
# ===================================================================
# <use oc mtv create provider with appropriate flags>
# For vSphere (insecure):
#   oc mtv create provider --name "${PROVIDER}" --type vsphere \
#     --url "${GOVC_URL}/sdk" --username "${GOVC_USERNAME}" \
#     --password "${GOVC_PASSWORD}" --provider-insecure-skip-tls -n "${NS}"
#
# For vSphere (with CA cert):
#   oc mtv create provider --name "${PROVIDER}" --type vsphere \
#     --url "${GOVC_URL}/sdk" --username "${GOVC_USERNAME}" \
#     --password "${GOVC_PASSWORD}" \
#     --cacert "$(fetch_ca_cert "${GOVC_URL}")" -n "${NS}"

echo "Creating host (local OpenShift) provider"
oc mtv create provider --name host --type openshift -n "${NS}"

echo "Waiting for providers Ready..."
oc wait "provider.forklift.konveyor.io/${PROVIDER}" -n "${NS}" \
  --for=condition=Ready --timeout=300s
oc wait "provider.forklift.konveyor.io/host" -n "${NS}" \
  --for=condition=Ready --timeout=300s

# ===================================================================
#  STEP 3: Create migration plan (if needed for this test)
# ===================================================================
# oc mtv create plan --name "${PLAN}" --source "${PROVIDER}" \
#   --vms "${VM}" -n "${NS}"
# oc wait "plan.forklift.konveyor.io/${PLAN}" -n "${NS}" \
#   --for=condition=Ready --timeout=300s

# ===================================================================
#  STEP <N>: <Ticket-specific test steps>
# ===================================================================
# <Insert the core test logic here — this is ticket-specific>

# ===================================================================
#  Summary
# ===================================================================
echo ""
echo "TEST PASSED: <what this confirms>"
exit 0
```

#### CA certificate helper

Include this function when TLS verification is needed (non-insecure providers):

```bash
fetch_ca_cert() {
  local hostport
  hostport=$(echo "$1" | sed -E 's|https?://||; s|/.*||')
  if ! echo "${hostport}" | grep -q ':'; then
    hostport="${hostport}:443"
  fi
  openssl s_client -showcerts -connect "${hostport}" </dev/null 2>/dev/null \
    | awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/'
}
```

#### Plan health check

After creating a plan and waiting for `condition=Ready`, always check for critical
conditions before starting the migration:

```bash
check_plan_health() {
  local plan_name="$1"
  echo "Checking plan health..."
  local critical
  critical=$(oc get plan.forklift.konveyor.io/"${plan_name}" -n "${NS}" \
    -o jsonpath='{range .status.conditions[*]}{.type}={.status}={.category}={.message}{"\n"}{end}' 2>/dev/null || echo "")
  if echo "${critical}" | grep -q "=True=Critical="; then
    echo "ERROR: Plan '${plan_name}' has critical issues:"
    echo "${critical}" | grep "=True=Critical=" | while IFS='=' read -r ctype cstatus ccat cmsg; do
      echo "  ${ctype}: ${cmsg}"
    done
    return 1
  fi
  echo "Plan health OK."
  return 0
}
```

Common critical conditions include `VMStorageNotMapped` (storage mapping missing) and
`VMNetworkNotMapped` (network mapping missing). Fix these by providing explicit
`--storage-pairs` or `--network-pairs` when creating the plan.

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
  blocked by a validation condition), do not wait for `Ready` — it will never come.
  Instead, write a polling loop that races the expected condition against `Ready`,
  returning whichever appears first. The test then asserts which one won:
  ```bash
  wait_for_plan_condition() {
    local plan_name="$1"
    local target_condition="$2"   # e.g. "VMCriticalConcerns"
    local elapsed=0
    while [[ ${elapsed} -lt ${MAX_WAIT} ]]; do
      local target_status ready_status
      target_status=$(oc get plan.forklift.konveyor.io/"${plan_name}" -n "${NS}" \
        -o jsonpath="{.status.conditions[?(@.type==\"${target_condition}\")].status}" 2>/dev/null || echo "")
      ready_status=$(oc get plan.forklift.konveyor.io/"${plan_name}" -n "${NS}" \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
      if [[ "${target_status}" == "True" ]]; then echo "${target_condition}"; return 0; fi
      if [[ "${ready_status}" == "True" ]]; then echo "Ready"; return 0; fi
      sleep "${POLL}"; elapsed=$((elapsed + POLL))
    done
    echo "TIMEOUT"; return 1
  }

  # Usage: expect blocked plan
  result=$(wait_for_plan_condition "${PLAN}" "VMCriticalConcerns")
  [[ "${result}" == *"VMCriticalConcerns"* ]] && echo "PASS" || echo "FAIL"

  # Usage: expect ready plan
  result=$(wait_for_plan_condition "${PLAN}" "VMCriticalConcerns")
  [[ "${result}" == *"Ready"* ]] && echo "PASS" || echo "FAIL"
  ```
- Exit 0 = PASS, exit 1 = FAIL, exit 2 = INCONCLUSIVE (test ran but result is ambiguous)
- Add a clear `echo "TEST PASSED/FAILED/INCONCLUSIVE: <reason>"` before each exit
- **Continue on failure**: When a script has multiple scenarios, do not `exit 1` on the first
  failure. Instead, record failures in a variable (e.g. `FAILURES+="..."`), clean up the
  scenario, and continue to the next one. Print a summary at the end showing each scenario's
  pass/fail status and exit 1 only if any scenario failed. This gives the user full visibility
  into which scenarios pass and which fail in a single run.
  Since the script uses `set -euo pipefail`, wrap each scenario's risky operations (plan
  creation, migration start, wait) in a subshell so errors are caught without aborting:
  ```bash
  FAILURES=""
  SCENARIO_X_PASS=false

  set +e
  (
    set -euo pipefail
    create_plan "${PLAN_X}" --some-flag
    oc mtv start plan --name "${PLAN_X}" -n "${NS}"
    wait_for_plan "${PLAN_X}"
  )
  SCENARIO_X_RC=$?
  set -e

  if [[ ${SCENARIO_X_RC} -ne 0 ]]; then
    echo "SCENARIO X FAIL: plan creation or migration failed"
    FAILURES="${FAILURES}  X: plan creation or migration failed\n"
  else
    # ... verify PVC names or other assertions ...
  fi
  cleanup_scenario "${PLAN_X}"
  ```
  At the end, print a summary table and exit based on whether `FAILURES` is empty:
  ```bash
  echo "RESULTS:"
  echo "  A: ${SCENARIO_A_PASS}"
  echo "  B: ${SCENARIO_B_PASS}"
  if [[ -z "${FAILURES}" ]]; then
    echo "TEST PASSED: All scenarios verified successfully"
    exit 0
  else
    echo "TEST FAILED: One or more scenarios failed:"
    echo -e "${FAILURES}"
    exit 1
  fi
  ```
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

Between-scenario cleanup helper pattern:

```bash
cleanup_scenario() {
  local plan_name="$1"
  oc mtv delete plan --name "${plan_name}" -n "${NS}" 2>/dev/null || true
  oc delete vm "${VM_NAME}" -n "${NS}" --ignore-not-found 2>/dev/null || true
  sleep 5
  local pvcs
  pvcs=$(oc get pvc -n "${NS}" --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null || true)
  for pvc in ${pvcs}; do
    oc delete pvc "${pvc}" -n "${NS}" --ignore-not-found 2>/dev/null || true
  done
  local dvs
  dvs=$(oc get dv -n "${NS}" --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null || true)
  for dv in ${dvs}; do
    oc delete dv "${dv}" -n "${NS}" --ignore-not-found 2>/dev/null || true
  done
  sleep 5
}
```

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

---

## Reference: Provider Creation Commands

### vSphere (insecure)
```bash
oc mtv create provider --name "${PROVIDER}" --type vsphere \
  --url "${GOVC_URL}/sdk" \
  --username "${GOVC_USERNAME}" \
  --password "${GOVC_PASSWORD}" \
  --provider-insecure-skip-tls \
  -n "${NS}"
```

### vSphere (with CA cert)
```bash
oc mtv create provider --name "${PROVIDER}" --type vsphere \
  --url "${GOVC_URL}/sdk" \
  --username "${GOVC_USERNAME}" \
  --password "${GOVC_PASSWORD}" \
  --cacert "$(fetch_ca_cert "${GOVC_URL}")" \
  -n "${NS}"
```

### oVirt / RHV
```bash
oc mtv create provider --name "${PROVIDER}" --type ovirt \
  --url "${RHV_URL}" \
  --username "${RHV_USERNAME}" \
  --password "${RHV_PASSWORD}" \
  --cacert "$(fetch_ca_cert "${RHV_URL}")" \
  -n "${NS}"
```

### OpenStack
```bash
oc mtv create provider --name "${PROVIDER}" --type openstack \
  --url "${OSP_URL}" \
  --username "${OSP_USERNAME}" \
  --password "${OSP_PASSWORD}" \
  --provider-domain-name "${OSP_DOMAIN_NAME}" \
  --provider-project-name "${OSP_PROJECT_NAME}" \
  --provider-region-name "${OSP_REGION_NAME}" \
  --cacert "$(fetch_ca_cert "${OSP_URL}")" \
  -n "${NS}"
```

### OVA
```bash
oc mtv create provider --name "${PROVIDER}" --type ova \
  --url "${OVA_URL}" \
  -n "${NS}"
```

### Remote OpenShift (source)
```bash
oc mtv create provider --name "${PROVIDER}" --type openshift \
  --url "${SOURCE_OCP_URL}" \
  --provider-token "${SOURCE_OCP_TOKEN}" \
  --provider-insecure-skip-tls \
  -n "${NS}"
```
The remote OpenShift cluster is typically the **source** (where VMs live). Use the
`SOURCE_` prefix for its env vars to distinguish from the local cluster running MTV.
Use with the local OpenShift provider (below) which serves as the target.

### HyperV
```bash
oc mtv create provider --name "${PROVIDER}" --type hyperv \
  --url "${HV_URL}" \
  --username "${HV_USERNAME}" \
  --password "${HV_PASSWORD}" \
  --smb-url "${HV_SMB_URL}" \
  --provider-insecure-skip-tls \
  -n "${NS}"
```

### EC2
```bash
oc mtv create provider --name "${PROVIDER}" --type ec2 \
  --ec2-region "${EC2_REGION}" \
  --target-access-key-id "${EC2_ACCESS_KEY_ID}" \
  --target-secret-access-key "${EC2_SECRET_ACCESS_KEY}" \
  --target-az "${EC2_TARGET_AZ}" \
  --target-region "${EC2_TARGET_REGION}" \
  -n "${NS}"
```

### OpenShift (local cluster)
```bash
oc mtv create provider --name host --type openshift -n "${NS}"
```
The local OpenShift provider auto-detects the current cluster and needs no URL or token.
It is typically the target but can serve as the source when the remote OpenShift is the target.
