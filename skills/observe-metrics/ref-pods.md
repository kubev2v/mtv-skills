# Pod and Container Metrics

Queries, labels, and metrics for pod/container statistics. See [SKILL.md](SKILL.md) for general usage.

## CPU and memory by namespace

### Trend over time (CPU + memory combined in one call)

```bash
oc metrics query-range \
  --query "topk(10, sort_desc(sum by (namespace)(rate(container_cpu_usage_seconds_total[5m]))))" \
  --query "topk(10, sort_desc(sum by (namespace)(container_memory_working_set_bytes)))" \
  --name cpu_cores --name mem_bytes \
  --start "-1h" --step 60s
```

### Instant snapshot

```bash
oc metrics query --query "topk(10, sort_desc(sum by (namespace)(rate(container_cpu_usage_seconds_total[5m]))))"
oc metrics query --query "topk(10, sort_desc(sum by (namespace)(container_memory_working_set_bytes)))"
```

## Pod status and restarts

### Pod phase summary

```bash
oc metrics query --query "count by (phase)(kube_pod_status_phase == 1)"
```

### Top restarting containers

```bash
oc metrics query --query "topk(10, sort_desc(kube_pod_container_status_restarts_total))"
```

### Restart rate trend

```bash
oc metrics query-range \
  --query "topk(10, sort_desc(increase(kube_pod_container_status_restarts_total[10m])))" \
  --start "-2h" --step 60s
```

## Pod count by namespace

```bash
oc metrics query --query "topk(15, count by (namespace)(kube_pod_info))"
```

## Available labels on pod/container metrics

| Label | Description | Example values |
|-------|-------------|----------------|
| `namespace` | Pod namespace | `konveyor-forklift`, `openshift-cnv` |
| `pod` | Pod name | `forklift-controller-6df77f6bf5-jtt7q` |
| `container` | Container name | `main`, `inventory`, `extract` |
| `node` | Node the pod runs on | `worker-0`, `worker-1` |
| `phase` | Pod phase (on status metrics) | `Running`, `Pending`, `Failed`, `Succeeded` |
| `uid` | Pod UID | `793fb1cb-3e58-4eef-b95a-733f237365a3` |
| `created_by_kind` | Owner resource kind (on kube_pod_info) | `ReplicaSet`, `DaemonSet`, `StatefulSet` |
| `created_by_name` | Owner resource name (on kube_pod_info) | `forklift-controller-6df77f6bf5` |
| `host_ip` | Node IP (on kube_pod_info) | `192.168.0.77` |
| `pod_ip` | Pod IP (on kube_pod_info) | `10.129.3.3` |

## Metrics reference

| Metric | Description |
|--------|-------------|
| `kube_pod_info` | Pod metadata (node, namespace, IPs, owner) |
| `kube_pod_status_phase` | Pod phase (Running/Pending/Failed/Succeeded) |
| `kube_pod_container_status_restarts_total` | Container restart count |
| `kube_pod_container_status_waiting_reason` | Waiting reason (CrashLoopBackOff, ImagePullBackOff, etc.) |
| `container_cpu_usage_seconds_total` | Container CPU usage |
| `container_memory_working_set_bytes` | Container memory usage |
| `namespace:container_cpu_usage:sum` | Pre-aggregated CPU by namespace |
| `namespace:container_memory_usage_bytes:sum` | Pre-aggregated memory by namespace |
