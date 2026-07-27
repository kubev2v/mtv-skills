#!/bin/bash
#
# E2E test for Azure VM migration (MTV-5926-B).
#
# Migrates a VM from Azure to OpenShift Virtualization and waits for the
# VirtualMachineInstance to reach Running state.
#
# Prerequisites:
#   - oc, oc mtv plugin
#   - AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID, AZURE_CLIENT_ID, AZURE_CLIENT_SECRET
#   - Azure resource group and VM already created
#     (see ~/demo-azure/mtv-5926/setup.sh)

set -euo pipefail

# --- Parse flags ---
AUTO_YES=false
for arg in "$@"; do
  case "$arg" in
    --yes) AUTO_YES=true ;;
  esac
done

pause() {
  if [[ "${AUTO_YES}" == "true" ]]; then
    return 0
  fi
  echo ""
  read -r -p "Press Enter to continue (or Ctrl-C to abort)... "
  echo ""
}

# --- Configuration ---
NS="mtv-5926-test-b"
PROVIDER="azure-test"
RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-mtv-5926-test-rg}"
VM_NAME="${AZURE_VM_NAME:-test-vm-5926}"
PLAN_NAME="azure-migration-test"
SKIP_CLEANUP="${SKIP_CLEANUP:-false}"
MIGRATION_TIMEOUT="${MIGRATION_TIMEOUT:-1200s}"

# ===================================================================
#  Preflight
# ===================================================================
echo "=========================================="
echo "MTV-5926 Test B: Azure VM Migration"
echo "=========================================="
echo ""
echo "Preflight: Checking tools..."

oc get crd providers.forklift.konveyor.io &>/dev/null
echo "  MTV controller: OK"

for var in AZURE_TENANT_ID AZURE_SUBSCRIPTION_ID AZURE_CLIENT_ID AZURE_CLIENT_SECRET; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: ${var} is not set."
    exit 1
  fi
done
echo "  Azure credentials: OK"
echo ""
echo "Resource Group:     ${RESOURCE_GROUP}"
echo "VM Name:            ${VM_NAME}"
echo "Migration timeout:  ${MIGRATION_TIMEOUT}"
echo ""

echo "Checking Azure VM power state..."
VM_STATE=$(az vm get-instance-view --resource-group "${RESOURCE_GROUP}" --name "${VM_NAME}" \
  --query "instanceView.statuses[?starts_with(code,'PowerState/')].displayStatus" -o tsv)
echo "  VM power state: ${VM_STATE}"
if [[ "${VM_STATE}" != "VM running" ]]; then
  echo "  VM is not running. Starting VM..."
  az vm start --resource-group "${RESOURCE_GROUP}" --name "${VM_NAME}"
  echo "  VM started."
fi

echo ""
echo "Preflight passed."
pause

# ===================================================================
#  Cleanup (runs on exit)
# ===================================================================
cleanup() {
  if [[ "${SKIP_CLEANUP}" == "true" ]]; then
    echo "SKIP_CLEANUP=true -- preserving OCP resources in namespace '${NS}'."
    return 0
  fi
  echo ""
  echo "Cleaning up OCP resources..."
  oc mtv delete plan --name "${PLAN_NAME}" -n "${NS}" 2>/dev/null || true
  oc mtv delete provider --name "${PROVIDER}" -n "${NS}" 2>/dev/null || true
  oc delete vm "${VM_NAME}" -n "${NS}" --ignore-not-found 2>/dev/null || true
  oc delete namespace "${NS}" --ignore-not-found 2>/dev/null || true
  echo "Cleanup done."
}
trap cleanup EXIT
cleanup

# ===================================================================
#  STEP 1: Create OCP namespace + providers
# ===================================================================
echo "=========================================="
echo "STEP 1: Creating OCP namespace and providers"
echo "=========================================="

oc create namespace "${NS}" --dry-run=client -o yaml | oc apply -f -

