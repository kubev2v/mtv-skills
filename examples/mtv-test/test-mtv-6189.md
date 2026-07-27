# Test Plan: MTV-6189 — Simplified PVC Name Template

## Objective

Verify the unified PVC name template logic for vSphere migrations:
- Empty `pvcNameTemplate` falls back to the hardcoded default at runtime
- The default template produces PVC names matching `{plan15}-{vm15}-disk-{index}-{suffix}`
- Custom `pvcNameTemplate` (including `.VmId`) overrides the default
- `pvcNameTemplateUseGenerateName` defaults to `true` for non-OCP (random suffix appended)
- Explicit `pvcNameTemplateUseGenerateName: false` produces exact names (no suffix)
- ForkliftController global `controller_pvc_name_template` overrides the hardcoded default

## Prerequisites

- oc with mtv plugin installed
- MTV installed on the cluster (with the MTV-6189 branch deployed)
- VDDK image configured
- Environment variables set: `GOVC_URL`, `GOVC_USERNAME`, `GOVC_PASSWORD`
- A VM available for migration (default: `mtv-rhel8-sanity`)

## Test Steps

### Scenario A: Default template (empty pvcNameTemplate)

1. Create namespace and providers (vSphere + host OpenShift)
2. Create a plan with no explicit `pvcNameTemplate`
3. Verify the plan is Ready
4. Start migration and wait for completion
5. Verify PVC names match pattern: `{plan15}-{vm15}-disk-{index}-{suffix}`
   (generateName is true by default for non-OCP, so a random suffix is appended)

### Scenario B: Custom template with `.VmId`

1. Create a plan with `pvcNameTemplate: "{{.PlanName}}-{{.VmId}}"`
2. Verify the plan is Ready
3. Start migration and wait for completion
4. Verify PVC names start with `{planName}-`

### Scenario C: Exact name (useGenerateName=false)

1. Create a plan with `pvcNameTemplateUseGenerateName: false` and the default template
2. Verify the plan is Ready
3. Start migration and wait for completion
4. Verify PVC names are exact: `{plan15}-{vm15}-disk-{index}` (no random suffix)

### Scenario D: ForkliftController global template override

1. Set `controller_pvc_name_template` via `oc mtv settings set`
2. Create a plan with no explicit `pvcNameTemplate`
3. Verify the plan is Ready
4. Start migration and wait for completion
5. Verify PVC names match the global template pattern
6. Revert the global setting

## Pass Criteria

- Scenario A: PVCs match `^<plan15>-<vm15>-disk-[0-9]+-[a-z0-9]{5}$` (with suffix)
- Scenario B: PVCs start with `<planName>-`
- Scenario C: PVCs match `^<plan15>-<vm15>-disk-[0-9]+$` exactly (no suffix)
- Scenario D: PVCs match the global template pattern

## Fail Criteria

- PVC name does not match the expected pattern for any scenario
- Migration fails for reasons unrelated to PVC naming

## Cleanup

- Namespace `mtv-6189-test` deleted
- Providers deleted
- ForkliftController global template reverted
