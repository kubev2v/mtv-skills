# Test Plan: MTV-5753 — Collect PCI slot number from vSphere into inventory

## Objective

Verify that after creating a vSphere provider, the inventory service populates
`pciSlotNumber` on VM devices and `pciAddress` on VM NICs using the correct
bridge-aware formula (FFF.BBBBB.DDDDD encoding per Broadcom KB 311606).

## Prerequisites

- oc with mtv plugin and jq installed
- MTV installed on the cluster (with the MTV-5753 patch applied)
- Environment variables set: `GOVC_URL`, `GOVC_USERNAME`, `GOVC_PASSWORD`
- At least one VM with multiple NICs on the vSphere source (default:
  `mtv-function-rhel7-9-staticips` which has 4 NICs including one behind a
  multi-function PCIe root port)
- govc installed for cross-validation against vSphere source data
- VM powered on with VMware Tools running (for lspci cross-validation)

## Test Steps

1. Create namespace `mtv-5753-test` and vSphere + OpenShift providers
2. Wait for inventory collection (VM appears)
3. Match devices to NICs by `key == deviceKey` and verify:
   - `pciSlotNumber > 0` on at least one device
   - `pciAddress` populated on ALL NICs (not just root-bus ones)
4. Cross-validate against govc: confirm inventory slot numbers match
   vSphere source data
5. Cross-validate against guest `lspci`: confirm inventory PCI addresses
   match the guest-visible addresses

## Pass Criteria

- At least one VM device has `pciSlotNumber > 0`
- ALL VM NICs have a non-empty `pciAddress`
- Inventory slot numbers match govc source data
- Inventory PCI addresses match guest `lspci` output

## Fail Criteria

- All `pciSlotNumber` values are 0
- Any `pciAddress` value is empty
- Slot numbers differ between inventory and govc
- PCI addresses differ between inventory and guest lspci

## Manual Verification

Create a namespace and vSphere provider:

```bash
oc create namespace mtv-5753-test

oc mtv create provider --name vsphere-test --type vsphere \
  --url "https://${GOVC_URL}/sdk" \
  --username "${GOVC_USERNAME}" \
  --password "${GOVC_PASSWORD}" \
  --provider-insecure-skip-tls \
  -n mtv-5753-test

oc wait provider.forklift.konveyor.io/vsphere-test \
  -n mtv-5753-test --for=condition=Ready --timeout=300s
```

Query the inventory for the default test VM after the provider is ready:

```bash
oc mtv get inventory vm \
  --provider vsphere-test -n mtv-5753-test \
  --query "where name = 'mtv-function-rhel7-9-staticips'" \
  --output json | jq '.[0] | {name, devices, nics}'
```

Expected output (4 NICs, all with `pciAddress` populated):

```json
{
  "name": "mtv-function-rhel7-9-staticips",
  "devices": [
    { "key": 4000, "kind": "VirtualVmxnet3", "pciSlotNumber": 192 },
    { "key": 4001, "kind": "VirtualVmxnet3", "pciSlotNumber": 224 },
    { "key": 4002, "kind": "VirtualVmxnet3", "pciSlotNumber": 256 },
    { "key": 4003, "kind": "VirtualVmxnet3", "pciSlotNumber": 1184 }
  ],
  "nics": [
    { "deviceKey": 4003, "mac": "00:50:56:be:3a:07", "pciAddress": "0000:04:00.0", "order": 3 },
    { "deviceKey": 4000, "mac": "00:50:56:1c:1c:7d", "pciAddress": "0000:0b:00.0", "order": 0 },
    { "deviceKey": 4001, "mac": "00:50:56:1c:8c:8d", "pciAddress": "0000:13:00.0", "order": 1 },
    { "deviceKey": 4002, "mac": "00:50:56:be:c3:3a", "pciAddress": "0000:1b:00.0", "order": 2 }
  ]
}
```

Note: device key 4003 (slot 1184) is behind a multi-function PCIe root port
(`BBBBB=5, FFF=1`), producing bus `0x04` instead of the root bus.

## Cleanup

- Namespace `mtv-5753-test` deleted
- Providers deleted
