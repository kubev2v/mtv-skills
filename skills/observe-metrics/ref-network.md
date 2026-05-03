# Network Traffic Metrics

Queries, labels, and metrics for container and node network traffic. See [SKILL.md](SKILL.md) for general usage.

## Network traffic by namespace

### Instant snapshot (top talkers)

```bash
oc metrics query --query "topk(10, sort_desc(sum by (namespace)(rate(container_network_receive_bytes_total[5m]))))"
```

### Trend over time (RX + TX combined in one call)

Replace `TARGET_NS` with the namespace to inspect:

```bash
oc metrics query-range \
  --query "sum(rate(container_network_receive_bytes_total{namespace=\"TARGET_NS\"}[5m]))" \
  --query "sum(rate(container_network_transmit_bytes_total{namespace=\"TARGET_NS\"}[5m]))" \
  --name rx_bytes_per_sec --name tx_bytes_per_sec \
  --start "-1h" --step 60s
```

### All-namespace RX + TX trend

```bash
oc metrics query-range \
  --query "topk(10, sort_desc(sum by (namespace)(rate(container_network_receive_bytes_total[5m]))))" \
  --query "topk(10, sort_desc(sum by (namespace)(rate(container_network_transmit_bytes_total[5m]))))" \
  --name rx_bytes_per_sec --name tx_bytes_per_sec \
  --start "-1h" --step 60s
```

## Network traffic by pod in a namespace

Replace `TARGET_NS` with the namespace to inspect:

### Trend over time (RX + TX combined in one call)

```bash
oc metrics query-range \
  --query "topk(10, sum by (pod)(rate(container_network_receive_bytes_total{namespace=\"TARGET_NS\"}[5m])))" \
  --query "topk(10, sum by (pod)(rate(container_network_transmit_bytes_total{namespace=\"TARGET_NS\"}[5m])))" \
  --name rx_bytes_per_sec --name tx_bytes_per_sec \
  --start "-1h" --step 60s
```

## Network errors and drops

### Combined errors trend

```bash
oc metrics query-range \
  --query "sum by (namespace)(rate(container_network_receive_errors_total[5m]))" \
  --query "sum by (namespace)(rate(container_network_transmit_errors_total[5m]))" \
  --name rx_errors --name tx_errors \
  --start "-1h" --step 60s
```

### Instant error total

```bash
oc metrics query --query "topk(10, sum by (namespace)(rate(container_network_receive_errors_total[5m])) + sum by (namespace)(rate(container_network_transmit_errors_total[5m])))"
```

## Node-level network throughput

```bash
oc metrics query --query "instance:node_network_receive_bytes_excluding_lo:rate1m + instance:node_network_transmit_bytes_excluding_lo:rate1m"
```

## Available labels on network metrics

| Label | Description | Example values |
|-------|-------------|----------------|
| `namespace` | Pod namespace | `openshift-storage`, `konveyor-forklift` |
| `pod` | Pod name | `forklift-controller-6df77f6bf5-jtt7q` |
| `interface` | Network interface (per-pod metrics) | `eth0` |
| `instance` | Node instance (node-level metrics) | `10.0.0.5:9100` |
| `node` | Node name (node-level metrics) | `worker-0` |

## Metrics reference

| Metric | Description |
|--------|-------------|
| `container_network_receive_bytes_total` | Bytes received per pod/namespace |
| `container_network_transmit_bytes_total` | Bytes transmitted per pod/namespace |
| `container_network_receive_errors_total` | Receive errors per pod/namespace |
| `container_network_transmit_errors_total` | Transmit errors per pod/namespace |
| `container_network_receive_packets_dropped_total` | Dropped receive packets |
| `container_network_transmit_packets_dropped_total` | Dropped transmit packets |
| `node_network_receive_bytes_total` | Bytes received per node/interface |
| `node_network_transmit_bytes_total` | Bytes transmitted per node/interface |
| `instance:node_network_receive_bytes_excluding_lo:rate1m` | Pre-computed node receive rate |
