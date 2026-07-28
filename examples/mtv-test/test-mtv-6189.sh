#!/bin/bash
#
# E2E test for simplified PVC name template (MTV-6189).
#
# Verifies:
#   A) Empty pvcNameTemplate falls back to hardcoded default (with generateName suffix)
#   B) Custom template with .VmId variable works
#   C) Explicit useGenerateName=false produces exact names (no suffix)
#   D) ForkliftController global template overrides hardcoded default
#
# Prerequisites: oc, oc mtv plugin, VDDK image configured,
#   and a cluster with MTV installed (MTV-6189 branch).

set -euo pipefail

# --- Constants ---
NS="mtv-6189-test"
PROVIDER="vsphere-test"
PLAN_A="mtv-6189-default"
PLAN_B="mtv-6189-custom"
PLAN_C="mtv-6189-exact"
PLAN_D="mtv-6189-global"
VM="${VM:-mtv-rhel8-sanity}"
SKIP_CLEANUP="${SKIP_CLEANUP:-false}"
POLL=30
MAX_WAIT=1200

# ===================================================================
#  Preflight: verify MTV is installed and VDDK is configured
# ===================================================================
echo "=========================================="
echo "MTV-6189 Test: Simplified PVC Name Template"
echo "=========================================="
echo ""
echo "Preflight: Checking MTV installation..."

if ! command -v oc &>/dev/null; then
  echo "ERROR: 'oc' CLI not found in PATH."
  exit 1
fi

if ! oc mtv settings get --setting vddk_image &>/dev/null; then
  echo "ERROR: Cannot read MTV settings. Is MTV installed on this cluster?"
  exit 1
fi
echo "MTV controller found."

VDDK_IMAGE=$(oc mtv settings get --setting vddk_image 2>/dev/null | tr -d '[:space:]')
if [[ -n "${VDDK_IMAGE}" && "${VDDK_IMAGE}" != "<none>" && "${VDDK_IMAGE}" != "(notset)" ]]; then
  echo "VDDK image configured: ${VDDK_IMAGE}"
else
  echo "ERROR: VDDK image not configured. Required for vSphere migrations."
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
    echo "SKIP_CLEANUP=true -- preserving resources in namespace '${NS}' for forensic inspection."
    return 0
  fi
  echo "Cleaning up..."
  oc mtv delete plan     --name "${PLAN_A}" -n "${NS}" 2>/dev/null || true
  oc mtv delete plan     --name "${PLAN_B}" -n "${NS}" 2>/dev/null || true
  oc mtv delete plan     --name "${PLAN_C}" -n "${NS}" 2>/dev/null || true
  oc mtv delete plan     --name "${PLAN_D}" -n "${NS}" 2>/dev/null || true
  oc mtv delete provider --name "${PROVIDER}" -n "${NS}" 2>/dev/null || true
  oc mtv delete provider --name host -n "${NS}"          2>/dev/null || true
  oc delete namespace "${NS}" --ignore-not-found         2>/dev/null || true
  local cr
  cr=$(oc get forkliftcontroller -n konveyor-forklift --no-headers \
    -o custom-columns=NAME:.metadata.name 2>/dev/null | head -1 || true)
  if [[ -n "${cr}" ]]; then
    oc patch forkliftcontroller/"${cr}" -n konveyor-forklift \
      --type=json -p '[{"op":"remove","path":"/spec/controller_pvc_name_template"}]' 2>/dev/null || true
  fi
  echo "Cleanup done."
}
trap cleanup EXIT
cleanup

