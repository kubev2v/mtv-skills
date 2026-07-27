#!/bin/bash
#
# E2E test for MTV-5548: Retain failed populator pods for debugging.
#
# Verifies that FEATURE_RETAIN_POPULATOR_PODS prevents the populator-controller
# from deleting the target PVC (and thus the pod via OwnerReference GC) when a
# vSphere xcopy populator pod fails.
#
# Prerequisites: oc, oc mtv plugin, and a cluster with MTV installed.
#
# Environment variables:
#   ECO_VSPHERE_PROVIDER  - vSphere provider URL (e.g. https://vcenter.example.com/sdk)
#   ECO_VSPHERE_USERNAME  - vSphere username
#   ECO_VSPHERE_PASSWORD  - vSphere password
#   ECO_VSPHERE_VDDK      - VDDK init image
#   ECO_NETAPP_SVM        - NetApp ONTAP SVM name
#   ECO_NETAPP_HOST       - NetApp storage hostname
#   ECO_NETAPP_USERNAME   - NetApp username
#   ECO_NETAPP_PASSWORD   - NetApp password (used only in working-secret scenario)
#   VM                    - VM name to migrate (default: tshefi_40G)
#   STORAGE_PAIRS         - storage mapping pairs (default: eco-iscsi-ds3:rhos-san-economy-iscsi)
#   SKIP_CLEANUP          - set to "true" to preserve resources (default: false)

set -euo pipefail

# --- Constants ---
NS="mtv-5548-test"
PROVIDER="eco-vsphere"
SECRET="ontap-rhosqe"
PLAN_A="mtv-5548-plan-a"
PLAN_B="mtv-5548-plan-b"
VM="${VM:-tshefi_40G}"
STORAGE_PAIRS="${STORAGE_PAIRS:-eco-iscsi-ds3:rhos-san-economy-iscsi}"
SKIP_CLEANUP="${SKIP_CLEANUP:-false}"
POLL=10
MAX_WAIT=300

# ===================================================================
#  Preflight
# ===================================================================
echo "=========================================="
echo "MTV-5548 Test"
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
echo "MTV controller found. Preflight passed."
echo ""

# ===================================================================
#  Cleanup
# ===================================================================
cleanup() {
  if [[ "${SKIP_CLEANUP}" == "true" ]]; then
    echo "SKIP_CLEANUP=true -- preserving resources in namespace '${NS}'."
    oc mtv settings set --setting controller_retain_populator_pods --value false 2>/dev/null || true
    return 0
  fi
  echo "Cleaning up..."
  oc mtv settings set --setting controller_retain_populator_pods --value false 2>/dev/null || true
  oc delete namespace "${NS}" --ignore-not-found --wait=false 2>/dev/null || true
  echo "Cleanup done."
}
trap cleanup EXIT
cleanup

# ===================================================================
#  Helpers
# ===================================================================
wait_for_populator_pod() {
  local elapsed=0
  while [[ ${elapsed} -lt ${MAX_WAIT} ]]; do
    local pods
    pods=$(oc get pods -n "${NS}" --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null \
      | grep "^populate-" || true)
    if [[ -n "${pods}" ]]; then
      echo "${pods}"
      return 0
    fi
    sleep "${POLL}"; elapsed=$((elapsed + POLL))
  done
  echo ""
  return 1
}

wait_for_pod_terminal() {
  local pod_name="$1"
  local elapsed=0
  while [[ ${elapsed} -lt ${MAX_WAIT} ]]; do
    local phase
    phase=$(oc get pod "${pod_name}" -n "${NS}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Gone")
    if [[ "${phase}" == "Failed" || "${phase}" == "Succeeded" || "${phase}" == "Gone" ]]; then
      echo "${phase}"
      return 0
    fi
    sleep "${POLL}"; elapsed=$((elapsed + POLL))
  done
  echo "TIMEOUT"
  return 1
}

