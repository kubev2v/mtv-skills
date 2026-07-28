#!/bin/bash
#
# E2E test for MTV-5723: Cleanup copied ConfigMaps after migration completes.
#
# Verifies that extra-v2v-conf, customization-scripts, and vddk-conf ConfigMaps
# copied to the target namespace are deleted when migration ends.

set -euo pipefail

# --- Constants ---
PROVIDER_NS="${PROVIDER_NS:-openshift-mtv}"
TARGET_NS="${TARGET_NS:-mtv-5723-test}"
PROVIDER_NAME="${PROVIDER_NAME:-vmware-7}"
VM_NAME="${VM_NAME:-mtv-feature-rhel7-2}"
PLAN_NAME="mtv-5723-plan"
CM_NAME="mtv-5723-scripts"
SKIP_CLEANUP="${SKIP_CLEANUP:-false}"
POLL=15

# ===================================================================
#  Preflight
# ===================================================================
echo "=========================================="
echo "MTV-5723 Test"
echo "=========================================="
echo ""
echo "Preflight: Checking MTV installation..."

if ! command -v oc &>/dev/null; then
  echo "ERROR: 'oc' CLI not found in PATH."
  exit 1
fi

oc get crd plans.forklift.konveyor.io >/dev/null 2>&1 || {
  echo "ERROR: MTV not installed on this cluster."
  exit 1
}

VDDK_IMAGE=$(oc mtv settings get --setting vddk_image 2>/dev/null | tr -d '[:space:]')
if [[ -n "${VDDK_IMAGE}" && "${VDDK_IMAGE}" != "<none>" && "${VDDK_IMAGE}" != "(notset)" ]]; then
  echo "VDDK image configured: ${VDDK_IMAGE}"
else
  echo "ERROR: VDDK image not configured."
  exit 1
fi

oc get provider "${PROVIDER_NAME}" -n "${PROVIDER_NS}" \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' | grep -q True || {
  echo "ERROR: Provider ${PROVIDER_NAME} not ready in ${PROVIDER_NS}"
  exit 1
}

echo "Preflight passed."
echo ""

# ===================================================================
#  Cleanup (also runs on error via trap)
# ===================================================================
cleanup() {
  if [[ "${SKIP_CLEANUP}" == "true" ]]; then
    echo "SKIP_CLEANUP=true -- preserving resources for forensic inspection."
    return 0
  fi
  echo "Cleaning up..."
  oc delete migration -n "${PROVIDER_NS}" -l plan="${PLAN_NAME}" --ignore-not-found 2>/dev/null || true
  oc delete plan "${PLAN_NAME}" -n "${PROVIDER_NS}" --ignore-not-found 2>/dev/null || true
  oc delete configmap "${CM_NAME}" -n "${PROVIDER_NS}" --ignore-not-found 2>/dev/null || true
  oc delete namespace "${TARGET_NS}" --ignore-not-found --wait=false 2>/dev/null || true
  echo "Cleanup done."
}
trap cleanup EXIT
cleanup

# ===================================================================
#  STEP 1: Create target namespace
# ===================================================================
echo ""
echo "=========================================="
echo "STEP 1: Creating target namespace"
echo "=========================================="
oc create namespace "${TARGET_NS}" --dry-run=client -o yaml | oc apply -f -
echo ""

# ===================================================================
#  STEP 2: Create customization-scripts ConfigMap in provider NS
# ===================================================================
echo "=========================================="
echo "STEP 2: Creating scripts ConfigMap in provider namespace (cross-namespace)"
echo "=========================================="
cat <<'EOF' | oc apply -n "${PROVIDER_NS}" -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: mtv-5723-scripts
data:
  01_linux_run_test.sh: |
    #!/bin/sh
    echo "MTV-5723 test script executed" > /tmp/mtv-5723-marker.txt
EOF
echo "ConfigMap '${CM_NAME}' created in '${PROVIDER_NS}'."
echo ""