echo "Creating Azure provider..."
oc mtv create provider --name "${PROVIDER}" --type azure \
  --azure-tenant-id "${AZURE_TENANT_ID}" \
  --azure-subscription-id "${AZURE_SUBSCRIPTION_ID}" \
  --azure-client-id "${AZURE_CLIENT_ID}" \
  --azure-client-secret "${AZURE_CLIENT_SECRET}" \
  --azure-resource-group "${RESOURCE_GROUP}" \
  -n "${NS}"

echo "Creating OpenShift provider..."
oc mtv create provider --name host --type openshift -n "${NS}"

echo "Waiting for providers..."
oc wait "provider.forklift.konveyor.io/${PROVIDER}" -n "${NS}" \
  --for=condition=Ready --timeout=300s
oc wait "provider.forklift.konveyor.io/host" -n "${NS}" \
  --for=condition=Ready --timeout=120s

echo "Providers ready."
pause

# ===================================================================
#  STEP 2: Verify VM exists in inventory
# ===================================================================
echo "=========================================="
echo "STEP 2: Verifying VM in inventory"
echo "=========================================="

oc mtv get inventory vm --provider "${PROVIDER}" -n "${NS}" \
  | grep -q "${VM_NAME}" \
  || { echo "ERROR: VM '${VM_NAME}' not found in inventory."; exit 1; }

echo "VM '${VM_NAME}' found in inventory."
pause

# ===================================================================
#  STEP 3: Create migration plan
# ===================================================================
echo "=========================================="
echo "STEP 3: Creating migration plan"
echo "=========================================="
echo "Creating plan..."
oc mtv create plan --name "${PLAN_NAME}" \
  --source "${PROVIDER}" \
  --target host \
  --vms "${VM_NAME}" \
  -n "${NS}"

echo "Waiting for plan to become ready..."
oc wait "plan.forklift.konveyor.io/${PLAN_NAME}" -n "${NS}" \
  --for=condition=Ready --timeout=120s

echo "Plan ready."
pause

# ===================================================================
#  STEP 4: Start migration
# ===================================================================
echo "=========================================="
echo "STEP 4: Starting migration"
echo "=========================================="
oc mtv start plan --name "${PLAN_NAME}" -n "${NS}"
echo "Migration started."
pause

# ===================================================================
#  STEP 5: Wait for migration to complete
# ===================================================================
echo "=========================================="
echo "STEP 5: Waiting for migration to complete"
echo "=========================================="
echo "(timeout: ${MIGRATION_TIMEOUT})"

oc wait "plan.forklift.konveyor.io/${PLAN_NAME}" -n "${NS}" \
  --for=condition=Succeeded --timeout="${MIGRATION_TIMEOUT}"

echo "Migration completed."
pause

# ===================================================================
#  STEP 6: Verify VM is running on OpenShift
# ===================================================================
echo "=========================================="
echo "STEP 6: Verifying VM on OpenShift"
echo "=========================================="

echo "Waiting for VirtualMachineInstance to appear..."
oc wait "vmi/${VM_NAME}" -n "${NS}" --for=create --timeout=300s

echo "Waiting for VirtualMachineInstance to reach Running phase..."
oc wait "vmi/${VM_NAME}" -n "${NS}" \
  --for=jsonpath='{.status.phase}'=Running --timeout=300s

echo "VMI '${VM_NAME}' is Running."

echo ""
echo "VM details:"
oc get vm "${VM_NAME}" -n "${NS}" -o wide 2>/dev/null || true
oc get vmi "${VM_NAME}" -n "${NS}" -o wide 2>/dev/null || true
echo ""

# ===================================================================
#  Summary
# ===================================================================
echo "=========================================="
echo "RESULT"
echo "=========================================="
echo "Azure VM '${VM_NAME}' migrated and running on OpenShift."
echo "Resource Group: ${RESOURCE_GROUP}"
echo ""
echo "TEST PASSED: MTV-5926-B"
exit 0
