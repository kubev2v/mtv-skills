---
name: check-ceph-health
description: Check Ceph storage health on OpenShift OCS/ODF clusters. Use when PVCs are stuck in Pending, storage provisioning fails, Ceph is degraded, OSDs are full, or cluster storage needs diagnosis.
---

# Check Ceph Health

Use this guide to diagnose and remediate Ceph storage issues on OpenShift clusters running OCS/ODF (OpenShift Data Foundation).

## Required CLI Tools

This skill requires:
- `oc metrics` ([kubectl-metrics](https://github.com/yaacov/kubectl-metrics)) -- for Ceph metrics (health, capacity, OSD, PG)
- `oc debug-queries` ([kubectl-debug-queries](https://github.com/yaacov/kubectl-debug-queries)) -- for listing resources, logs, events

If any tool is missing, install with the secure version-pinned installer:

```bash
curl -sSLO https://raw.githubusercontent.com/kubev2v/mtv-skills/main/tools/install-tools.sh
curl -sSL  https://raw.githubusercontent.com/kubev2v/mtv-skills/main/SHA256SUMS | shasum -a 256 --check --ignore-missing
bash install-tools.sh kubectl-metrics kubectl-debug-queries && rm install-tools.sh
```

## Using `--query` for Filtering

Use `--query` to filter, sort, and project results server-side. Use pipe output to `jq`, `grep`, or other post-processing tools only when `--query` cannot express what you need.

The `--query` flag accepts TSL (Tree Search Language) with four optional clauses:

```
[select <field>, ...] [where <condition>] [order by <field> [asc|desc]] [limit N]
```

**Note:** `select` only affects table output (the default). With `--output json`, all fields are always returned regardless of `select`.

Operators: `=`, `!=`, `<`, `>`, `<=`, `>=`, `like` (% wildcard), `ilike` (case-insensitive), `~=` (regex), `and`, `or`, `not`, `in [...]`, `between X and Y`.

Before writing queries, discover actual field names with `--output json`:

```bash
oc debug-queries list --resource pods --namespace openshift-storage --limit 2 --output json
```

## 1. Ceph Cluster Health

### Quick health status via metrics

```bash
oc metrics query --query "ceph_health_status"
```

Health values: 0=OK, 1=WARN, 2=ERR.

### Capacity overview

```bash
oc metrics query --query "ceph_cluster_total_bytes"
oc metrics query --query "ceph_cluster_total_used_bytes"
oc metrics query --query "ceph_cluster_total_used_bytes / ceph_cluster_total_bytes * 100"
```

### CephCluster CR status

```bash
oc debug-queries get --resource cephcluster --namespace openshift-storage --output json
```

Health states:
- `HEALTH_OK` -- cluster is healthy
- `HEALTH_WARN` -- degraded but functional (backfillfull, nearfull, degraded PGs)
- `HEALTH_ERR` -- critical, writes may be blocked (full OSDs, too few OSDs, down PGs)

## 2. OSD Status

### OSD metrics

```bash
oc metrics query --query "ceph_osd_stat_bytes"
oc metrics query --query "ceph_osd_stat_bytes_used"
oc metrics query --query "rate(ceph_osd_op_latency_sum[5m]) / rate(ceph_osd_op_latency_count[5m])"
```

### OSD pods

```bash
oc debug-queries list --resource pods --namespace openshift-storage --selector "app=rook-ceph-osd"
oc debug-queries list --resource pods --namespace openshift-storage --query "where name ~= '.*osd-prepare.*'"
```

### OSD backing PVCs

```bash
oc debug-queries list --resource pvc --namespace openshift-storage --selector "app=rook-ceph-osd"
```

## 3. Placement Group Health

```bash
oc metrics query --query "ceph_pg_total"
oc metrics query --query "ceph_pg_active"
oc metrics query --query "ceph_pg_degraded"
```

## 4. Pool Statistics

```bash
oc metrics query --query "ceph_pool_percent_used * 100"
oc metrics query --query "rate(ceph_pool_rd[5m])"
oc metrics query --query "rate(ceph_pool_wr[5m])"
oc metrics query --query "ceph_pool_stored"
oc metrics query --query "ceph_pool_max_avail"
```

## 5. CSI Provisioner Pods

PVC provisioning is handled by CSI driver pods. If these are unhealthy, no volumes can be created.

```bash
oc debug-queries list --resource pods --namespace openshift-storage --query "where name ~= '.*rbd.*ctrlplugin.*'"
oc debug-queries list --resource pods --namespace openshift-storage --query "where name ~= '.*cephfs.*ctrlplugin.*'"
oc debug-queries list --resource pods --namespace openshift-storage --query "where name ~= '.*rbd.*nodeplugin.*'"
```

Check CSI provisioner logs:

```bash
oc debug-queries logs --name <rbd-ctrlplugin-pod> --namespace openshift-storage --container csi-rbdplugin --tail 50
```

## 6. PVC and PV Diagnosis

```bash
oc debug-queries list --resource pvc --all-namespaces --query "where status.phase = 'Pending'"
oc debug-queries get --resource pvc --name <pvc-name> --namespace <namespace>
oc debug-queries list --resource pv --all-namespaces --query "where status.phase = 'Released'"
oc debug-queries list --resource storageclass --all-namespaces
```

## 7. Common Problems and Remediation

### OSDs Full (HEALTH_ERR: full osd(s))

**Symptoms**: PVCs stuck in Pending, provisioning errors with `DeadlineExceeded` or `operation already exists`.

**Diagnosis**:

```bash
oc metrics query --query "ceph_health_status"
oc metrics query --query "ceph_osd_stat_bytes_used / ceph_osd_stat_bytes * 100"
oc debug-queries get --resource cephcluster --namespace openshift-storage --output json
```

Look for `OSD_FULL` and `POOL_FULL` messages in the CephCluster status.

**Remediation**: See "Requires Shell" section below for `oc delete pv` and `ceph osd set-full-ratio`.

### OSDs Nearfull / Backfillfull (HEALTH_WARN)

**Symptoms**: Cluster functional but approaching full. Warnings about `nearfull` or `backfillfull` OSDs.

**Remediation**:
- Clean up unused PVCs and Released PVs
- Delete completed migration data no longer needed
- Plan capacity expansion before reaching full threshold (85%)

### Degraded PGs

**Symptoms**: `HEALTH_WARN` with messages about degraded or undersized placement groups.

**Diagnosis**:

```bash
oc metrics query --query "ceph_pg_degraded"
oc metrics query --query "ceph_pg_total - ceph_pg_active"
oc debug-queries events --namespace openshift-storage --query "where type = 'Warning'"
```

**Remediation**:
- If an OSD is down, check the OSD pod and its node
- If a node is down, Ceph will self-heal once the node returns
- If an OSD is permanently lost, Ceph will rebalance automatically (may take time)

### CSI Provisioner Not Responding

**Symptoms**: PVC events say "waiting for external provisioner" but no `ProvisioningFailed` errors.

**Diagnosis**:

```bash
oc debug-queries list --resource pods --namespace openshift-storage --query "where name ~= '.*ctrlplugin.*'"
oc debug-queries logs --name <rbd-ctrlplugin-pod> --namespace openshift-storage --container csi-rbdplugin --tail 100
```

**Remediation**:
- Restart the CSI controller pod if it's stuck
- Check if the Ceph cluster is reachable from the CSI pod
- Verify the StorageClass references a valid pool and secret

### Pools Full but OSDs Not Full

**Symptoms**: `POOL_FULL` warning but individual OSDs have space.

**Diagnosis**:

```bash
oc metrics query --query "ceph_pool_percent_used * 100"
oc metrics query --query "ceph_osd_stat_bytes_used / ceph_osd_stat_bytes * 100"
```

**Remediation**:
- A pool may have a quota set -- check and raise it
- Rebalance may be needed if data is unevenly distributed

## 8. Operator Health

```bash
oc debug-queries list --resource pods --namespace openshift-storage --query "where name ~= '.*ocs-operator.*|.*odf-operator.*|.*rook-ceph-operator.*'"
oc debug-queries logs --name deployment/rook-ceph-operator --namespace openshift-storage --tail 50
```

Check for high restart counts:

```bash
oc metrics query --query "topk(10, sort_desc(kube_pod_container_status_restarts_total))"
```

## 9. Preventive Checks

Run these periodically to avoid surprise outages:

```bash
oc metrics query --query "ceph_cluster_total_used_bytes / ceph_cluster_total_bytes * 100"
oc debug-queries list --resource pv --all-namespaces --query "where status.phase = 'Released'"
oc debug-queries list --resource pvc --all-namespaces --query "where status.phase = 'Pending'"
```

Act when usage exceeds 70% -- start cleaning up or expanding capacity before hitting the 85% full threshold.

---

## Requires Shell

These remediation operations require shell access:

### Delete Released PVs to reclaim space

```bash
oc get pv --field-selector status.phase=Released
oc delete pv <released-pv-names>
```

### Temporarily raise the full ratio (when Ceph is blocking all writes)

```bash
MON_POD=$(oc -n openshift-storage get pods -l app=rook-ceph-mon -o jsonpath='{.items[0].metadata.name}')
MON_ADDR=$(oc -n openshift-storage get pod $MON_POD -o jsonpath='{.spec.containers[0].env[?(@.name=="ROOK_CEPH_MON_HOST")].value}' | sed 's/\[//;s/\]//')

# Raise to 0.92 to unblock writes temporarily
oc -n openshift-storage exec $MON_POD -c mon -- \
  ceph -m $MON_ADDR --keyring /etc/ceph/keyring-store/keyring \
  osd set-full-ratio 0.92

# After space is freed, reset to default
oc -n openshift-storage exec $MON_POD -c mon -- \
  ceph -m $MON_ADDR --keyring /etc/ceph/keyring-store/keyring \
  osd set-full-ratio 0.85
```

## Self-Learning Rule

When you need to discover available flags or verify syntax:

```bash
oc debug-queries list --help
oc debug-queries logs --help
oc metrics query --help
```