cleanup_scenario() {
  local plan_name="$1"
  oc mtv delete plan --name "${plan_name}" -n "${NS}" 2>/dev/null || true
  oc delete vm "${VM}" -n "${NS}" --ignore-not-found 2>/dev/null || true
  oc delete secret "${SECRET}" -n "${NS}" --ignore-not-found 2>/dev/null || true
  sleep 5
  oc delete pvc --all -n "${NS}" --wait=false 2>/dev/null || true
  oc delete dv --all -n "${NS}" --wait=false 2>/dev/null || true
  sleep 5
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
  --url "${ECO_VSPHERE_PROVIDER}" \
  --username "${ECO_VSPHERE_USERNAME}" \
  --password "${ECO_VSPHERE_PASSWORD}" \
  --vddk-init-image "${ECO_VSPHERE_VDDK}" \
  --provider-insecure-skip-tls \
  -n "${NS}"

echo "Creating OpenShift provider..."
oc mtv create provider --name host --type openshift -n "${NS}"

echo "Waiting for providers (large vSphere inventories may take 30+ min)..."
oc wait "provider.forklift.konveyor.io/${PROVIDER}" -n "${NS}" \
  --for=condition=Ready --timeout=1800s
oc wait "provider.forklift.konveyor.io/host" -n "${NS}" \
  --for=condition=Ready --timeout=300s

echo "Providers ready."
echo ""

# ===================================================================
#  SCENARIO A: Retain enabled — pod survives failure
# ===================================================================
FAILURES=""
SCENARIO_A_PASS=false

echo "=========================================="
echo "SCENARIO A: Retain ENABLED"
echo "=========================================="

echo "Enabling controller_retain_populator_pods..."
oc mtv settings set --setting controller_retain_populator_pods --value true
sleep 10

set +e
(
  set -euo pipefail

  echo ""
  echo "STEP 3: Create offload secret (bad password)..."
  oc create secret generic "${SECRET}" \
    --from-literal=ONTAP_SVM="${ECO_NETAPP_SVM}" \
    --from-literal=STORAGE_HOSTNAME="${ECO_NETAPP_HOST}" \
    --from-literal=STORAGE_USERNAME="${ECO_NETAPP_USERNAME}" \
    --from-literal=STORAGE_PASSWORD="RE9FU05UIFdPUks=" \
    -n "${NS}"

  echo ""
  echo "STEP 4: Create migration plan (scenario A)..."
  oc mtv create plan --name "${PLAN_A}" --source "${PROVIDER}" \
    --vms "${VM}" \
    --default-offload-plugin vsphere \
    --default-offload-secret "${SECRET}" \
    --default-offload-vendor ontap \
    --default-target-storage-class trident-storage-class \
    --storage-pairs "${STORAGE_PAIRS}" \
    -n "${NS}"

  echo "Waiting for plan..."
  oc wait "plan.forklift.konveyor.io/${PLAN_A}" -n "${NS}" \
    --for=condition=Ready --timeout=300s
  echo "Plan ready."

  echo ""
  echo "STEP 5: Start migration (scenario A)..."
  oc mtv start plan --name "${PLAN_A}" -n "${NS}"

  echo "Waiting for populator pod to appear..."
  POD_NAME=$(wait_for_populator_pod)
  if [[ -z "${POD_NAME}" ]]; then
    echo "ERROR: No populator pod appeared within ${MAX_WAIT}s."
    exit 1
  fi
  echo "Populator pod found: ${POD_NAME}"

  echo "Waiting for pod to reach terminal state..."
  POD_PHASE=$(wait_for_pod_terminal "${POD_NAME}")
  echo "Pod phase: ${POD_PHASE}"

  echo ""
  echo "STEP 6: Verify pod and PVC retained..."

  POD_EXISTS=$(oc get pod "${POD_NAME}" -n "${NS}" --no-headers 2>/dev/null || true)
  if [[ -z "${POD_EXISTS}" ]]; then
    echo "FAIL: Populator pod '${POD_NAME}' was deleted despite retain flag!"
    exit 1
  fi
  echo "PASS: Populator pod '${POD_NAME}' still exists."

  PVC_COUNT=$(oc get pvc -n "${NS}" --no-headers 2>/dev/null | wc -l)
  if [[ "${PVC_COUNT}" -eq 0 ]]; then
    echo "FAIL: No PVCs found -- PVC was deleted despite retain flag!"
    exit 1
  fi
  echo "PASS: PVC(s) still present (${PVC_COUNT} found)."

  echo "Pod logs (for debugging reference):"
  oc logs "${POD_NAME}" -n "${NS}" --tail=20 2>/dev/null || echo "(could not fetch logs)"
)
SCENARIO_A_RC=$?
set -e

if [[ ${SCENARIO_A_RC} -ne 0 ]]; then
  echo "SCENARIO A FAIL"
  FAILURES="${FAILURES}  A: populator pod/PVC not retained with flag enabled\n"
else
  SCENARIO_A_PASS=true
  echo "SCENARIO A PASS"
fi

echo ""
echo "Cleaning up scenario A..."
cleanup_scenario "${PLAN_A}"

# ===================================================================
#  SCENARIO B: Retain disabled — pod is cleaned up
# ===================================================================
SCENARIO_B_PASS=false

echo "=========================================="
echo "SCENARIO B: Retain DISABLED (default)"
echo "=========================================="

echo "Disabling controller_retain_populator_pods..."
oc mtv settings set --setting controller_retain_populator_pods --value false
sleep 10

set +e
(
  set -euo pipefail

  echo ""
  echo "STEP 7: Create offload secret (bad password)..."
  oc create secret generic "${SECRET}" \
    --from-literal=ONTAP_SVM="${ECO_NETAPP_SVM}" \
    --from-literal=STORAGE_HOSTNAME="${ECO_NETAPP_HOST}" \
    --from-literal=STORAGE_USERNAME="${ECO_NETAPP_USERNAME}" \
    --from-literal=STORAGE_PASSWORD="RE9FU05UIFdPUks=" \
    -n "${NS}"

  echo ""
  echo "STEP 8: Create migration plan (scenario B)..."
  oc mtv create plan --name "${PLAN_B}" --source "${PROVIDER}" \
    --vms "${VM}" \
    --default-offload-plugin vsphere \
    --default-offload-secret "${SECRET}" \
    --default-offload-vendor ontap \
    --default-target-storage-class trident-storage-class \
    --storage-pairs "${STORAGE_PAIRS}" \
    -n "${NS}"

  echo "Waiting for plan..."
  oc wait "plan.forklift.konveyor.io/${PLAN_B}" -n "${NS}" \
    --for=condition=Ready --timeout=300s
  echo "Plan ready."

  echo ""
  echo "STEP 9: Start migration (scenario B)..."
  oc mtv start plan --name "${PLAN_B}" -n "${NS}"

  echo "Waiting for populator pod to appear..."
  POD_NAME=$(wait_for_populator_pod)
  if [[ -z "${POD_NAME}" ]]; then
    echo "ERROR: No populator pod appeared within ${MAX_WAIT}s."
    exit 1
  fi
  echo "Populator pod found: ${POD_NAME}"

  echo "Waiting for pod to reach terminal state..."
  POD_PHASE=$(wait_for_pod_terminal "${POD_NAME}")
  echo "Pod phase: ${POD_PHASE}"

  echo "Waiting 30s for populator-controller to delete PVC (and GC the pod)..."
  sleep 30

  echo ""
  echo "STEP 10: Verify pod and PVC are gone..."

  POD_EXISTS=$(oc get pod "${POD_NAME}" -n "${NS}" --no-headers 2>/dev/null || true)
  if [[ -n "${POD_EXISTS}" ]]; then
    echo "FAIL: Populator pod '${POD_NAME}' still exists with retain disabled!"
    exit 1
  fi
  echo "PASS: Populator pod '${POD_NAME}' was deleted."

  PVC_COUNT=$(oc get pvc -n "${NS}" --no-headers 2>/dev/null | wc -l)
  if [[ "${PVC_COUNT}" -gt 0 ]]; then
    echo "FAIL: PVC(s) still present (${PVC_COUNT}) with retain disabled!"
    exit 1
  fi
  echo "PASS: PVCs deleted."
)
SCENARIO_B_RC=$?
set -e

if [[ ${SCENARIO_B_RC} -ne 0 ]]; then
  echo "SCENARIO B FAIL"
  FAILURES="${FAILURES}  B: populator pod/PVC not cleaned up with flag disabled\n"
else
  SCENARIO_B_PASS=true
  echo "SCENARIO B PASS"
fi

# ===================================================================
#  Summary
# ===================================================================
echo ""
echo "=========================================="
echo "RESULTS"
echo "=========================================="
echo "  A (retain enabled):  ${SCENARIO_A_PASS}"
echo "  B (retain disabled): ${SCENARIO_B_PASS}"
echo ""

if [[ -z "${FAILURES}" ]]; then
  echo "TEST PASSED: MTV-5548"
  exit 0
else
  echo "TEST FAILED:"
  echo -e "${FAILURES}"
  exit 1
fi
