# Bash Script Template

Full skeleton for a generated verification script. Adapt each section to the
specific ticket — remove or add blocks as needed.

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
echo "=========================================="
echo "MTV-<number> Test"
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

# >>> CONDITIONAL: include this VDDK check only when migrating from a vSphere source.
# >>> Omit the entire block for oVirt, OpenStack, OVA, EC2, HyperV, and OpenShift sources.
VDDK_IMAGE=$(oc mtv settings get --setting vddk_image 2>/dev/null \
  | tail -1 | awk '{print $NF}')
if [[ -n "${VDDK_IMAGE}" && "${VDDK_IMAGE}" != "<none>" && "${VDDK_IMAGE}" != "VALUE" ]]; then
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
echo ""
echo "=========================================="
echo "STEP 1: Creating namespace"
echo "=========================================="
oc create namespace "${NS}" --dry-run=client -o yaml | oc apply -f -
echo ""

# ===================================================================
#  STEP 2: Create provider(s)
# ===================================================================
echo "=========================================="
echo "STEP 2: Creating providers"
echo "=========================================="

# <use oc mtv create provider with appropriate flags — see ref-providers.md>
echo "Creating <type> provider..."
# <provider creation command here>

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
#  STEP 3: Create migration plan (if needed for this test)
# ===================================================================
echo "=========================================="
echo "STEP 3: Creating migration plan"
echo "=========================================="

echo "Creating plan..."
# oc mtv create plan --name "${PLAN}" --source "${PROVIDER}" \
#   --vms "${VM}" -n "${NS}"

echo "Waiting for plan..."
# oc wait "plan.forklift.konveyor.io/${PLAN}" -n "${NS}" \
#   --for=condition=Ready --timeout=300s

echo "Plan ready."
echo ""

# ===================================================================
#  STEP <N>: <Ticket-specific test steps>
# ===================================================================
echo "=========================================="
echo "STEP <N>: <Description>"
echo "=========================================="

# <Insert the core test logic here — this is ticket-specific>

# ===================================================================
#  Summary
# ===================================================================
echo ""
echo "=========================================="
echo "RESULT"
echo "=========================================="
echo "<Summary of what was verified>"
echo ""
echo "TEST PASSED: MTV-<number>"
exit 0
```
