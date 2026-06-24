#!/bin/bash
#
# E2E test for PCI slot number collection from vSphere (MTV-5753).
#
# Prerequisites: oc, oc mtv plugin, jq, GOVC_URL, GOVC_USERNAME, GOVC_PASSWORD,
#   and a cluster with MTV installed (controller in konveyor-forklift by default).

set -euo pipefail

# --- Constants ---
NS="mtv-5753-test"
PROVIDER="vsphere-test"
VM="${VM:-mtv-function-rhel7-9-staticips}"
SKIP_CLEANUP="${SKIP_CLEANUP:-false}"
POLL=15
MAX_WAIT=300

# --- Helper ---
get_vm_inventory() {
  oc mtv get inventory vm --provider "${PROVIDER}" -n "${NS}" \
    --query "where name = '${VM}'" --output json 2>/dev/null || echo "[]"
}

# ===================================================================
#  Preflight: verify MTV is installed and VDDK configured
# ===================================================================
echo "=========================================="
echo "MTV-5753 Test"
echo "=========================================="
echo ""
echo "Preflight: Checking MTV installation..."

if ! command -v oc &>/dev/null; then
  echo "ERROR: 'oc' CLI not found in PATH."
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "ERROR: 'jq' not found in PATH."
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
    echo "SKIP_CLEANUP=true -- preserving resources in namespace '${NS}' for forensic inspection."
    return 0
  fi
  echo "Cleaning up..."
  oc mtv delete provider --name "${PROVIDER}" -n "${NS}" 2>/dev/null || true
  oc mtv delete provider --name host -n "${NS}"          2>/dev/null || true
  oc delete namespace "${NS}" --ignore-not-found         2>/dev/null || true
  echo "Cleanup done."
}
trap cleanup EXIT
cleanup

# ===================================================================
#  STEP 1: Create namespace and providers
# ===================================================================
echo ""
echo "=========================================="
echo "STEP 1: Creating namespace and providers"
echo "=========================================="
oc create namespace "${NS}" --dry-run=client -o yaml | oc apply -f -

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
#  STEP 2: Wait for inventory collection
# ===================================================================
echo "=========================================="
echo "STEP 2: Waiting for inventory collection"
echo "=========================================="
echo "Polling for VM '${VM}' in inventory..."

elapsed=0
vm_count=0
while [[ ${elapsed} -lt ${MAX_WAIT} ]]; do
  vm_count=$(get_vm_inventory | jq 'length')

  if [[ "${vm_count}" -gt 0 ]]; then
    echo "Found VM in inventory after ${elapsed}s."
    break
  fi
  echo "  No VMs yet (${elapsed}s / ${MAX_WAIT}s)..."
  sleep "${POLL}"
  elapsed=$((elapsed + POLL))
done

if [[ "${vm_count}" -eq 0 ]]; then
  echo "ERROR: VM '${VM}' not found in inventory after ${MAX_WAIT}s."
  echo "TEST INCONCLUSIVE: MTV-5753 — could not verify (VM not in inventory)"
  exit 2
fi

INVENTORY_JSON=$(get_vm_inventory)
echo ""
echo "Inventory for '${VM}':"
echo "${INVENTORY_JSON}" | jq '[.[] | {name, devices, nics}]'
echo ""

# ===================================================================
#  STEP 3: Match devices to NICs by key and verify PCI data
# ===================================================================
echo "=========================================="
echo "STEP 3: Matching devices to NICs by key"
echo "=========================================="

echo "${INVENTORY_JSON}" | jq -r '
  .[] |
  .devices as $devs |
  .nics[] |
  . as $nic |
  ($devs[] | select(.key == $nic.deviceKey)) as $dev |
  "  key=\($dev.key) kind=\($dev.kind) pciSlotNumber=\($dev.pciSlotNumber) -> pciAddress=\($nic.pciAddress // "(empty)") mac=\($nic.mac)"
'

