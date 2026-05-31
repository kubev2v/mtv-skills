# Test Plan: MTV-4874 — Manual Network Map Uses NAD UID Instead of Namespace Name

## Objective
Verify that when creating a Network Map manually using `oc mtv create networkmap` (not as part of a migration plan), the `spec.map[].destination.namespace` field correctly uses the namespace name instead of the Network Attachment Definition's UID. This bug caused VMs to fail to start after migration because the system could not locate the NAD using the incorrect UUID reference.

## Prerequisites
- oc with mtv plugin installed
- MTV installed on the cluster
- Environment variables set: `GOVC_URL`, `GOVC_USERNAME`, `GOVC_PASSWORD`
- vSphere provider with available networks (e.g., "VM Network", "Mgmt Network")

## Test Steps
1. Create test namespace `mtv-4874`
2. Create two L2 Network Attachment Definitions (NADs) using OVN-Kubernetes overlay:
   - `test-l2-network-1` (topology: layer2)
   - `test-l2-network-2` (topology: layer2)
3. Create vSphere source provider (`vsphere-src`) with `--provider-insecure-skip-tls`
4. Create OpenShift destination provider (`host`)
5. Wait for vSphere provider to be Ready (condition=Ready)
6. Query source networks using `oc mtv get inventory network --provider vsphere-src -n mtv-4874`
7. Manually create a Network Map using `oc mtv create networkmap` that maps a vSphere source network (e.g., "VM Network") to the NAD `test-l2-network-1`
8. Retrieve the created Network Map YAML using `oc get networkmap -n mtv-4874 -o yaml`
9. Extract the NAD's UID using `oc get network-attachment-definition test-l2-network-1 -n mtv-4874 -o jsonpath='{.metadata.uid}'`
10. **Verify** that `spec.map[].destination.namespace` equals `mtv-4874` (the namespace name)
11. **Verify** that `spec.map[].destination.namespace` does NOT equal the NAD's UID

## Pass Criteria
- Manual Network Map is created successfully
- `spec.map[].destination.namespace` equals the namespace name (`mtv-4874`)
- `spec.map[].destination.namespace` does NOT match the NAD's UID (UUID format)
- `spec.map[].destination.name` equals the NAD name (`test-l2-network-1`)
- `spec.map[].destination.type` equals `multus`

## Fail Criteria
- `spec.map[].destination.namespace` contains a UUID format string (e.g., `e1becbe0-1e4e-4209-9f41-09d60804f5c1`)
- `spec.map[].destination.namespace` matches the NAD's UID instead of the namespace name
- Network Map creation fails

## Cleanup
- Namespace `mtv-4874` deleted (includes NADs, providers, and network map)
- No migration plan or VM migration required for this test
