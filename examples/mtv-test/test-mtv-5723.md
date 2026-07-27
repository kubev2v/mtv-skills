# Test Plan: MTV-5723 — Cleanup copied ConfigMaps after migration completes

## Objective
Verify that ConfigMaps copied to the target namespace during migration (extra-v2v-conf,
customization-scripts, vddk-conf) are automatically deleted when the migration finishes
(succeeded, failed, or canceled). Previously these ConfigMaps leaked in the target namespace.

## Prerequisites
- oc with mtv plugin installed
- MTV installed on the cluster with the MTV-5723 fix deployed
- A vSphere provider already configured in the provider namespace
- Optional environment variables:
  - `PROVIDER_NS` — namespace of the existing provider (default: `openshift-mtv`)
  - `PROVIDER_NAME` — name of the existing vSphere provider (default: `vmware-7`)
  - `VM_NAME` — VM to migrate (default: `mtv-feature-rhel7-2`)
  - `TARGET_NS` — target namespace for migration (default: `mtv-5723-test`)
  - `SKIP_CLEANUP` — set to `true` to preserve resources after test

## Test Steps
1. Create a target namespace distinct from the provider namespace
2. Create a customization-scripts ConfigMap in the provider namespace (cross-namespace)
3. Create a cold migration plan with `--customization-scripts` referencing the cross-namespace CM
4. Start migration and wait for it to complete
5. Verify that copied ConfigMaps (`<plan>-customization-scripts`, `<plan>-extra-v2v-conf`,
   vddk-conf CMs) are absent from the target namespace after completion

## Pass Criteria
- Migration completes successfully
- No `<plan>-customization-scripts` ConfigMap exists in target namespace after completion
- No `<plan>-extra-v2v-conf` ConfigMap exists in target namespace after completion
- No vddk-conf ConfigMaps (by label) exist in target namespace after completion

## Fail Criteria
- Migration hangs or fails
- Any copied ConfigMap remains in the target namespace after migration completion

## Cleanup
- Migration and plan deleted
- ConfigMap in provider namespace deleted
- Target namespace deleted
