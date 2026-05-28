#!/bin/bash
#
# Test: MTV-3505 — VMware Serial Number Feature Flag
#
# Verifies that the feature_vmware_system_serial_number feature flag correctly
# controls whether the VMware-formatted system serial number is used.
#
# Prerequisites:
#   - oc CLI with mtv plugin installed
#   - MTV installed on the cluster
#
# Usage:
#   export GOVC_URL=10.6.46.248
#   export GOVC_USERNAME=admin@vsphere.local
#   export GOVC_PASSWORD=secret
#   export VM=yzamir-mtv-rhel8-79     # optional
#   export VDDK_IMAGE=<vddk-image>    # optional, only if not already configured
#   bash test-mtv-3505.sh

set -euo pipefail

# --- Configuration ---
VM="${VM:-yzamir-mtv-rhel8-79}"
CONTROLLER_NS="${CONTROLLER_NS:-konveyor-forklift}"
SKIP_CLEANUP="${SKIP_CLEANUP:-false}"

# --- Test constants ---
NS="mtv-3505-test"
PROVIDER="vsphere-provider"
PLAN_ENABLED="serial-enabled-plan"
PLAN_DISABLED="serial-disabled-plan"
POLL=15
MIGRATION_TIMEOUT=1800

# --- Cleanup ---
cleanup() {
  if [[ "${SKIP_CLEANUP}" == "true" ]]; then
    echo "SKIP_CLEANUP is set — leaving resources in place."
    return
  fi
  echo "Cleaning up..."
  oc mtv delete plan --name "${PLAN_ENABLED}" --skip-archive -n "${NS}" 2>/dev/null || true
  oc mtv delete plan --name "${PLAN_DISABLED}" --skip-archive -n "${NS}" 2>/dev/null || true
  oc mtv delete provider --name "${PROVIDER}" -n "${NS}" 2>/dev/null || true
  oc mtv delete provider --name host -n "${NS}" 2>/dev/null || true
  oc delete namespace "${NS}" --ignore-not-found 2>/dev/null || true
  oc mtv settings unset --setting feature_vmware_system_serial_number 2>/dev/null || true
  echo "Cleanup done."
}
trap cleanup EXIT

# Wait for migration
wait_for_migration() {
  local plan_name=$1
  echo "Waiting for migration to complete..."
  elapsed=0
  while (( elapsed < MIGRATION_TIMEOUT )); do
    sleep "${POLL}"
    elapsed=$(( elapsed + POLL ))

    if oc mtv get plan --name "${plan_name}" -n "${NS}" 2>&1 | grep -qi "Succeeded"; then
      echo "Migration succeeded."
      return 0
    fi
    if oc mtv get plan --name "${plan_name}" -n "${NS}" 2>&1 | grep -qiE "Failed|Canceled"; then
      echo "Migration failed or canceled."
      return 1
    fi

    echo "  still running... (${elapsed}s)"
  done

  echo "ERROR: Migration timed out."
  return 1
}

echo "=========================================="
echo "MTV-3505 Test"
echo "=========================================="

# --- Ensure VDDK image is set ---
CURRENT_VDDK=$(oc mtv settings get --setting vddk_image 2>/dev/null | tail -1 | awk '{print $NF}')
if [[ -z "${CURRENT_VDDK}" || "${CURRENT_VDDK}" == "(not" || "${CURRENT_VDDK}" == "<none>" ]]; then
  if [[ -z "${VDDK_IMAGE:-}" ]]; then
    echo "ERROR: VDDK image is not configured and VDDK_IMAGE env var is not set"
    exit 1
  fi
  echo "Setting VDDK image..."
  oc mtv settings set --setting vddk_image --value "${VDDK_IMAGE}"
fi

# Start fresh
cleanup

# --- Create namespace ---
echo "Creating namespace..."
oc create namespace "${NS}"

