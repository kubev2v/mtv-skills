# Test Plan: MTV-4911 — In-flight Migrations Fail Immediately on Transient Provider/Map Readiness Loss

## Objective
Verify that an active migration survives transient provider readiness loss (e.g., during controller pod restart) and completes successfully after the provider recovers within the grace period. This test confirms that the new blocker grace period mechanism prevents migrations from failing immediately during routine operational events like controller restarts, node maintenance, or operator upgrades.

## Background
The fix for MTV-4336 introduced `failExecutingMigrationOnBlocker()` which immediately transitions an active migration to Failed when a validation blocker (Critical/Error condition) is detected during execution. While this correctly fixes infinite hangs when a map permanently loses Ready, it did not account for transient readiness loss — causing in-flight migrations to fail during routine operational events like:
- ForkliftController CR changes triggering deployment rollout
- OLM operator upgrades
- Node drain/maintenance
- Controller pod OOMKill or crashes

MTV-4911 introduces a grace period (default 5 minutes) to tolerate transient outages before failing the migration.

## Prerequisites
- oc CLI with mtv plugin installed
- MTV installed on the cluster with the MTV-4911 fix (controller image with grace period support)
- Environment variables set: `GOVC_URL`, `GOVC_USERNAME`, `GOVC_PASSWORD`
- vSphere provider with an available VM for migration (e.g., `mtv-rhel8-sanity`)
- Optional: Custom controller image with fix (default: `quay.io/yaacov/forklift-controller:mtv-4911-01-amd64`)

## Test Steps
1. Set the controller image to a version with the MTV-4911 fix using `oc mtv settings set --setting controller_image_fqin`
2. Wait for controller deployment rollout to complete
3. Create test namespace `grace-period-test`
4. Create vSphere source provider (`vsphere-test`) pointing to valid vCenter URL with `--provider-insecure-skip-tls`
5. Create OpenShift destination provider (`host`)
6. Wait for both providers to reach Ready state (condition=Ready)
7. Create a migration plan (`grace-period-plan`) targeting a test VM
8. Wait for plan to reach Ready state
9. Start the migration using `oc mtv start plan`
10. Wait for migration to reach Executing state (condition=Executing)
11. **Break the provider** by patching the source provider URL to an invalid endpoint (e.g., `https://1.2.3.4/sdk`)
12. **Monitor during outage window** (120 seconds, within the 5-minute grace period):
    - Poll the plan status every 15 seconds
    - **Verify** the plan does NOT transition to Failed during this window
    - If plan fails during this window, the test fails (old behavior)
13. **Restore the provider** by patching the source provider URL back to the valid vCenter URL
14. Wait for provider to reach Ready state again
15. **Wait for migration completion** (up to 3600 seconds):
    - Poll plan status every 15 seconds
    - Wait for terminal state (Succeeded, Failed, or Canceled)
16. **Verify** the migration completes with Succeeded status

## Pass Criteria
- Migration does NOT fail during the 120-second outage window (grace period active)
- Provider successfully recovers after URL is restored
- Migration resumes and completes with Succeeded status
- Plan conditions show the migration survived the transient blocker

## Fail Criteria
- Migration transitions to Failed during the outage window (indicates old behavior — no grace period)
- Migration times out after provider recovery (indicates recovery failed)
- Migration completes with Failed or Canceled status

## Environment Configuration
- `VM`: Source VM name (default: `mtv-rhel8-sanity`)
- `CONTROLLER_NS`: Forklift controller namespace (default: `konveyor-forklift`)
- `FIXED_IMAGE`: Controller image with MTV-4911 fix (default: `quay.io/yaacov/forklift-controller:mtv-4911-01-amd64`)
- `OUTAGE_WAIT`: Duration in seconds to keep provider broken (default: 120, must be < 300 to stay within grace period)
- `COMPLETE_WAIT`: Maximum time to wait for migration completion (default: 3600)
- `SKIP_CLEANUP`: Set to `true` to preserve resources after test for debugging

## Cleanup
- Migration plan `grace-period-plan` deleted
- Providers `vsphere-test` and `host` deleted
- Namespace `grace-period-test` deleted
- Controller image setting reset using `oc mtv settings unset --setting controller_image_fqin`

## Notes
- The grace period default is 5 minutes (300 seconds)
- The test breaks the provider for 120 seconds, which is well within the grace period
- The test verifies both that the migration survives the outage AND that it completes successfully after recovery
- Breaking the provider URL is a realistic simulation of what happens during controller restarts when providers temporarily lose Ready status
- Test-specific: This test modifies the controller image, which is not typical cleanup but is included to restore the cluster to its original state