# ===================================================================
#  STEP 3: Create migration plan with cross-namespace customizationScripts
# ===================================================================
echo "=========================================="
echo "STEP 3: Creating migration plan"
echo "=========================================="
oc mtv create plan "${PLAN_NAME}" \
  --namespace "${PROVIDER_NS}" \
  --source "${PROVIDER_NAME}" \
  --target host \
  --target-namespace "${TARGET_NS}" \
  --vms "${VM_NAME}" \
  --customization-scripts "${PROVIDER_NS}/${CM_NAME}" 2>&1

echo "Waiting for plan to become Ready..."
oc wait plan "${PLAN_NAME}" -n "${PROVIDER_NS}" --for=condition=Ready --timeout=120s 2>&1
echo "Plan ready."
echo ""

# ===================================================================
#  STEP 4: Start migration and wait for completion
# ===================================================================
echo "=========================================="
echo "STEP 4: Starting migration"
echo "=========================================="
oc mtv start plan --name "${PLAN_NAME}" --namespace "${PROVIDER_NS}" 2>&1

echo "Waiting for migration to complete..."
TIMEOUT=900
if ! oc wait "plan.forklift.konveyor.io/${PLAN_NAME}" -n "${PROVIDER_NS}" \
  --for=condition=Succeeded --timeout="${TIMEOUT}s"; then
  echo "TEST FAILED: Migration did not succeed within ${TIMEOUT}s."
  oc get plan "${PLAN_NAME}" -n "${PROVIDER_NS}" \
    -o jsonpath='{.status.migration.vms[0].phase}' 2>/dev/null || true
  exit 1
fi
echo "Migration completed successfully."
echo ""

# ===================================================================
#  STEP 5: Verify copied ConfigMaps were cleaned up
# ===================================================================
echo "=========================================="
echo "STEP 5: Verifying copied ConfigMaps are deleted from target namespace"
echo "=========================================="

# Allow a few seconds for the controller to run cleanup
sleep 10

CUST_CM="${PLAN_NAME}-customization-scripts"
EXTRA_CM="${PLAN_NAME}-extra-v2v-conf"
FAIL=false

echo "Checking for '${CUST_CM}' in '${TARGET_NS}'..."
if oc get configmap "${CUST_CM}" -n "${TARGET_NS}" >/dev/null 2>&1; then
  echo "FAIL: '${CUST_CM}' still exists in '${TARGET_NS}'"
  FAIL=true
else
  echo "OK: '${CUST_CM}' not found (cleaned up)."
fi

echo "Checking for '${EXTRA_CM}' in '${TARGET_NS}'..."
if oc get configmap "${EXTRA_CM}" -n "${TARGET_NS}" >/dev/null 2>&1; then
  echo "FAIL: '${EXTRA_CM}' still exists in '${TARGET_NS}'"
  FAIL=true
else
  echo "OK: '${EXTRA_CM}' not found (cleaned up)."
fi

echo "Checking for vddk-conf ConfigMaps by label in '${TARGET_NS}'..."
VDDK_CMS=$(oc get configmap -n "${TARGET_NS}" -l use=vddk-conf \
  --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null || true)
if [[ -n "${VDDK_CMS}" ]]; then
  echo "FAIL: vddk-conf ConfigMap(s) still exist: ${VDDK_CMS}"
  FAIL=true
else
  echo "OK: No vddk-conf ConfigMaps found (cleaned up)."
fi

echo ""

# ===================================================================
#  RESULT
# ===================================================================
echo "=========================================="
echo "RESULT"
echo "=========================================="

if [[ "${FAIL}" == "true" ]]; then
  echo "Remaining ConfigMaps in target namespace:"
  oc get configmap -n "${TARGET_NS}" 2>&1 || true
  echo ""
  echo "TEST FAILED: MTV-5723 — copied ConfigMaps were NOT cleaned up"
  exit 1
fi

echo "All copied ConfigMaps deleted from '${TARGET_NS}' after migration completion."
echo ""
echo "TEST PASSED: MTV-5723"
exit 0
