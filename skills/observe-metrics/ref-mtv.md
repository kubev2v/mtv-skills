# Forklift / MTV Migration Metrics

Queries, labels, and metrics for Forklift/MTV VM migrations. See [SKILL.md](SKILL.md) for general usage.

## Migration status and plans

### Instant snapshot

```bash
oc metrics query --query "sum by (status)(mtv_migrations_status_total)"
oc metrics query --query "sum by (status)(mtv_plans_status)"
```

### Status trend over time

```bash
oc metrics query-range \
  --query "sum by (status)(mtv_migrations_status_total)" \
  --query "sum by (status)(mtv_plans_status)" \
  --name migration_status --name plan_status \
  --start "-6h" --step 60s
```

## Migration data transfer and throughput

### Trend over time (throughput combined in one call)

```bash
oc metrics query-range \
  --query "sum(mtv_migration_net_throughput)" \
  --query "sum(mtv_migration_storage_throughput)" \
  --name net_throughput --name storage_throughput \
  --start "-2h" --step 30s
```

### Data transferred + duration trend

```bash
oc metrics query-range \
  --query "sum(mtv_migration_data_transferred_bytes)" \
  --query "sum(mtv_migration_duration_seconds)" \
  --name data_bytes --name duration_sec \
  --start "-6h" --step 60s
```

### Instant snapshot

```bash
oc metrics query --query "sum(mtv_migration_data_transferred_bytes)"
oc metrics query --query "avg(mtv_migration_duration_seconds)"
```

## Migration pod CPU and network traffic

### Trend over time (RX + TX combined in one call)

```bash
oc metrics query-range \
  --query "sum by (pod)(rate(container_network_receive_bytes_total{namespace=\"konveyor-forklift\",pod=~\".*populator.*|.*importer.*\"}[5m]))" \
  --query "sum by (pod)(rate(container_network_transmit_bytes_total{namespace=\"konveyor-forklift\",pod=~\".*populator.*|.*importer.*\"}[5m]))" \
  --name migration_pod_rx --name migration_pod_tx \
  --start "-2h" --step 30s
```

### Populator CPU + all-forklift traffic

```bash
oc metrics query-range \
  --query "sum(rate(container_cpu_usage_seconds_total{namespace=\"konveyor-forklift\",pod=~\".*populator.*\"}[5m]))" \
  --query "sum(rate(container_network_receive_bytes_total{namespace=\"konveyor-forklift\"}[5m])) + sum(rate(container_network_transmit_bytes_total{namespace=\"konveyor-forklift\"}[5m]))" \
  --name populator_cpu_cores --name forklift_traffic_bytes_per_sec \
  --start "-2h" --step 30s
```

## KubeVirt VMI migration metrics

### Pending + running VMI migrations (combined in one call)

```bash
oc metrics query-range \
  --query "sum(kubevirt_vmi_migrations_in_pending_phase)" \
  --query "sum(kubevirt_vmi_migrations_in_running_phase)" \
  --name pending --name running \
  --start "-2h" --step 30s
```

## Available labels on mtv_* metrics

All `mtv_*` metrics share these labels for filtering and grouping:

| Label | Description | Example values |
|-------|-------------|----------------|
| `provider` | Source provider type | `vsphere`, `ovirt`, `openstack`, `ova`, `ec2` |
| `mode` | Migration mode | `Cold`, `Warm` |
| `target` | Target cluster | `Local` (host cluster) or remote cluster name |
| `owner` | User who owns the migration | `admin@example.com` |
| `plan` | Migration plan UUID | `363ce137-dace-4fb4-b815-759c214c9fec` |
| `namespace` | Forklift operator namespace | `konveyor-forklift`, `openshift-mtv` |
| `status` | Migration/plan status (on status metrics) | `Succeeded`, `Failed`, `Executing` |

## Metrics reference

| Metric | Description |
|--------|-------------|
| `mtv_migrations_status_total` | Migration counts by status (succeeded/failed/running) |
| `mtv_plans_status` | Plan-level status counts |
| `mtv_migration_data_transferred_bytes` | Total bytes migrated per plan |
| `mtv_migration_net_throughput` | Migration network throughput |
| `mtv_migration_storage_throughput` | Migration storage throughput |
| `mtv_migration_duration_seconds` | Migration duration per plan |
| `mtv_plan_alert_status` | Alerts on migration plans |
| `mtv_workload_migrations_status_total` | Per-workload migration status (per plan + status) |
| `kubevirt_vmi_migrations_in_pending_phase` | Live VMI migrations pending |
| `kubevirt_vmi_migrations_in_running_phase` | Live VMI migrations in progress |

## Narrowing migration metrics with label filters

Use PromQL label selectors directly in the query to narrow results:

```bash
oc metrics query --query "mtv_migration_data_transferred_bytes{provider=\"vsphere\"}"
oc metrics query --query "mtv_migration_data_transferred_bytes{mode=\"Cold\"}"
oc metrics query --query "mtv_migration_data_transferred_bytes{provider=\"ovirt\", mode=\"Warm\"}"
oc metrics query --query "mtv_migrations_status_total{status=\"Failed\"}"
oc metrics query --query "mtv_workload_migrations_status_total{plan=\"PLAN_UUID\", status=\"Failed\"}"
```

## Grouping migration metrics

```bash
oc metrics query --query "sum by (provider)(mtv_migration_data_transferred_bytes)"
oc metrics query --query "sum by (mode)(mtv_migration_data_transferred_bytes)"
oc metrics query --query "sum by (status, provider)(mtv_migrations_status_total)"
oc metrics query --query "avg by (provider)(mtv_migration_duration_seconds)"
oc metrics query --query "sum by (plan, status)(mtv_workload_migrations_status_total)"
```
