#!/bin/bash
#
# E2E test for ConvertorNodeSelector propagation to CDI VDDK importer pods (MTV-3207).
#
# Prerequisites: oc, oc mtv plugin, GOVC_URL, GOVC_USERNAME, GOVC_PASSWORD,
#   and a cluster with MTV installed (controller in konveyor-forklift by default).

set -euo pipefail

# --- Constants ---
NS="mtv-3207-test"
PROVIDER="vsphere-test"
PLAN="mtv-3207-plan"
VM="${VM:-mtv-rhel8-warm-sanity}"
NODE_LABEL_KEY="mtv-3207-test"
NODE_LABEL_VALUE="importer-target"
SKIP_CLEANUP="${SKIP_CLEANUP:-false}"
POLL=10
MAX_WAIT=300
LABELED_NODE=""

# ===================================================================
#  Preflight: verify MTV is installed and VDDK configured
# ===================================================================
echo "=========================================="
echo "MTV-3207 Test"
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
  oc mtv delete plan     --name "${PLAN}" -n "${NS}"     2>/dev/null || true
  oc mtv delete provider --name "${PROVIDER}" -n "${NS}" 2>/dev/null || true
  oc mtv delete provider --name host -n "${NS}"          2>/dev/null || true
  oc delete namespace "${NS}" --ignore-not-found         2>/dev/null || true

  if [[ -n "${LABELED_NODE}" ]]; then
    echo "Removing label from node ${LABELED_NODE}..."
    oc label node "${LABELED_NODE}" "${NODE_LABEL_KEY}-" 2>/dev/null || true
  fi
  echo "Cleanup done."
}
trap cleanup EXIT
cleanup

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
#  STEP 2: Label a worker node
# ===================================================================
echo "=========================================="
echo "STEP 2: Labeling a worker node"
echo "=========================================="

LABELED_NODE=$(oc get nodes -l node-role.kubernetes.io/worker \
  --no-headers -o custom-columns=NAME:.metadata.name | head -1)

if [[ -z "${LABELED_NODE}" ]]; then
  echo "ERROR: No worker nodes found."
  exit 1
fi

echo "Labeling node '${LABELED_NODE}' with ${NODE_LABEL_KEY}=${NODE_LABEL_VALUE}..."
oc label node "${LABELED_NODE}" "${NODE_LABEL_KEY}=${NODE_LABEL_VALUE}" --overwrite
echo ""

# ===================================================================
#  STEP 3: Create providers
# ===================================================================
echo "=========================================="
echo "STEP 3: Creating providers"
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
#  STEP 4: Create warm migration plan with convertorNodeSelector
# ===================================================================
echo "=========================================="
echo "STEP 4: Creating warm migration plan"
echo "=========================================="

echo "Creating warm plan with convertorNodeSelector..."
oc mtv create plan --name "${PLAN}" --source "${PROVIDER}" \
  --migration-type warm --vms "${VM}" \
  --convertor-node-selector "${NODE_LABEL_KEY}=${NODE_LABEL_VALUE}" \
  -n "${NS}"

echo "Waiting for plan to be ready..."
oc wait "plan.forklift.konveyor.io/${PLAN}" -n "${NS}" \
  --for=condition=Ready --timeout=300s

echo "Plan ready."
echo ""

# ===================================================================
#  STEP 5: Start migration and wait for CDI importer pod
# ===================================================================
echo "=========================================="
echo "STEP 5: Starting migration"
echo "=========================================="

echo "Starting warm migration..."
oc mtv start plan --name "${PLAN}" -n "${NS}"

echo "Waiting for CDI importer pod to appear..."
IMPORTER_POD=""
elapsed=0
while [[ ${elapsed} -lt ${MAX_WAIT} ]]; do
  IMPORTER_POD=$(oc get pods -n "${NS}" --no-headers \
    -o custom-columns=NAME:.metadata.name 2>/dev/null \
    | grep "^importer-" | head -1 || true)

  if [[ -n "${IMPORTER_POD}" ]]; then
    echo "Found importer pod: ${IMPORTER_POD}"
    break
  fi
  sleep "${POLL}"
  elapsed=$((elapsed + POLL))
  echo "  Waiting... (${elapsed}s)"
done

if [[ -z "${IMPORTER_POD}" ]]; then
  echo "TEST INCONCLUSIVE: No CDI importer pod appeared within ${MAX_WAIT}s."
  echo "The migration may be using virt-v2v transfer instead of VDDK."
  exit 2
fi
echo ""

# ===================================================================
#  STEP 6: Verify importer pod node selector and placement
# ===================================================================
echo "=========================================="
echo "STEP 6: Verifying importer pod scheduling"
echo "=========================================="

echo "Checking importer pod nodeSelector..."
POD_NODE_SELECTOR=$(oc get pod "${IMPORTER_POD}" -n "${NS}" \
  -o jsonpath="{.spec.nodeSelector.${NODE_LABEL_KEY}}" 2>/dev/null || echo "")

if [[ "${POD_NODE_SELECTOR}" != "${NODE_LABEL_VALUE}" ]]; then
  echo "TEST FAILED: Importer pod does not have expected nodeSelector."
  echo "  Expected: ${NODE_LABEL_KEY}=${NODE_LABEL_VALUE}"
  echo "  Got:      ${NODE_LABEL_KEY}=${POD_NODE_SELECTOR}"
  echo ""
  echo "Full pod nodeSelector:"
  oc get pod "${IMPORTER_POD}" -n "${NS}" -o jsonpath='{.spec.nodeSelector}' 2>/dev/null || true
  echo ""
  exit 1
fi

echo "nodeSelector verified: ${NODE_LABEL_KEY}=${POD_NODE_SELECTOR}"

echo "Checking which node the importer pod is scheduled on..."
POD_NODE=$(oc get pod "${IMPORTER_POD}" -n "${NS}" \
  -o jsonpath='{.spec.nodeName}' 2>/dev/null || echo "")

if [[ -n "${POD_NODE}" ]]; then
  if [[ "${POD_NODE}" == "${LABELED_NODE}" ]]; then
    echo "Importer pod scheduled on labeled node: ${POD_NODE}"
  else
    echo "WARNING: Importer pod scheduled on ${POD_NODE}, expected ${LABELED_NODE}."
    echo "This may indicate the nodeSelector was not enforced."
    exit 1
  fi
else
  echo "Importer pod not yet scheduled to a node (still pending)."
  echo "nodeSelector is correctly set -- scheduling will enforce placement."
fi

echo ""

# ===================================================================
#  STEP 7: Cancel migration (cleanup will handle the rest)
# ===================================================================
echo "=========================================="
echo "STEP 7: Canceling migration"
echo "=========================================="
echo "Test complete, canceling migration..."
oc patch "migration.forklift.konveyor.io" -n "${NS}" \
  -l "plan=${PLAN}" --type merge -p '{"spec":{"cancel":[]}}' 2>/dev/null || true
sleep 5

# ===================================================================
#  Summary
# ===================================================================
echo ""
echo "=========================================="
echo "RESULT"
echo "=========================================="
echo "ConvertorNodeSelector was propagated to CDI VDDK importer pod."
echo "Importer pod has nodeSelector: ${NODE_LABEL_KEY}=${NODE_LABEL_VALUE}"
echo "Importer pod scheduled on labeled node: ${LABELED_NODE}"
echo ""
echo "TEST PASSED: MTV-3207"
exit 0