# --- Create providers ---
echo "Creating providers..."
oc mtv create provider \
  --name "${PROVIDER}" \
  --type vsphere \
  --url "https://${GOVC_URL}/sdk" \
  --username "${GOVC_USERNAME}" \
  --password "${GOVC_PASSWORD}" \
  --provider-insecure-skip-tls \
  -n "${NS}"

oc mtv create provider --name host --type openshift -n "${NS}"

echo "Waiting for providers..."
oc wait "provider.forklift.konveyor.io/${PROVIDER}" -n "${NS}" --for=condition=Ready --timeout=300s
oc wait "provider.forklift.konveyor.io/host" -n "${NS}" --for=condition=Ready --timeout=300s

echo ""
echo "=========================================="
echo "SCENARIO 1: Feature Enabled (Default)"
echo "=========================================="

# --- Create plan ---
echo "Creating plan..."
oc mtv create plan --name "${PLAN_ENABLED}" --source "${PROVIDER}" --vms "${VM}" -n "${NS}"

oc wait "plan.forklift.konveyor.io/${PLAN_ENABLED}" -n "${NS}" --for=condition=Ready --timeout=900s
sleep 2

# --- Start migration ---
echo "Starting migration..."
oc mtv start plan --name "${PLAN_ENABLED}" -n "${NS}"

# --- Wait for completion ---
if ! wait_for_migration "${PLAN_ENABLED}"; then
  echo "TEST FAILED: Migration did not complete."
  exit 1
fi

# --- Verify serial ---
echo "Checking serial number..."
SERIAL_ENABLED=$(oc get vm "${VM}" -n "${NS}" -o jsonpath='{.spec.template.spec.domain.firmware.serial}')
echo "Serial: ${SERIAL_ENABLED}"

if [[ "${SERIAL_ENABLED}" == VMware-* ]]; then
  echo "✓ PASS: Serial starts with 'VMware-'"
else
  echo "✗ FAIL: Serial does not start with 'VMware-'"
  exit 1
fi

# --- Clean up scenario 1 ---
echo "Cleaning up scenario 1..."
oc mtv delete plan --name "${PLAN_ENABLED}" --skip-archive -n "${NS}"
oc delete vm "${VM}" -n "${NS}"

echo ""
echo "=========================================="
echo "SCENARIO 2: Feature Disabled"
echo "=========================================="

# --- Disable feature ---
echo "Disabling feature..."
oc mtv settings set --setting feature_vmware_system_serial_number --value "false"

echo "Waiting for controller rollout..."
sleep 10
oc wait deployment/forklift-controller -n "${CONTROLLER_NS}" --for=condition=Available --timeout=300s

# --- Create plan ---
echo "Creating plan..."
oc mtv create plan --name "${PLAN_DISABLED}" --source "${PROVIDER}" --vms "${VM}" -n "${NS}"

oc wait "plan.forklift.konveyor.io/${PLAN_DISABLED}" -n "${NS}" --for=condition=Ready --timeout=900s
sleep 2

# --- Start migration ---
echo "Starting migration..."
oc mtv start plan --name "${PLAN_DISABLED}" -n "${NS}"

# --- Wait for completion ---
if ! wait_for_migration "${PLAN_DISABLED}"; then
  echo "TEST FAILED: Migration did not complete."
  exit 1
fi

# --- Verify serial ---
echo "Checking serial number..."
SERIAL_DISABLED=$(oc get vm "${VM}" -n "${NS}" -o jsonpath='{.spec.template.spec.domain.firmware.serial}')
echo "Serial: ${SERIAL_DISABLED}"

if [[ "${SERIAL_DISABLED}" != VMware-* ]]; then
  echo "✓ PASS: Serial does not start with 'VMware-'"
else
  echo "✗ FAIL: Serial starts with 'VMware-' when feature is disabled"
  exit 1
fi

# --- Summary ---
echo ""
echo "=========================================="
echo "TEST PASSED: MTV-3505"
echo "=========================================="
echo "Serial (enabled):  ${SERIAL_ENABLED}"
echo "Serial (disabled): ${SERIAL_DISABLED}"
exit 0
