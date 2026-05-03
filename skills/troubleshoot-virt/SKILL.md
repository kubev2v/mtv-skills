---
name: troubleshoot-virt
description: Troubleshoot stuck VMs and migrations in OpenShift Virtualization and MTV/Forklift. Use when VMs won't start, DataVolumes are stuck, migrations fail, or cluster resources are exhausted.
---

# Troubleshooting VMs and Migrations

Use this guide when VMs or migrations are stuck, failing, or behaving unexpectedly.

## Required CLI Tools

This skill requires:
- `oc debug-queries` ([kubectl-debug-queries](https://github.com/yaacov/kubectl-debug-queries)) -- for listing resources, logs, events
- `oc mtv` ([kubectl-mtv](https://github.com/yaacov/kubectl-mtv)) -- for MTV health, plans, providers
- `oc metrics` ([kubectl-metrics](https://github.com/yaacov/kubectl-metrics)) -- for node resource usage

If any tool is missing, install with:

```bash
curl -sSL https://raw.githubusercontent.com/yaacov/kubectl-debug-queries/main/install.sh | bash
curl -sSL https://raw.githubusercontent.com/yaacov/kubectl-mtv/main/install.sh | bash
curl -sSL https://raw.githubusercontent.com/yaacov/kubectl-metrics/main/install.sh | bash
```

## Quick Triage Checklist

When something is stuck, check these in order:

1. **Node resources** -- is the cluster out of CPU/memory/pods?
2. **Storage** -- is the default StorageClass set? Are PVCs bound? Are DataVolumes progressing?
3. **VM status** -- what does the VM/VMI conditions say?
4. **Pod status** -- is the virt-launcher or importer pod stuck/erroring?
5. **Events** -- what do namespace events say?

## 1. Node Resources

```bash
oc debug-queries list --resource nodes --all-namespaces

oc metrics query --query "avg(instance:node_cpu:ratio) * 100"
oc metrics query --query "(1 - sum(node_memory_MemAvailable_bytes) / sum(node_memory_MemTotal_bytes)) * 100"
oc metrics query --query "sum(kube_node_status_condition{condition='Ready',status='true'})"
```

Check what's consuming resources on a specific node:

```bash
oc debug-queries list --resource pods --all-namespaces --query "where spec.nodeName = '<node-name>'"
```

Check for node conditions:

```bash
oc debug-queries get --resource node --name <node-name> --namespace default
```

If nodes show `MemoryPressure` or `DiskPressure`, VMs and migration pods cannot be scheduled.

## 2. Storage

### Default StorageClass

A default StorageClass is required for DataVolumes to work. Without it, PVCs won't provision.

```bash
oc debug-queries list --resource storageclass --all-namespaces
```

If none is default, set one (requires shell):

```bash
oc annotate storageclass <name> storageclass.kubernetes.io/is-default-class=true
```

### StorageProfile

CDI uses StorageProfiles to determine accessModes and volumeMode for each StorageClass. A misconfigured profile can cause DataVolumes to fail.

```bash
oc debug-queries list --resource storageprofile --all-namespaces
oc debug-queries get --resource storageprofile --name <storageclass-name> --namespace default --output yaml
```

A healthy StorageProfile has `status.claimPropertySets` populated with accessModes and volumeMode.

### DataVolumes (DV)

DataVolumes manage the lifecycle of importing/cloning disk images into PVCs.

```bash
oc debug-queries list --resource dv --namespace <namespace>
oc debug-queries get --resource dv --name <dv-name> --namespace <namespace>
```

Common DV phases: `ImportScheduled` -> `ImportInProgress` -> `Succeeded`. `Pending` (stuck) usually means a storage or scheduling problem.

### PVCs

```bash
oc debug-queries list --resource pvc --namespace <namespace>
oc debug-queries get --resource pvc --name <pvc-name> --namespace <namespace>
```

Stuck in Pending = no StorageClass, no capacity, or WaitForFirstConsumer binding.

### CDI Importer/Cloner Pods

When a DataVolume is importing, CDI creates temporary pods. If those pods are stuck, the DV won't progress.

```bash
oc debug-queries list --resource pods --namespace <namespace> --query "where name ~= '.*importer.*|.*clone.*|.*upload.*'"
oc debug-queries get --resource pod --name <importer-pod> --namespace <namespace>
oc debug-queries logs --name <importer-pod> --namespace <namespace>
```

## 3. VM Status

```bash
oc debug-queries get --resource vm --name <vm-name> --namespace <namespace>
oc debug-queries get --resource vmi --name <vm-name> --namespace <namespace>
```

Common stuck reasons:
- Unschedulable: not enough CPU/memory on any node
- DataVolumeError: boot disk DV failed
- ErrImagePull: containerdisk image not found
- Guest agent not connected: VM running but no agent

## 4. Pod Status (virt-launcher)

Each running VM has a `virt-launcher` pod. If the pod is stuck, the VM won't start.

```bash
oc debug-queries list --resource pods --namespace <namespace> --selector "kubevirt.io=virt-launcher"
oc debug-queries get --resource pod --name <virt-launcher-pod> --namespace <namespace>
oc debug-queries logs --name <virt-launcher-pod> --namespace <namespace>
oc debug-queries logs --name <virt-launcher-pod> --namespace <namespace> --container compute
```

## 5. Events

Namespace events often reveal the root cause faster than anything else.

```bash
oc debug-queries events --namespace <namespace> --sort-by time_desc
oc debug-queries events --namespace <namespace> --query "where type = 'Warning'"
oc debug-queries events --namespace <namespace> --name <vm-name> --resource VirtualMachine
```

## 6. Migration Troubleshooting (MTV/Forklift)

### Discover the Forklift namespace

The operator namespace varies by installation (commonly `openshift-mtv` or `konveyor-forklift`). Always discover it first:

```bash
oc mtv health --all-namespaces --skip-logs
```

The health output includes "Namespace: <actual-namespace>". Use that value for all subsequent commands in this section.

### Quick health check

The `health` command includes built-in log analysis by default. Use one of:

```bash
oc mtv health --all-namespaces
```

This includes log analysis (default 100 lines per pod). For deeper log analysis:

```bash
oc mtv health --all-namespaces --log-lines 200
```

For a fast check without log analysis:

```bash
oc mtv health --all-namespaces --skip-logs
```

### Forklift pods

Forklift runs in the namespace discovered above.

```bash
oc debug-queries list --resource pods --namespace <forklift-namespace>
oc debug-queries logs --name deployment/forklift-controller --namespace <forklift-namespace> --container main
oc debug-queries logs --name deployment/forklift-controller --namespace <forklift-namespace> --container inventory
```

Key pods: `forklift-controller` (main migration controller), `forklift-api`, `forklift-validation`, `forklift-volume-populator-controller`.

### Querying Forklift logs

Before writing log queries, discover the actual field names and values:

```bash
oc debug-queries logs --name deployment/forklift-controller --namespace <forklift-namespace> --container main --tail 5 --output json
```

This shows the parsed fields (`level`, `message`, `logger`, `source`, `fields.*`) and their actual values for the target workload.

Forklift controllers use the `logger` field (e.g., `plan|ocp`, `storageMap|ocp`, `provider`) rather than `source` (which is empty). Filter by logger:

```bash
oc debug-queries logs --name deployment/forklift-controller --namespace <forklift-namespace> --container main --tail 200 --query "where logger ~= 'plan.*'"
```

Tip: If a level query returns no matches, check what levels the workload actually uses. Level strings vary by workload -- controller-runtime logs normalize to `ERROR`, `INFO`, `DEBUG`; klog-format logs may normalize to `E`, `W`, `I`, `F`. Run with `--output json` and `--tail 5` first to see actual level values.

Filter logs by structured fields (e.g., provider name):

```bash
oc debug-queries logs --name deployment/forklift-controller --namespace <forklift-namespace> --container main --tail 200 --query "where fields.provider ~= '.*<provider-name>.*'"
```

For newest-first log output (useful when checking recent errors):

```bash
oc debug-queries logs --name deployment/forklift-controller --namespace <forklift-namespace> --container main --tail 200 --sort-by time_desc --query "where level = 'ERROR'"
```

Full-text search when you don't know which field contains the value:

```bash
oc debug-queries logs --name deployment/forklift-controller --namespace <forklift-namespace> --container main --tail 200 --query "where raw_line ~= '.*<search-term>.*'"
```

### Migration plan status

```bash
oc mtv get plan -n <namespace>
oc mtv get plan --name <plan-name> -n <namespace>
oc mtv get plan --name <plan-name> --vms -n <namespace>
oc mtv get plan --name <plan-name> --disk -n <namespace>
oc mtv describe plan --name <plan-name> -n <namespace>
```

### Debug a failing plan

Forklift reports most failures through status conditions and Kubernetes events, not ERROR-level logs. Prioritize these over log searching:

1. Check plan status conditions first:

```bash
oc debug-queries get --resource plans --name <plan-name> --namespace <ns> --output json --query "select name, status.conditions"
```

2. Check events for the plan and its mappings:

```bash
oc debug-queries events --namespace <ns> --query "where involvedObject.name ~= '.*<plan-name>.*'"
```

3. Check mapping status conditions:

```bash
oc debug-queries get --resource storagemaps --name <storage-map-name> --namespace <ns> --output json --query "select name, status.conditions"
oc debug-queries get --resource networkmaps --name <network-map-name> --namespace <ns> --output json --query "select name, status.conditions"
```

4. Only then check controller logs for reconcile context:

```bash
oc debug-queries logs --name deployment/forklift-controller --namespace <forklift-namespace> --container main --since 10m --tail 200 --query "where fields.plan ~= '.*<plan-name>.*'"
```

### Migration pods (per-VM)

During migration, Forklift creates pods in the target namespace (not the operator namespace):

```bash
oc debug-queries list --resource pods --namespace <namespace> --query "where name ~= '.*virt-v2v.*|.*populator.*|.*importer.*'"
oc debug-queries logs --name <virt-v2v-pod> --namespace <namespace>
```

### Provider connectivity

```bash
oc mtv get provider -n <namespace>
oc mtv describe provider --name <provider-name> -n <namespace>
```

## 7. KubeVirt Operator Pods

The KubeVirt operator components run in `openshift-cnv` (OpenShift) or `kubevirt` namespace.

```bash
oc debug-queries list --resource pods --namespace openshift-cnv --query "where name ~= '.*virt-operator.*|.*virt-controller.*|.*virt-handler.*|.*virt-api.*|.*cdi-.*'"
```

Check for pod restarts (sign of instability):

```bash
oc metrics query --query "topk(10, sort_desc(kube_pod_container_status_restarts_total))"
```

Logs from key components:

```bash
oc debug-queries logs --name deployment/virt-controller --namespace openshift-cnv
oc debug-queries logs --name deployment/cdi-deployment --namespace openshift-cnv
```

## 8. Common Stuck Scenarios

### VM stuck in Scheduling
- **Cause**: Not enough CPU/memory on any schedulable node
- **Check**: `oc debug-queries list` nodes + `oc metrics query` CPU utilization + `oc debug-queries get` vmi for scheduling errors
- **Fix**: Free up node resources, scale cluster, or use a smaller instance type

### DataVolume stuck in Pending
- **Cause**: No default StorageClass, or StorageProfile misconfigured
- **Check**: `oc debug-queries list` storageclass (look for default), `oc debug-queries get` storageprofile
- **Fix**: Set a default StorageClass, ensure StorageProfile has `claimPropertySets`

### DataVolume stuck in ImportInProgress
- **Cause**: Importer pod failing (network, auth, image not found)
- **Check**: `oc debug-queries list` pods with query for importer, then `oc debug-queries logs`
- **Fix**: Check source URL, credentials, network policies

### Migration plan stuck
- **Cause**: Provider unreachable, disk transfer stalled, converter pod OOM
- **Check**: `oc mtv health`, `oc mtv get plan` with --vms --disk flags, converter pod logs
- **Fix**: Check provider connectivity, increase converter memory via settings, check storage throughput

### VM stuck in Pending after migration
- **Cause**: Target PVCs not bound, insufficient resources for target VM
- **Check**: `oc debug-queries list` pvc, `oc debug-queries get` vmi
- **Fix**: Ensure target storage has capacity, check node resources

## Self-Learning Rule

When you need to discover available flags or verify syntax:

```bash
oc mtv <command> --help
oc debug-queries logs --help
oc metrics query --help
```