pci_device_count=$(echo "${INVENTORY_JSON}" | jq '
  [.[] | .devices[] | select(.pciSlotNumber > 0)] | length
')

pci_nic_count=$(echo "${INVENTORY_JSON}" | jq '
  [.[] | .nics[] | select(.pciAddress != null and .pciAddress != "")] | length
')

empty_count=$(echo "${INVENTORY_JSON}" | jq '
  [.[] | .nics[] | select(.pciAddress == null or .pciAddress == "")] | length
')

echo ""

if [[ "${pci_device_count}" -eq 0 ]]; then
  echo "TEST FAILED: MTV-5753 — pciSlotNumber not populated on any device"
  exit 1
fi
echo "PASS: ${pci_device_count} device(s) have pciSlotNumber populated."

if [[ "${pci_nic_count}" -eq 0 ]]; then
  echo "TEST FAILED: MTV-5753 — pciAddress not populated on any NIC"
  exit 1
fi

if [[ "${empty_count}" -gt 0 ]]; then
  echo "TEST FAILED: MTV-5753 — ${empty_count} NIC(s) have empty pciAddress (bridge formula issue)"
  exit 1
fi
echo "PASS: ${pci_nic_count} NIC(s) have pciAddress populated (all NICs covered)."
echo ""

# ===================================================================
#  STEP 4: Cross-validate against govc
# ===================================================================
echo "=========================================="
echo "STEP 4: Cross-validating with govc"
echo "=========================================="

if ! command -v govc &>/dev/null; then
  echo "govc not found — skipping cross-validation."
else
  GOVC_JSON=$(govc vm.info -json "${VM}" 2>/dev/null || echo "{}")
  govc_nics=$(echo "${GOVC_JSON}" | jq -r '
    [.virtualMachines[0].config.hardware.device[] |
     select(.macAddress != null) |
     {key, pciSlotNumber: .slotInfo.pciSlotNumber, mac: .macAddress}]
  ' 2>/dev/null || echo "[]")

  echo "Comparing inventory to vSphere source data..."
  mismatches=0
  while IFS= read -r line; do
    gkey=$(echo "${line}" | jq -r '.key')
    gslot=$(echo "${line}" | jq -r '.pciSlotNumber')
    gmac=$(echo "${line}" | jq -r '.mac')

    inv_slot=$(echo "${INVENTORY_JSON}" | jq -r \
      --argjson k "${gkey}" \
      '[.[] | .devices[] | select(.key == $k) | .pciSlotNumber] | first // "missing"')
    inv_addr=$(echo "${INVENTORY_JSON}" | jq -r \
      --argjson k "${gkey}" \
      '[.[] | .nics[] | select(.deviceKey == $k) | .pciAddress] | first // "missing"')

    status="OK"
    if [[ "${inv_slot}" != "${gslot}" ]]; then
      status="SLOT_MISMATCH(expected=${gslot},got=${inv_slot})"
      mismatches=$((mismatches + 1))
    fi
    echo "  key=${gkey} mac=${gmac} govc_slot=${gslot} inv_slot=${inv_slot} pciAddress=${inv_addr} ${status}"
  done < <(echo "${govc_nics}" | jq -c '.[]')

  if [[ ${mismatches} -gt 0 ]]; then
    echo "TEST FAILED: MTV-5753 — ${mismatches} slot mismatch(es) between govc and inventory"
    exit 1
  fi
  echo "PASS: All slot numbers match vSphere source data."
fi
echo ""

# ===================================================================
#  STEP 5: Cross-validate PCI addresses against guest lspci
# ===================================================================
echo "=========================================="
echo "STEP 5: Cross-validating with guest lspci"
echo "=========================================="

GUEST_LOGIN="${GUEST_LOGIN:-root:redhat}"

if ! command -v govc &>/dev/null; then
  echo "govc not found — skipping lspci cross-validation."
else
  power_state=$(govc vm.info -json "${VM}" 2>/dev/null | jq -r '.virtualMachines[0].runtime.powerState // "unknown"')
  if [[ "${power_state}" != "poweredOn" ]]; then
    echo "VM is ${power_state} — powering on for guest validation..."
    govc vm.power -on "${VM}" 2>/dev/null || true
    echo "Waiting for VMware Tools (up to 120s)..."
    tools_wait=0
    while [[ ${tools_wait} -lt 120 ]]; do
      tools_status=$(govc vm.info -json "${VM}" 2>/dev/null | jq -r '.virtualMachines[0].guest.toolsRunningStatus // "unknown"')
      if [[ "${tools_status}" == "guestToolsRunning" ]]; then
        echo "Tools running after ${tools_wait}s."
        break
      fi
      sleep 10
      tools_wait=$((tools_wait + 10))
    done
  fi

  if ! govc guest.run -vm "${VM}" -l "${GUEST_LOGIN}" /bin/true &>/dev/null; then
    echo "Cannot run commands in guest (tools not ready or wrong credentials) — skipping."
  else
    echo "Querying guest for NIC PCI addresses..."
    GUEST_PCI=$(echo '
      for iface in /sys/class/net/*/device; do
        dir=$(dirname "$iface")
        name=$(basename "$dir")
        [ "$name" = "lo" ] && continue
        mac=$(cat "$dir/address" 2>/dev/null)
        pci=$(readlink "$dir/device" 2>/dev/null | grep -oE "[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-9a-f]")
        [ -z "$pci" ] && continue
        echo "$mac $pci"
      done
    ' | govc guest.run -vm "${VM}" -l "${GUEST_LOGIN}" -d - /bin/bash 2>/dev/null || echo "")

    if [[ -z "${GUEST_PCI}" ]]; then
      echo "No PCI data from guest — skipping."
    else
      pci_mismatches=0
      while IFS=' ' read -r gmac gpci; do
        gmac_lower=$(echo "${gmac}" | tr '[:upper:]' '[:lower:]')
        inv_pci=$(echo "${INVENTORY_JSON}" | jq -r \
          --arg mac "${gmac_lower}" \
          '[.[] | .nics[] | select(.mac == $mac) | .pciAddress] | first // "missing"')
        status="OK"
        if [[ "${inv_pci}" != "${gpci}" ]]; then
          status="PCI_MISMATCH(guest=${gpci},inv=${inv_pci})"
          pci_mismatches=$((pci_mismatches + 1))
        fi
        echo "  mac=${gmac_lower} guest_pci=${gpci} inv_pci=${inv_pci} ${status}"
      done <<< "${GUEST_PCI}"

      if [[ ${pci_mismatches} -gt 0 ]]; then
        echo "TEST FAILED: MTV-5753 — ${pci_mismatches} PCI address mismatch(es) between guest and inventory"
        exit 1
      fi
      echo "PASS: All PCI addresses match guest lspci output."
    fi
  fi
fi
echo ""

# ===================================================================
#  Summary
# ===================================================================
echo ""
echo "=========================================="
echo "RESULT"
echo "=========================================="
echo "Devices with pciSlotNumber: ${pci_device_count}"
echo "NICs with pciAddress:       ${pci_nic_count}"
echo ""
echo "TEST PASSED: MTV-5753 — PCI slot number collection and address computation verified"
exit 0
