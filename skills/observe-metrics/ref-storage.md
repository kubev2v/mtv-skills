# Storage Metrics (Ceph / ODF)

Queries, labels, and metrics for Ceph/ODF storage on OpenShift. See [SKILL.md](SKILL.md) for general usage.

## Cluster-wide storage health

```bash
oc metrics query --query "ceph_health_status"
```

Health values: 0=OK, 1=WARN, 2=ERR.

## Storage capacity

```bash
oc metrics query --query "ceph_cluster_total_bytes"
oc metrics query --query "ceph_cluster_total_used_bytes"
oc metrics query --query "ceph_cluster_total_used_bytes / ceph_cluster_total_bytes * 100"
```

## Pool-level statistics

```bash
oc metrics query --query "ceph_pool_percent_used * 100"
```

## Pool I/O rates

```bash
oc metrics query --query "rate(ceph_pool_rd[5m])"
oc metrics query --query "rate(ceph_pool_wr[5m])"
```

## OSD operation latency

```bash
oc metrics query --query "rate(ceph_osd_op_latency_sum[5m]) / rate(ceph_osd_op_latency_count[5m])"
```

## Placement group health

```bash
oc metrics query --query "ceph_pg_total"
oc metrics query --query "ceph_pg_degraded"
```

## Available labels on ceph_* metrics

| Label | Description | Example values |
|-------|-------------|----------------|
| `pool_id` | Ceph pool identifier (pool-level metrics) | `1`, `2`, `3`, `4` |
| `ceph_daemon` | OSD daemon name (OSD-level metrics) | `osd.0`, `osd.1`, `osd.2` |
| `namespace` | Storage operator namespace | `openshift-storage` |
| `managedBy` | Managing resource | `ocs-storagecluster` |
| `job` | Scrape job | `rook-ceph-mgr`, `rook-ceph-exporter` |

## Metrics reference

| Metric | Description |
|--------|-------------|
| `ceph_health_status` | Overall cluster health (0=OK, 1=WARN, 2=ERR) |
| `ceph_cluster_total_bytes` | Total cluster capacity |
| `ceph_cluster_total_used_bytes` | Used cluster capacity |
| `ceph_pool_percent_used` | Per-pool usage percentage |
| `ceph_pool_stored` | Bytes stored per pool |
| `ceph_pool_max_avail` | Available bytes per pool |
| `ceph_pool_rd`, `ceph_pool_wr` | Read/write IOPS per pool |
| `ceph_pool_rd_bytes`, `ceph_pool_wr_bytes` | Read/write bytes per pool |
| `ceph_osd_op_latency_sum/count` | OSD operation latency (use as rate ratio) |
| `ceph_osd_stat_bytes`, `ceph_osd_stat_bytes_used` | Per-OSD capacity and usage |
| `ceph_pg_total`, `ceph_pg_active`, `ceph_pg_degraded` | Placement group counts |
| `node_filesystem_avail_bytes`, `node_filesystem_size_bytes` | Node filesystem capacity |
