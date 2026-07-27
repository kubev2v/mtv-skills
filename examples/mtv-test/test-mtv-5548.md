# Test Plan: MTV-5548 — Retain failed populator pods for debugging

## Objective

Verify that when `controller_retain_populator_pods` is enabled on the
ForkliftController CR, a failed vSphere xcopy populator pod and its target
PVC are preserved after permanent failure. When disabled (default), the
populator-controller should delete the PVC (and GC cascades to the pod).

## Prerequisites

- oc with mtv plugin installed (kubectl also works)
- MTV installed on the cluster with copy offload (xcopy) enabled
- Environment variables set:
  - `ECO_VSPHERE_PROVIDER` - vSphere provider URL
  - `ECO_VSPHERE_USERNAME` - vSphere username
  - `ECO_VSPHERE_PASSWORD` - vSphere password
  - `ECO_VSPHERE_VDDK` - VDDK init image
  - `ECO_NETAPP_SVM` - NetApp ONTAP SVM name
  - `ECO_NETAPP_HOST` - NetApp storage hostname
  - `ECO_NETAPP_USERNAME` - NetApp username
  - `ECO_NETAPP_PASSWORD` - NetApp password (only for working-secret use)
- A VM on vSphere (`VM` env var, default: `tshefi_40G`)
- Target storage class `trident-storage-class` available on the cluster

## Test Steps

### Scenario A: Retain enabled — populator pod survives failure

1. Create namespace `mtv-5548-test`
2. Create vSphere and OpenShift providers
3. Enable `controller_retain_populator_pods`
4. Create ONTAP secret with bad password (`RE9FU05UIFdPUks=`)
5. Create migration plan with offload (vsphere plugin, ontap vendor)
6. Start migration — populator pod fails due to bad credentials
7. Verify populator pod still exists (phase=Failed)
8. Verify target PVC still exists

### Scenario B: Retain disabled — populator pod is cleaned up

9. Clean up scenario A artifacts
10. Disable `controller_retain_populator_pods`
11. Create ONTAP secret with bad password again
12. Create new migration plan with same offload config
13. Start migration — populator pod fails
14. Verify populator pod is gone (deleted via PVC GC)
15. Verify target PVC is gone

## Pass Criteria

- Scenario A: populator pod exists with phase=Failed AND target PVC exists
- Scenario B: populator pod AND target PVC are both gone after failure

## Fail Criteria

- Scenario A: populator pod or PVC is missing (retain flag not respected)
- Scenario B: populator pod or PVC persists (default cleanup broken)

## Cleanup

- Namespace `mtv-5548-test` deleted
- `controller_retain_populator_pods` reverted to `false`
