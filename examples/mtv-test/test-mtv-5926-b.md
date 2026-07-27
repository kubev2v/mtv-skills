# Test Plan: MTV-5926-B — Azure VM Migration E2E

## Objective

Migrate a VM from Azure to OpenShift Virtualization and verify it reaches
Running state on the target cluster.

## Prerequisites

- oc with mtv plugin installed
- MTV installed on the cluster
- Azure CLI (`az`) installed
- Environment variables set:
  - `AZURE_TENANT_ID` — Azure AD tenant ID
  - `AZURE_SUBSCRIPTION_ID` — Azure subscription ID
  - `AZURE_CLIENT_ID` — service principal client ID
  - `AZURE_CLIENT_SECRET` — service principal secret
- Optional environment variables:
  - `AZURE_RESOURCE_GROUP` — resource group containing the VM (default: `mtv-5926-test-rg`)
  - `AZURE_VM_NAME` — VM to migrate (default: `test-vm-5926`)
  - `MIGRATION_TIMEOUT` — max time to wait for migration (default: `1200s`)
  - `SKIP_CLEANUP` — set to `true` to keep resources after test
- A VM in the target resource group (deallocated or stoppable)

## Test Steps

1. Create test namespace `mtv-5926-test-b`
2. Create Azure source provider and OpenShift host provider
3. Wait for both providers to become Ready
4. Verify the target VM exists in the Azure inventory
5. Create a migration plan with auto-generated network/storage mappings
6. Wait for the plan to become Ready
7. Start the migration
8. Wait for the migration plan to reach Succeeded condition
9. Verify the VirtualMachineInstance reaches Running phase on OpenShift

## Pass Criteria

- Both providers reach Ready state
- Migration plan becomes Ready with auto-generated mappings
- Migration completes (plan condition Succeeded)
- VMI reaches Running phase on OpenShift

## Fail Criteria

- Provider fails to reach Ready state
- VM not found in inventory
- Plan fails to become Ready (bad mappings, validation errors)
- Migration times out or fails
- VMI does not reach Running phase within 5 minutes after migration

## Cleanup

- Migration plan, providers, migrated VM, and namespace `mtv-5926-test-b` deleted
- Set `SKIP_CLEANUP=true` to preserve resources for debugging
