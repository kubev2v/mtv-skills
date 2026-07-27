#!/bin/bash
#
# E2E test for MTV-4874: Manual Network Map Uses NAD UID Instead of Namespace Name
#
# Prerequisites: oc, oc mtv plugin, GOVC_URL, GOVC_USERNAME, GOVC_PASSWORD,
#   and a cluster with MTV installed (controller in konveyor-forklift by default).

set -euo pipefail

# --- Constants ---
NS="mtv-4874"
PROVIDER="vsphere-src"
NETWORKMAP="test-networkmap"
NAD1="test-l2-network-1"
NAD2="test-l2-network-2"
SKIP_CLEANUP="${SKIP_CLEANUP:-false}"

# ===================================================================
#  Preflight: verify MTV is installed and provider prerequisites
# ===================================================================
echo "=========================================="
echo "MTV-4874 Test"
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
    echo "SKIP_CLEANUP=true — preserving resources in namespace '${NS}' for forensic inspection."
    return 0
  fi
  echo "Cleaning up..."
  oc mtv delete mapping network "${NETWORKMAP}" -n "${NS}" 2>/dev/null || true
  oc mtv delete provider --name "${PROVIDER}" -n "${NS}" 2>/dev/null || true
  oc mtv delete provider --name host -n "${NS}" 2>/dev/null || true
  oc delete namespace "${NS}" --ignore-not-found 2>/dev/null || true
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
#  STEP 2: Create L2 Network Attachment Definitions
# ===================================================================
echo "=========================================="
echo "STEP 2: Creating L2 NADs"
echo "=========================================="

cat <<EOF | oc apply -f -
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: ${NAD1}
  namespace: ${NS}
spec:
  config: |
    {
      "cniVersion": "0.3.1",
      "name": "${NAD1}",
      "type": "ovn-k8s-cni-overlay",
      "topology": "layer2",
      "netAttachDefName": "${NS}/${NAD1}"
    }
---
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: ${NAD2}
  namespace: ${NS}
spec:
  config: |
    {
      "cniVersion": "0.3.1",
      "name": "${NAD2}",
      "type": "ovn-k8s-cni-overlay",
      "topology": "layer2",
      "netAttachDefName": "${NS}/${NAD2}"
    }
EOF

echo "NADs created."
echo ""

# ===================================================================
#  STEP 3: Create providers
# ===================================================================
echo "=========================================="
echo "STEP 3: Creating providers"
echo "=========================================="

echo "Creating vSphere provider..."
oc mtv create provider --name "${PROVIDER}" --type vsphere \
  --url "${GOVC_URL}/sdk" \
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
#  STEP 4: Query source networks from inventory
# ===================================================================
echo "=========================================="
echo "STEP 4: Query source networks"
echo "=========================================="

oc mtv get inventory network --provider "${PROVIDER}" -n "${NS}"

# Get the first available network for testing
SOURCE_NETWORK=$(oc mtv get inventory network --provider "${PROVIDER}" -n "${NS}" --output json \
  | jq -r '.[0].name' 2>/dev/null || echo "")

if [[ -z "${SOURCE_NETWORK}" ]]; then
  echo "ERROR: No source networks found in vSphere inventory."
  exit 1
fi

echo "Using source network: ${SOURCE_NETWORK}"
echo ""

# ===================================================================
#  STEP 5: Create manual Network Map
# ===================================================================
echo "=========================================="
echo "STEP 5: Create manual Network Map"
echo "=========================================="

echo "Creating network map..."
oc mtv create mapping network --name "${NETWORKMAP}" \
  --source "${PROVIDER}" \
  --target host \
  --network-pairs "${SOURCE_NETWORK}:${NAD1}" \
  -n "${NS}"

echo "Network map created."
echo ""
echo "Getting network map YAML..."
oc mtv get mapping "${NETWORKMAP}" -n "${NS}" -o yaml
echo ""

# ===================================================================
#  STEP 6: Verify the Network Map namespace field
# ===================================================================
echo "=========================================="
echo "STEP 6: Verify Network Map"
echo "=========================================="

# Get the NAD UID
NAD_UID=$(oc get network-attachment-definition "${NAD1}" -n "${NS}" -o jsonpath='{.metadata.uid}')

# Get the NetworkMap spec
NETWORKMAP_YAML=$(oc get networkmap "${NETWORKMAP}" -n "${NS}" -o yaml)

# Extract the destination namespace from the NetworkMap
DEST_NAMESPACE=$(echo "${NETWORKMAP_YAML}" | yq eval '.spec.map[0].destination.namespace' -)
DEST_NAME=$(echo "${NETWORKMAP_YAML}" | yq eval '.spec.map[0].destination.name' -)
DEST_TYPE=$(echo "${NETWORKMAP_YAML}" | yq eval '.spec.map[0].destination.type' -)

echo ""
echo "=========================================="
echo "VERIFICATION"
echo "=========================================="
echo "NAD name:              ${NAD1}"
echo "NAD UID:               ${NAD_UID}"
echo "Expected namespace:    ${NS}"
echo "Actual namespace:      ${DEST_NAMESPACE}"
echo "Actual name:           ${DEST_NAME}"
echo "Actual type:           ${DEST_TYPE}"
echo ""

# Verify the namespace field is correct
if [[ "${DEST_NAMESPACE}" == "${NS}" ]]; then
  echo "PASS: destination.namespace equals namespace name"
else
  echo "FAIL: destination.namespace is '${DEST_NAMESPACE}', expected '${NS}'"
  exit 1
fi

# Verify the namespace is NOT the NAD UID
if [[ "${DEST_NAMESPACE}" == "${NAD_UID}" ]]; then
  echo "FAIL: destination.namespace equals NAD UID (bug reproduced!)"
  exit 1
else
  echo "PASS: destination.namespace does NOT equal NAD UID"
fi

# Verify the destination name is correct
if [[ "${DEST_NAME}" == "${NAD1}" ]]; then
  echo "PASS: destination.name equals NAD name"
else
  echo "FAIL: destination.name is '${DEST_NAME}', expected '${NAD1}'"
  exit 1
fi

# Verify the destination type is multus
if [[ "${DEST_TYPE}" == "multus" ]]; then
  echo "PASS: destination.type equals 'multus'"
else
  echo "FAIL: destination.type is '${DEST_TYPE}', expected 'multus'"
  exit 1
fi

# ===================================================================
#  Summary
# ===================================================================
echo ""
echo "=========================================="
echo "RESULT"
echo "=========================================="
echo "Namespace (expected): ${NS}"
echo "Namespace (actual):   ${DEST_NAMESPACE}"
echo "NAD UID:              ${NAD_UID}"
echo ""
echo "TEST PASSED: MTV-4874"
exit 0
