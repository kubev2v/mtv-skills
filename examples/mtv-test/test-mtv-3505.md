# Test Plan: MTV-3505 — VMware Serial Number Feature Flag

## Objective

Verify that the `feature_vmware_system_serial_number` feature flag in the ForkliftController CR correctly controls whether the VMware-formatted system serial number is used when migrating VMware VMs.

Before the fix, setting `feature_vmware_system_serial_number: false` had no effect because the Jinja2 template only emitted the environment variable when true, and the Go code defaulted to true when the env var was absent. After the fix, the template unconditionally emits the env var with the actual boolean value.

This test verifies both scenarios:
- **Default (enabled)**: System serial number should use VMware format (starts with `VMware-`)
- **Explicitly disabled**: System serial number should use the raw UUID (not VMware-formatted)

## Prerequisites

- `oc` with mtv plugin installed (kubectl also works)
- MTV installed on the cluster
- At least one VM available in vSphere inventory
- VDDK image configured (set via `VDDK_IMAGE` env var if not already configured)

## Test Steps

### Scenario 1: Default behavior (flag enabled by default)

1. Create namespace `mtv-3505-test`
2. Create vSphere provider with insecure-skip-tls
3. Wait for provider to be ready
4. Query inventory to select a VM for migration
5. Create migration plan for the selected VM
6. Start the migration
7. Wait for migration to complete
8. **Verify**: Extract the system serial number from the migrated VM CR (`.spec.template.spec.domain.firmware.serial`)
   - The serial SHOULD start with `VMware-` (VMware-formatted serial number)
9. Clean up migrated VM and plan

### Scenario 2: Feature flag disabled

10. Use `oc mtv settings set` to set `feature_vmware_system_serial_number: false`
11. Wait for controller deployment to rollout with the new settings
12. Create a new migration plan for the same VM
13. Start the migration
14. Wait for migration to complete
15. **Verify**: Extract the system serial number from the migrated VM CR (`.spec.template.spec.domain.firmware.serial`)
    - The serial should NOT start with `VMware-` (should be the raw UUID format)
16. Clean up namespace and revert settings

## Pass Criteria

- **Scenario 1 (enabled)**: The system serial number in the migrated VM CR starts with `VMware-`
- **Scenario 2 (disabled)**: The system serial number in the migrated VM CR does NOT start with `VMware-` (raw UUID format)

## Fail Criteria

- Scenario 1: Serial number does not start with `VMware-` when feature is enabled
- Scenario 2: Serial number starts with `VMware-` when the feature is disabled
- Provider fails to reconcile
- Migration fails for reasons unrelated to the feature being tested

## Notes

- This test focuses on the **system serial number** (SMBIOS/firmware serial), not disk serial numbers
- The VMware-formatted serial is generated from the VM's UUID using a specific algorithm
- The serial number can be found in the VirtualMachine CR at: `.spec.template.spec.domain.firmware.serial`
- To verify in the guest OS (optional, requires console access):
  - Linux: `sudo dmidecode -s system-serial-number`
  - Windows: `wmic bios get serialnumber`

## Cleanup

- Namespace `mtv-3505-test` deleted (includes provider and plans)
- Migrated VMs deleted
- ForkliftController CR settings reverted to original state (remove `feature_vmware_system_serial_number` override)
