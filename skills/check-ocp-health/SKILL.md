---
name: check-ocp-health
description: General OpenShift (OCP) cluster health check. Use when the cluster is unhealthy, nodes are NotReady, operators are degraded, pods are crashing, etcd is slow, networking issues occur, or a general cluster diagnosis is needed.
---

# OpenShift Cluster Health Check

Use this guide for general OCP cluster health diagnosis and remediation.

## Required CLI Tools

This skill requires:
- `oc debug-queries` ([kubectl-debug-queries](https://github.com/yaacov/kubectl-debug-queries)) -- for listing resources, logs, events
- `oc metrics` ([kubectl-metrics](https://github.com/yaacov/kubectl-metrics)) -- for CPU/memory/node metrics

If any tool is missing, install with the secure version-pinned installer:

```bash
curl -sSLO https://raw.githubusercontent.com/kubev2v/mtv-skills/main/tools/install-tools.sh
curl -sSL  https://raw.githubusercontent.com/kubev2v/mtv-skills/main/SHA256SUMS | shasum -a 256 --check --ignore-missing
bash install-tools.sh kubectl-debug-queries kubectl-metrics && rm install-tools.sh
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
oc debug-queries list --resource pods --namespace <namespace> --limit 2 --output json
```

## Quick Triage

Check these in order for a fast overview:

```bash
oc debug-queries list --resource nodes --all-namespaces
oc debug-queries list --resource clusteroperators --all-namespaces
oc debug-queries list --resource pods --all-namespaces --query "where status.phase != 'Running' and status.phase != 'Succeeded'" --limit 30
oc debug-queries events --all-namespaces --query "where type = 'Warning'" --sort-by time_desc --limit 20
```

## 1. Nodes

```bash
oc debug-queries list --resource nodes --all-namespaces
oc debug-queries get --resource node --name <node-name> --namespace default
```

Resource usage:

```bash
oc metrics query --query "avg(instance:node_cpu:ratio) * 100"
oc metrics query --query "(1 - sum(node_memory_MemAvailable_bytes) / sum(node_memory_MemTotal_bytes)) * 100"
oc metrics query --query "sum(kube_node_status_condition{condition='Ready',status='true'})"
```

Pods on a specific node:

```bash
oc debug-queries list --resource pods --all-namespaces --query "where spec.nodeName = '<node-name>'"
```

### Node NotReady

**Diagnosis**:

```bash
oc debug-queries get --resource node --name <node-name> --namespace default
oc debug-queries events --all-namespaces --name <node-name> --sort-by time_desc
```

**Common causes**:
- Kubelet not running
- Network partition -- node can't reach API server
- Disk pressure -- node disk full
- Memory pressure -- OOM conditions

**Remediation**:
- For disk pressure: clean up logs, images, or unused containers on the node
- For kubelet issues: restart kubelet on the node (requires shell)
- For unrecoverable nodes: cordon, drain, and replace

## 2. Cluster Operators

```bash
oc debug-queries list --resource clusteroperators --all-namespaces
oc debug-queries get --resource clusteroperator --name <operator-name> --namespace default
```

Key operators to watch: `etcd`, `kube-apiserver`, `openshift-controller-manager`, `ingress`, `monitoring`, `storage`, `machine-config`.

### Degraded Operator

**Diagnosis**: Check the operator's namespace for unhealthy pods:

```bash
oc debug-queries list --resource pods --namespace openshift-<operator-name> --query "where status.phase != 'Running'"
oc debug-queries logs --name <pod-name> --namespace openshift-<operator-name> --tail 50
```

Before writing log queries, discover the actual field names and level values:

```bash
oc debug-queries logs --name <pod-name> --namespace openshift-<operator-name> --tail 5 --output json
```

Level strings vary by workload. Controller-runtime logs normalize to `ERROR`, `WARN`, `INFO`, `DEBUG`. klog-format logs (used by etcd and other Kubernetes components) may normalize to `E`, `W`, `I`, `F`. Always check with `--output json` first to see actual level values.

Full-text search when you don't know which field contains the value:

```bash
oc debug-queries logs --name <pod-name> --namespace openshift-<operator-name> --tail 200 --query "where raw_line ~= '.*<search-term>.*'"
```

**Remediation**:
- Restart the operator pod if it's stuck
- Check if a dependent service (etcd, API server) is down
- Review MachineConfigPool if `machine-config` operator is degraded

## 3. etcd Health

```bash
oc debug-queries get --resource clusteroperator --name etcd --namespace default
oc debug-queries list --resource pods --namespace openshift-etcd --selector "app=etcd"
oc debug-queries logs --name deployment/etcd-operator --namespace openshift-etcd-operator --tail 50 --query "where level = 'ERROR' or level = 'WARN'"
```

### etcd Slow or Degraded

**Common causes**:
- Slow disk I/O -- etcd needs fast storage (SSD recommended)
- Network latency between control plane nodes
- Database too large (fragmentation)

**Remediation**:
- Check disk performance on control plane nodes
- Defragment etcd if DB size is large (done automatically by the operator)
- Ensure control plane nodes have low-latency network

## 4. API Server

```bash
oc debug-queries list --resource pods --namespace openshift-kube-apiserver --selector "app=openshift-kube-apiserver"
oc debug-queries events --namespace openshift-kube-apiserver --sort-by time_desc --limit 10
```

## 5. Pods and Workloads

```bash
oc debug-queries list --resource pods --all-namespaces --query "where status.phase = 'Failed'" --limit 20
oc debug-queries list --resource pods --all-namespaces --query "where status.phase = 'Pending'"
```

Pods with high restart counts:

```bash
oc metrics query --query "topk(10, sort_desc(kube_pod_container_status_restarts_total))"
```

### CrashLoopBackOff

**Diagnosis**:

```bash
oc debug-queries get --resource pod --name <pod-name> --namespace <namespace>
oc debug-queries logs --name <pod-name> --namespace <namespace> --previous
```

**Common causes**: missing config/secrets, OOM, application errors, image issues.

### ImagePullBackOff

**Diagnosis**:

```bash
oc debug-queries events --namespace <namespace> --name <pod-name> --resource Pod
```

**Common causes**: wrong image name, registry auth missing, network issues to registry.

## 6. Networking

```bash
oc debug-queries list --resource pods --namespace openshift-ingress
oc debug-queries get --resource clusteroperator --name network --namespace default
oc debug-queries list --resource pods --namespace openshift-network-operator
```

### Service/Route Not Reachable

**Diagnosis**:

```bash
oc debug-queries list --resource endpoints --namespace <namespace>
oc debug-queries list --resource pods --namespace openshift-ingress
oc debug-queries logs --name <router-pod> --namespace openshift-ingress --tail 20
```

## 7. Certificates

```bash
oc debug-queries list --resource certificates --all-namespaces
oc debug-queries get --resource clusteroperator --name kube-apiserver --namespace default
```

## 8. MachineConfigPool (Node Updates)

```bash
oc debug-queries list --resource machineconfigpool --all-namespaces
oc debug-queries get --resource machineconfigpool --name worker --namespace default
oc debug-queries get --resource machineconfigpool --name master --namespace default
```

### Nodes Stuck Updating

**Diagnosis**:

```bash
oc debug-queries list --resource machineconfigpool --all-namespaces --output json
```

**Remediation**:
- Check the machine-config-daemon pod on the stuck node
- Review logs for the machine-config-daemon pod on that node
- A degraded MCP often means a config failed to apply -- fix the MachineConfig or remove it

## 9. Cluster Version and Updates

```bash
oc debug-queries list --resource clusterversion --all-namespaces
oc debug-queries get --resource clusterversion --name version --namespace default
```

## 10. Resource Quotas and Limits

```bash
oc debug-queries list --resource resourcequota --all-namespaces
oc debug-queries list --resource limitrange --all-namespaces
oc debug-queries get --resource resourcequota --name <quota-name> --namespace <namespace>
```

## 11. Full Health Report

When the user asks for a cluster health report, run these commands **in parallel** and present the results as a formatted summary with tables:

**Cluster & nodes:**

```bash
oc debug-queries list --resource clusterversion --all-namespaces
oc debug-queries list --resource nodes --all-namespaces
oc debug-queries list --resource clusteroperators --all-namespaces
oc debug-queries list --resource pods --all-namespaces --query "where status.phase != 'Running' and status.phase != 'Succeeded'" --limit 15
```

**Resource usage:**

```bash
oc metrics query --query "avg(instance:node_cpu:ratio) * 100"
oc metrics query --query "(1 - sum(node_memory_MemAvailable_bytes) / sum(node_memory_MemTotal_bytes)) * 100"
oc metrics query --query "sum(kube_node_status_condition{condition='Ready',status='true'})"
```

**Storage health:**

```bash
oc metrics query --query "ceph_health_status"
oc metrics query --query "ceph_cluster_total_used_bytes / ceph_cluster_total_bytes * 100"
```

### How to present the report

Format the results as a concise summary with:

- **Cluster Overview** section: version, node count/status, operator health, problem pods
- **Storage** section: Ceph health, capacity used/available/percentage as a table
- **Memory & CPU** section: per-node usage as a table, highlight nodes above 70% memory or 80% CPU

Flag any issues found with brief remediation hints. If everything is healthy, say so clearly.

---

## Requires Shell

These operations require shell access:

### API server raw health check

```bash
oc get --raw /healthz
```

### etcd member health (exec into etcd pod)

```bash
oc -n openshift-etcd exec $(oc -n openshift-etcd get pods -l app=etcd -o jsonpath='{.items[0].metadata.name}') -c etcd -- \
  etcdctl member list -w table

oc -n openshift-etcd exec $(oc -n openshift-etcd get pods -l app=etcd -o jsonpath='{.items[0].metadata.name}') -c etcd -- \
  etcdctl endpoint health --cluster -w table

oc -n openshift-etcd exec $(oc -n openshift-etcd get pods -l app=etcd -o jsonpath='{.items[0].metadata.name}') -c etcd -- \
  etcdctl endpoint status --cluster -w table
```

### DNS resolution test

```bash
oc run dns-test --rm -i --restart=Never --image=busybox -- nslookup kubernetes.default.svc.cluster.local
```

### Certificate expiry inspection

```bash
oc get secret -n openshift-kube-apiserver -o json | \
  python3 -c "import json,sys; [print(i['metadata']['name']) for i in json.load(sys.stdin)['items'] if 'cert' in i['metadata']['name'].lower()]" 2>/dev/null
```

## Self-Learning Rule

When you need to discover available flags or verify syntax:

```bash
oc debug-queries list --help
oc debug-queries logs --help
oc metrics query --help
```
