#!/bin/bash
#
# Test: MTV-4911 - BlockerGracePeriod
#
# Verifies that a migration survives a transient provider outage within
# the 5-minute grace window and completes successfully after the provider
# is restored.
#
# Prerequisites:
#   - oc CLI with mtv plugin installed
#   - MTV installed on the cluster
#
# Usage:
#   export GOVC_URL=https://vcenter.example.com
#   export GOVC_USERNAME=admin@vsphere.local
#   export GOVC_PASSWORD=secret
#   export VM=my-rhel8-vm                # optional
#   export CONTROLLER_NS=konveyor-forklift  # optional
#   export FIXED_IMAGE=quay.io/yaacov/forklift-controller:mtv-4911-01-amd64  # optional
#   export OUTAGE_WAIT=120               # optional, seconds to keep provider broken
#   export COMPLETE_WAIT=3600            # optional, migration timeout in seconds
#   export SKIP_CLEANUP=true             # optional, preserve resources after test
#   bash test-mtv-4911.sh

set -euo pipefail

# --- Configuration (override via environment) ---
VM="${VM:-mtv-rhel8-sanity}"
CONTROLLER_NS="${CONTROLLER_NS:-konveyor-forklift}"
FIXED_IMAGE="${FIXED_IMAGE:-quay.io/yaacov/forklift-controller:mtv-4911-01-amd64}"
OUTAGE_WAIT="${OUTAGE_WAIT:-120}"
COMPLETE_WAIT="${COMPLETE_WAIT:-3600}"
SKIP_CLEANUP="${SKIP_CLEANUP:-false}"

# --- Test constants ---
NS="grace-period-test"
PROVIDER="vsphere-test"
PLAN="grace-period-plan"
REAL_URL="${GOVC_URL}/sdk"
BROKEN_URL="https://1.2.3.4/sdk"
POLL=15

# --- Cleanup ---
cleanup() {
  if [[ "${SKIP_CLEANUP}" == "true" ]]; then
    echo "SKIP_CLEANUP is set -- leaving resources in place."
    return
  fi
  echo "Cleaning up..."
  oc mtv delete plan     --name "${PLAN}" -n "${NS}" 2>/dev/null || true
  oc mtv delete provider --name "${PROVIDER}" -n "${NS}"            2>/dev/null || true
  oc mtv delete provider --name host -n "${NS}"                     2>/dev/null || true
  oc delete namespace "${NS}" --ignore-not-found                    2>/dev/null || true

  # Test-specific: reset the controller image modified by this test (not part of general cleanup)
  oc mtv settings unset --setting controller_image_fqin             2>/dev/null || true
  echo "Cleanup done."
}
trap cleanup EXIT
cleanup

echo "=========================================="
echo "MTV-4911 Test"
echo "=========================================="

# --- STEP 0: Set controller image ---
echo "STEP 0: Setting controller image"
echo ">>> oc mtv settings set --setting controller_image_fqin --value ${FIXED_IMAGE}"
oc mtv settings set --setting controller_image_fqin --value "${FIXED_IMAGE}"

echo "Waiting for controller rollout..."
sleep 10
oc wait deployment/forklift-controller -n "${CONTROLLER_NS}" \
  --for=condition=Available --timeout=300s
echo "Controller ready."

# --- STEP 1: Create namespace ---
echo "STEP 1: Creating namespace '${NS}'"
oc create namespace "${NS}" --dry-run=client -o yaml | oc apply -f -

# --- STEP 2: Create providers ---
echo "STEP 2: Creating vSphere provider '${PROVIDER}'"
echo ">>> oc mtv create provider --name ${PROVIDER} --type vsphere --url ${REAL_URL} --username \${GOVC_USERNAME} --password \${GOVC_PASSWORD} --provider-insecure-skip-tls -n ${NS}"
oc mtv create provider \
  --name "${PROVIDER}" \
  --type vsphere \
  --url "${REAL_URL}" \
  --username "${GOVC_USERNAME}" \
  --password "${GOVC_PASSWORD}" \
  --provider-insecure-skip-tls \
  -n "${NS}"

echo ">>> oc mtv create provider --name host --type openshift -n ${NS}"
oc mtv create provider --name host --type openshift -n "${NS}"

echo "Waiting for providers Ready..."
oc wait "provider.forklift.konveyor.io/${PROVIDER}" -n "${NS}" \
  --for=condition=Ready --timeout=300s
oc wait "provider.forklift.konveyor.io/host" -n "${NS}" \
  --for=condition=Ready --timeout=300s
echo "Providers ready."

