#!/bin/bash
#
# E2E test for VMware serial number feature flag (MTV-3505).
#
# Verifies that the feature_vmware_system_serial_number feature flag correctly
# controls whether the VMware-formatted system serial number is used.
#
# Prerequisites: oc, oc mtv plugin, GOVC_URL, GOVC_USERNAME, GOVC_PASSWORD,
#   and a cluster with MTV installed.

set -euo pipefail

# --- Constants ---
NS="mtv-3505-test"
PROVIDER="vsphere-provider"
PLAN_ENABLED="serial-enabled-plan"
PLAN_DISABLED="serial-disabled-plan"
VM="${VM:-yzamir-mtv-rhel8-79}"
CONTROLLER_NS="${CONTROLLER_NS:-konveyor-forklift}"
SKIP_CLEANUP="${SKIP_CLEANUP:-false}"
MIGRATION_TIMEOUT=1800

# ===================================================================
#  Preflight: verify MTV is installed and VDDK is configured
# ===================================================================
echo "=========================================="
echo "MTV-3505 Test: VMware Serial Number Feature Flag"
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

VDDK_IMAGE_CURRENT=$(oc mtv settings get --setting vddk_image 2>/dev/null \
  | tail -1 | awk '{print $NF}')
if [[ -n "${VDDK_IMAGE_CURRENT}" && "${VDDK_IMAGE_CURRENT}" != "<none>" && "${VDDK_IMAGE_CURRENT}" != "VALUE" ]]; then
  echo "VDDK image configured: ${VDDK_IMAGE_CURRENT}"
elif [[ -n "${VDDK_IMAGE:-}" ]]; then
  echo "Setting VDDK image..."
  oc mtv settings set --setting vddk_image --value "${VDDK_IMAGE}"
else
  echo "ERROR: VDDK image not configured and VDDK_IMAGE env var not set."
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
  oc mtv delete plan     --name "${PLAN_ENABLED}" -n "${NS}"  2>/dev/null || true
  oc mtv delete plan     --name "${PLAN_DISABLED}" -n "${NS}" 2>/dev/null || true
  oc mtv delete provider --name "${PROVIDER}" -n "${NS}"      2>/dev/null || true
  oc mtv delete provider --name host -n "${NS}"               2>/dev/null || true
  oc delete namespace "${NS}" --ignore-not-found              2>/dev/null || true
  oc mtv settings unset --setting feature_vmware_system_serial_number 2>/dev/null || true
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
  oc delete vm "${VM}" -n "${NS}" --ignore-not-found  2>/dev/null || true
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
oc mtv create provider \
  --name "${PROVIDER}" \
  --type vsphere \
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
#  SCENARIO 1: Feature Enabled (Default)
# ===================================================================
echo "=========================================="
echo "SCENARIO 1: Feature Enabled (Default)"
echo "=========================================="
echo ""

echo "Creating plan..."
oc mtv create plan --name "${PLAN_ENABLED}" --source "${PROVIDER}" --vms "${VM}" -n "${NS}"

echo "Waiting for plan to be Ready..."
oc wait "plan.forklift.konveyor.io/${PLAN_ENABLED}" -n "${NS}" \
  --for=condition=Ready --timeout=900s

echo "Starting migration..."
oc mtv start plan --name "${PLAN_ENABLED}" -n "${NS}"

echo "Waiting for migration to complete..."
if ! oc wait "plan.forklift.konveyor.io/${PLAN_ENABLED}" -n "${NS}" \
  --for=condition=Succeeded --timeout="${MIGRATION_TIMEOUT}s"; then
  echo "TEST FAILED: Migration did not succeed within ${MIGRATION_TIMEOUT}s."
  exit 1
fi

echo "Checking serial number..."
SERIAL_ENABLED=$(oc get vm "${VM}" -n "${NS}" -o jsonpath='{.spec.template.spec.domain.firmware.serial}')
echo "Serial: ${SERIAL_ENABLED}"

if [[ "${SERIAL_ENABLED}" == VMware-* ]]; then
  echo "PASS: Serial starts with 'VMware-'"
else
  echo "FAIL: Serial does not start with 'VMware-'"
  exit 1
fi

echo "Cleaning up scenario 1..."
cleanup_scenario "${PLAN_ENABLED}"

# ===================================================================
#  SCENARIO 2: Feature Disabled
# ===================================================================
echo ""
echo "=========================================="
echo "SCENARIO 2: Feature Disabled"
echo "=========================================="
echo ""

echo "Disabling feature..."
oc mtv settings set --setting feature_vmware_system_serial_number --value "false"

echo "Waiting for controller rollout..."
sleep 10
oc wait deployment/forklift-controller -n "${CONTROLLER_NS}" \
  --for=condition=Available --timeout=300s

echo "Creating plan..."
oc mtv create plan --name "${PLAN_DISABLED}" --source "${PROVIDER}" --vms "${VM}" -n "${NS}"

echo "Waiting for plan to be Ready..."
oc wait "plan.forklift.konveyor.io/${PLAN_DISABLED}" -n "${NS}" \
  --for=condition=Ready --timeout=900s

echo "Starting migration..."
oc mtv start plan --name "${PLAN_DISABLED}" -n "${NS}"

echo "Waiting for migration to complete..."
if ! oc wait "plan.forklift.konveyor.io/${PLAN_DISABLED}" -n "${NS}" \
  --for=condition=Succeeded --timeout="${MIGRATION_TIMEOUT}s"; then
  echo "TEST FAILED: Migration did not succeed within ${MIGRATION_TIMEOUT}s."
  exit 1
fi

echo "Checking serial number..."
SERIAL_DISABLED=$(oc get vm "${VM}" -n "${NS}" -o jsonpath='{.spec.template.spec.domain.firmware.serial}')
echo "Serial: ${SERIAL_DISABLED}"

if [[ "${SERIAL_DISABLED}" != VMware-* ]]; then
  echo "PASS: Serial does not start with 'VMware-'"
else
  echo "FAIL: Serial starts with 'VMware-' when feature is disabled"
  exit 1
fi

# ===================================================================
#  Summary
# ===================================================================
echo ""
echo "=========================================="
echo "RESULT"
echo "=========================================="
echo "Serial (enabled):  ${SERIAL_ENABLED}"
echo "Serial (disabled): ${SERIAL_DISABLED}"
echo ""
echo "TEST PASSED: MTV-3505"
exit 0
