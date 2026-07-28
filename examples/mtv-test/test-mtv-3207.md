# Test Plan: MTV-3207 — ConvertorNodeSelector propagated to CDI VDDK importer pods

## Objective

Verify that setting `convertorNodeSelector` on a vSphere warm migration Plan causes
the CDI VDDK importer pods to be scheduled on nodes matching the specified labels.
The test labels a worker node with a custom label, creates a warm Plan with
`convertorNodeSelector` pointing to that label, starts the migration, and confirms
that the CDI importer pod lands on the labeled node.

## Prerequisites

- oc with mtv plugin installed
- MTV installed on the cluster (with CDI version that includes CNV-84595 support)
- VDDK image configured
- Environment variables set: `GOVC_URL`, `GOVC_USERNAME`, `GOVC_PASSWORD`
- VM `mtv-rhel8-warm-sanity` available on vSphere (1.9 GB disk, smallest warm VM)

## Test Steps

1. Create test namespace `mtv-3207-test`
2. Label one worker node with `mtv-3207-test=importer-target`
3. Create vSphere source provider and OpenShift host provider
4. Create a warm migration plan with `convertorNodeSelector: {"mtv-3207-test": "importer-target"}`
5. Start the migration
6. Wait for the CDI importer pod to appear (pod name starts with `importer-`)
7. Verify the importer pod is scheduled on the labeled node
8. Cancel the migration (no need to wait for full completion)

## Pass Criteria

- The CDI importer pod's `spec.nodeSelector` contains `mtv-3207-test: importer-target`
- The CDI importer pod is running on (or scheduled to) the labeled worker node

## Fail Criteria

- The CDI importer pod has no `nodeSelector` or is scheduled on a different node
- No CDI importer pod appears (migration uses virt-v2v path instead of VDDK)

## Cleanup

- Node label `mtv-3207-test` removed from the worker node
- Namespace `mtv-3207-test` deleted (removes providers, plan, migration artifacts)