# ===================================================================
#  Helpers
# ===================================================================
cleanup_scenario() {
  local plan_name="$1"
  oc mtv delete plan --name "${plan_name}" -n "${NS}" 2>/dev/null || true
  local vm_name
  vm_name=$(oc get vm -n "${NS}" --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null | head -1 || true)
  if [[ -n "${vm_name}" ]]; then
    oc delete vm "${vm_name}" -n "${NS}" --ignore-not-found 2>/dev/null || true
  fi
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

get_pvcs() {
  oc get pvc -n "${NS}" -l plan --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null \
    | grep -v '^prime-' || true
}

wait_for_pvcs() {
  local elapsed=0
  while [[ ${elapsed} -lt ${MAX_WAIT} ]]; do
    local pvcs
    pvcs=$(get_pvcs)
    if [[ -n "${pvcs}" ]]; then
      echo "PVCs detected after ${elapsed}s."
      return 0
    fi
    echo "Waiting for PVCs to appear... (${elapsed}s elapsed)"
    sleep "${POLL}"
    elapsed=$((elapsed + POLL))
  done
  echo "No PVCs appeared within ${MAX_WAIT}s"
  return 1
}

start_plan_and_wait_for_pvcs() {
  local plan_name="$1"
  echo "Waiting for plan to be Ready..."
  oc wait "plan.forklift.konveyor.io/${plan_name}" -n "${NS}" \
    --for=condition=Ready --timeout=300s

  echo "Starting migration..."
  oc mtv start plan --name "${plan_name}" -n "${NS}"

  wait_for_pvcs
}

# Get the ForkliftController CR name in the operator namespace.
get_controller_cr() {
  oc get forkliftcontroller -n konveyor-forklift --no-headers \
    -o custom-columns=NAME:.metadata.name 2>/dev/null | head -1
}

# check_pvcs PREFIX [--exact]
#   Verifies every PVC name starts with PREFIX.
#   With --exact, also rejects names that end with a 5-char random suffix.
#   Returns 0 if all match, 1 otherwise.
check_pvcs() {
  local prefix="$1"
  local exact="${2:-}"

  local pvcs
  pvcs=$(get_pvcs)
  echo "PVCs found:"
  echo "${pvcs}"
  echo ""

  local all_match=true
  for pvc_name in ${pvcs}; do
    if [[ "${pvc_name}" != ${prefix}* ]]; then
      echo "FAIL: '${pvc_name}' does not match expected prefix '${prefix}*'"
      all_match=false
      continue
    fi
    if [[ "${exact}" == "--exact" ]]; then
      local after="${pvc_name#"${prefix}"}"
      if [[ "${after}" =~ -[a-z0-9]{5}$ ]]; then
        echo "FAIL: '${pvc_name}' has random suffix (expected exact name)"
        all_match=false
        continue
      fi
      echo "OK:   '${pvc_name}' is an exact name (no random suffix)"
    else
      echo "OK:   '${pvc_name}' matches prefix '${prefix}'"
    fi
  done

  [[ "${all_match}" == "true" ]]
}

# run_scenario LABEL PLAN_NAME PREFIX [--exact]
#   Runs the PVC check, sets SCENARIO_<LABEL>_PASS and appends to FAILURES.
run_scenario_check() {
  local label="$1" plan_name="$2" prefix="$3"
  local exact="${4:-}"

  echo "Checking PVC names..."
  if check_pvcs "${prefix}" "${exact}"; then
    eval "SCENARIO_${label}_PASS=true"
    echo "SCENARIO ${label} PASS"
  else
    FAILURES="${FAILURES}  ${label}: PVC names don't match expected pattern\n"
  fi

  echo ""
  echo "Cleaning up scenario ${label}..."
  cleanup_scenario "${plan_name}"
}

# ===================================================================
#  STEP 1: Create namespace
# ===================================================================
echo ""
echo "=========================================="
echo "STEP 1: Creating namespace"
echo "=========================================="
oc create namespace "${NS}" --dry-run=client -o yaml | oc apply -f -
echo ""

# ===================================================================
#  STEP 2: Create providers
# ===================================================================
echo "=========================================="
echo "STEP 2: Creating providers"
echo "=========================================="

echo "Creating vSphere provider..."
oc mtv create provider --name "${PROVIDER}" --type vsphere \
  --url "https://${GOVC_URL}/sdk" \
  --username "${GOVC_USERNAME}" \
  --password "${GOVC_PASSWORD}" \
  --provider-insecure-skip-tls \
  -n "${NS}"

echo "Creating OpenShift provider..."
oc mtv create provider --name host --type openshift -n "${NS}"

echo "Waiting for providers..."
oc wait "provider.forklift.konveyor.io/${PROVIDER}" -n "${NS}" \
  --for=condition=Ready --timeout=300s
oc wait "provider.forklift.konveyor.io/host" -n "${NS}" \
  --for=condition=Ready --timeout=300s

echo "Providers ready."
echo ""

# ===================================================================
#  Tracking
# ===================================================================
FAILURES=""
SCENARIO_A_PASS=false
SCENARIO_B_PASS=false
SCENARIO_C_PASS=false
SCENARIO_D_PASS=false

# ===================================================================
#  SCENARIO A: Default template (empty pvcNameTemplate, generateName=true)
# ===================================================================
echo "=========================================="
echo "SCENARIO A: Default template (empty, with generateName suffix)"
echo "=========================================="
echo ""

set +e
(
  set -euo pipefail
  echo "Creating plan with no pvcNameTemplate..."
  oc mtv create plan --name "${PLAN_A}" \
    --source "${PROVIDER}" --target host --vms "${VM}" \
    --skip-guest-conversion --use-compatibility-mode=true -n "${NS}"
  start_plan_and_wait_for_pvcs "${PLAN_A}"
)
RC=$?; set -e

if [[ ${RC} -ne 0 ]]; then
  echo "SCENARIO A FAIL: No PVCs created"
  FAILURES="${FAILURES}  A: no PVCs created\n"
  cleanup_scenario "${PLAN_A}"
else
  PLAN_TRUNC=$(echo "${PLAN_A}" | cut -c1-15)
  run_scenario_check A "${PLAN_A}" "${PLAN_TRUNC}-"
fi

# ===================================================================
#  SCENARIO B: Custom template with .VmId
# ===================================================================
echo "=========================================="
echo "SCENARIO B: Custom PVC name template (.VmId)"
echo "=========================================="
echo ""

set +e
(
  set -euo pipefail
  echo "Creating plan with custom template '{{.PlanName}}-{{.VmId}}'..."
  oc mtv create plan --name "${PLAN_B}" \
    --source "${PROVIDER}" --target host --vms "${VM}" \
    --pvc-name-template '{{.PlanName}}-{{.VmId}}' \
    --skip-guest-conversion --use-compatibility-mode=true -n "${NS}"
  start_plan_and_wait_for_pvcs "${PLAN_B}"
)
RC=$?; set -e

if [[ ${RC} -ne 0 ]]; then
  echo "SCENARIO B FAIL: No PVCs created"
  FAILURES="${FAILURES}  B: no PVCs created\n"
  cleanup_scenario "${PLAN_B}"
else
  run_scenario_check B "${PLAN_B}" "${PLAN_B}-"
fi

# ===================================================================
#  SCENARIO C: Exact name (useGenerateName=false)
# ===================================================================
echo "=========================================="
echo "SCENARIO C: Exact name (useGenerateName=false)"
echo "=========================================="
echo ""

set +e
(
  set -euo pipefail
  echo "Creating plan with useGenerateName=false..."
  oc mtv create plan --name "${PLAN_C}" \
    --source "${PROVIDER}" --target host --vms "${VM}" \
    --skip-guest-conversion --use-compatibility-mode=true -n "${NS}"
  echo "Patching plan to set pvcNameTemplateUseGenerateName=false..."
  oc patch plan.forklift.konveyor.io/"${PLAN_C}" -n "${NS}" \
    --type=merge -p '{"spec":{"pvcNameTemplateUseGenerateName":false}}'
  sleep 5
  start_plan_and_wait_for_pvcs "${PLAN_C}"
)
RC=$?; set -e

if [[ ${RC} -ne 0 ]]; then
  echo "SCENARIO C FAIL: No PVCs created"
  FAILURES="${FAILURES}  C: no PVCs created\n"
  cleanup_scenario "${PLAN_C}"
else
  PLAN_TRUNC=$(echo "${PLAN_C}" | cut -c1-15)
  run_scenario_check C "${PLAN_C}" "${PLAN_TRUNC}-" --exact
fi

# ===================================================================
#  SCENARIO D: ForkliftController global template override
# ===================================================================
echo "=========================================="
echo "SCENARIO D: Global template override"
echo "=========================================="
echo ""

GLOBAL_TEMPLATE='{{trunc 10 .PlanName}}-global-{{.DiskIndex}}'
CONTROLLER_CR=$(get_controller_cr)

set +e
(
  set -euo pipefail
  echo "Setting global controller_pvc_name_template on ForkliftController/${CONTROLLER_CR}..."
  oc patch forkliftcontroller/"${CONTROLLER_CR}" -n konveyor-forklift \
    --type=merge -p "{\"spec\":{\"controller_pvc_name_template\":\"${GLOBAL_TEMPLATE}\"}}"

  echo "Restarting controller to pick up new setting..."
  local ctrl_pod
  ctrl_pod=$(oc get pods -n konveyor-forklift -l app=forklift-controller \
    --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null | head -1)
  if [[ -n "${ctrl_pod}" ]]; then
    oc delete pod "${ctrl_pod}" -n konveyor-forklift 2>/dev/null || true
  fi
  sleep 15
  oc wait pod -n konveyor-forklift -l app=forklift-controller \
    --for=condition=Ready --timeout=120s

  echo "Creating plan with no pvcNameTemplate (should use global)..."
  oc mtv create plan --name "${PLAN_D}" \
    --source "${PROVIDER}" --target host --vms "${VM}" \
    --skip-guest-conversion --use-compatibility-mode=true -n "${NS}"
  start_plan_and_wait_for_pvcs "${PLAN_D}"
)
RC=$?; set -e

echo "Reverting global template..."
oc patch forkliftcontroller/"${CONTROLLER_CR}" -n konveyor-forklift \
  --type=json -p '[{"op":"remove","path":"/spec/controller_pvc_name_template"}]' 2>/dev/null || true

if [[ ${RC} -ne 0 ]]; then
  echo "SCENARIO D FAIL: No PVCs created"
  FAILURES="${FAILURES}  D: no PVCs created\n"
  cleanup_scenario "${PLAN_D}"
else
  PLAN_TRUNC10=$(echo "${PLAN_D}" | cut -c1-10)
  run_scenario_check D "${PLAN_D}" "${PLAN_TRUNC10}-global-"
fi

# ===================================================================
#  Summary
# ===================================================================
echo ""
echo "=========================================="
echo "RESULTS"
echo "=========================================="
echo "  A (default template + suffix):  ${SCENARIO_A_PASS}"
echo "  B (custom .VmId):               ${SCENARIO_B_PASS}"
echo "  C (exact name, no suffix):      ${SCENARIO_C_PASS}"
echo "  D (global template override):   ${SCENARIO_D_PASS}"
echo ""

if [[ -z "${FAILURES}" ]]; then
  echo "TEST PASSED: MTV-6189 — All scenarios verified successfully"
  exit 0
else
  echo "TEST FAILED: MTV-6189 — One or more scenarios failed:"
  echo -e "${FAILURES}"
  exit 1
fi