# --- STEP 3: Create migration plan ---
echo "STEP 3: Creating plan '${PLAN}' for VM '${VM}'"
echo ">>> oc mtv create plan --name ${PLAN} --source ${PROVIDER} --vms ${VM} -n ${NS}"
oc mtv create plan --name "${PLAN}" --source "${PROVIDER}" --vms "${VM}" -n "${NS}"

echo "Waiting for plan Ready..."
oc wait "plan.forklift.konveyor.io/${PLAN}" -n "${NS}" \
  --for=condition=Ready --timeout=300s
echo "Plan ready."

# --- STEP 4: Start migration ---
echo "STEP 4: Starting plan '${PLAN}'"
echo ">>> oc mtv start plan --name ${PLAN} -n ${NS}"
oc mtv start plan --name "${PLAN}" -n "${NS}"

echo "Waiting for Executing..."
oc wait "plan.forklift.konveyor.io/${PLAN}" -n "${NS}" \
  --for=condition=Executing --timeout=300s
echo "Plan is executing."

# --- STEP 5: Break the provider ---
echo "STEP 5: Breaking provider -- patching URL to ${BROKEN_URL}"
oc mtv patch provider --name "${PROVIDER}" --url "${BROKEN_URL}" -n "${NS}"
echo "Provider URL is now broken. Grace period clock starts."

# --- STEP 6: Wait during outage window ---
echo "STEP 6: Waiting ${OUTAGE_WAIT}s (within the 5-min grace window)..."
elapsed=0
while (( elapsed < OUTAGE_WAIT )); do
  sleep "${POLL}"
  elapsed=$(( elapsed + POLL ))
  plan_out=$(oc mtv get plan --name "${PLAN}" -n "${NS}" 2>&1) || true
  echo "  ${elapsed}/${OUTAGE_WAIT}s -- $(echo "${plan_out}" | tail -1)"

  if echo "${plan_out}" | grep -qi "Failed"; then
    echo "TEST FAILED: Plan failed during the grace window (old behavior)."
    oc logs deployment/forklift-controller -n "${CONTROLLER_NS}" \
      -c main --tail=50 | grep -iE "grace|blocker|fail" || true
    exit 1
  fi
done
echo "Plan survived the ${OUTAGE_WAIT}s outage window."

# --- STEP 7: Restore provider ---
echo "STEP 7: Restoring provider URL to ${REAL_URL}"
oc mtv patch provider --name "${PROVIDER}" --url "${REAL_URL}" -n "${NS}"

echo "Waiting for provider Ready..."
oc wait "provider.forklift.konveyor.io/${PROVIDER}" -n "${NS}" \
  --for=condition=Ready --timeout=300s
echo "Provider ready."

# --- STEP 8: Wait for migration completion ---
echo "STEP 8: Waiting for migration to complete (timeout ${COMPLETE_WAIT}s)..."
plan_out=$(oc mtv get plan --name "${PLAN}" -n "${NS}" 2>&1 || true)
complete_elapsed=0
while (( complete_elapsed < COMPLETE_WAIT )); do
  sleep "${POLL}"
  complete_elapsed=$(( complete_elapsed + POLL ))
  plan_out=$(oc mtv get plan --name "${PLAN}" -n "${NS}" 2>&1) || true

  if echo "${plan_out}" | grep -qi "Succeeded"; then echo "Migration SUCCEEDED."; break; fi
  if echo "${plan_out}" | grep -qi "Failed";    then echo "Migration FAILED.";    break; fi
  if echo "${plan_out}" | grep -qi "Canceled";  then echo "Migration CANCELED.";  break; fi

  echo "  still executing... (${complete_elapsed}s) -- $(echo "${plan_out}" | tail -1)"
done

if (( complete_elapsed >= COMPLETE_WAIT )) && ! echo "${plan_out}" | grep -qiE "Succeeded|Failed|Canceled"; then
  echo "TEST FAILED: Timed out after ${COMPLETE_WAIT}s waiting for a terminal state."
  exit 1
fi

# --- Summary ---
echo ""
echo "=========================================="
echo "RESULT"
echo "=========================================="
if echo "${plan_out}" | grep -qi "Succeeded"; then
  echo "TEST PASSED: MTV-4911"
  echo "Migration survived transient provider outage and completed successfully."
  exit 0
elif echo "${plan_out}" | grep -qi "Canceled"; then
  echo "TEST INCONCLUSIVE: MTV-4911"
  echo "Migration was canceled (not failed). Grace period worked but migration did not recover."
  exit 2
else
  echo "TEST FAILED: MTV-4911"
  echo "Check the logs above for details."
  exit 1
fi
