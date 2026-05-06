# Bash Helper Functions

Reusable helper functions for generated verification scripts.
Include only the helpers that apply to the scenario being tested.

## CA Certificate Helper

Include when TLS verification is needed. Pick the variant that matches the provider type.

### Generic — extract from TLS handshake

Works for vSphere, OpenStack, and as a fallback for any provider:

```bash
fetch_ca_cert() {
  local hostport host
  hostport=$(echo "$1" | sed -E 's|https?://||; s|/.*||')
  host="${hostport%%:*}"
  if ! echo "${hostport}" | grep -q ':'; then
    hostport="${hostport}:443"
  fi
  openssl s_client -showcerts -servername "${host}" \
    -connect "${hostport}" </dev/null 2>/dev/null \
    | awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/'
}
```

### oVirt/RHV — engine PKI endpoint

Preferred for oVirt — returns the actual CA certificate rather than relying on
the TLS chain:

```bash
fetch_ca_cert() {
  local host
  host=$(echo "$1" | sed -E 's|https?://||; s|[:/].*||')
  curl -sSk "https://${host}/ovirt-engine/services/pki-resource?resource=ca-certificate&format=X509-PEM-CA"
}
```

## Plan Health Check

After creating a plan and waiting for `condition=Ready`, check for critical
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

## Wait-for-Condition Polling

Use when a test expects a resource to NOT be Ready (e.g. a plan blocked by a validation
condition). This polling loop races the expected condition against `Ready`, returning
whichever appears first:

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

## Multi-Scenario Pattern (continue on failure)

When a script has multiple scenarios, do not `exit 1` on the first failure.
Record failures and continue so the user sees all results in a single run.

Since the script uses `set -euo pipefail`, wrap each scenario in a subshell:

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

Print a summary table at the end:

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

## Between-Scenario Cleanup

When reusing a namespace and providers across scenarios, clean up only the plan
and migrated artifacts between runs:

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
