---
name: kubectl-mtv
description: Use the oc mtv CLI to manage VM migrations. Use this skill when the user wants to migrate VMs from vSphere, oVirt, OpenStack, OVA, EC2, or HyperV to OpenShift/KubeVirt.
---

# MTV/Forklift - Migration Toolkit for Virtualization

Manage VM migrations from VMware vSphere, oVirt (RHV), OpenStack, OVA, EC2, and HyperV to OpenShift Virtualization (KubeVirt) using the `oc mtv` CLI.

## Required CLI Tools

This skill requires:
- `oc mtv` ([kubectl-mtv](https://github.com/yaacov/kubectl-mtv)) -- for MTV/Forklift management
- `oc debug-queries` ([kubectl-debug-queries](https://github.com/yaacov/kubectl-debug-queries)) -- for resource/log/event queries

If any tool is missing, install with:

```bash
curl -sSL https://raw.githubusercontent.com/yaacov/kubectl-mtv/main/install.sh | bash
curl -sSL https://raw.githubusercontent.com/yaacov/kubectl-debug-queries/main/install.sh | bash
```

## Getting Help

Always call `--help` before using an unfamiliar command to learn its flags and see examples:

```bash
oc mtv create provider --help
oc mtv create plan --help
oc mtv get inventory vm --help
oc mtv help tsl
oc mtv help karl
```

## Typical Migration Workflow

### 1. Check system health

```bash
oc mtv health
oc mtv health --all-namespaces
oc mtv health --skip-logs
```

The health output shows the Forklift operator namespace. See [Forklift Pod Labels](#forklift-pod-labels) for pod label details.

### 2. Configure settings (e.g., VDDK image for vSphere)

```bash
oc mtv settings set --setting vddk_image --value <registry-url>/vddk
oc mtv settings get --setting vddk_image
oc mtv settings unset --setting vddk_image
oc mtv settings --all
```

To build a VDDK image from the VMware SDK tar:

```bash
oc mtv create vddk-image --tar VMware-vix-disklib-8.0.1.tar.gz --tag quay.io/myorg/vddk:8.0.1 --push
oc mtv create vddk-image --tar VMware-vix-disklib-8.0.1.tar.gz --tag quay.io/myorg/vddk:8.0.1 --push --set-controller-image
```

### 3. Create providers

For vSphere providers, the VDDK init image is required. Check if it is already configured globally:

```bash
oc mtv settings get --setting vddk_image
```

If a global VDDK image is set, you do NOT need `--vddk-init-image` on the provider. If it is not set, prefer setting it globally (if you have permissions). Only use `--vddk-init-image` on the provider as a fallback.

```bash
oc mtv create provider --name host --type openshift -n <namespace>

oc mtv create provider --name my-vsphere --type vsphere \
  --url "https://vcenter.example.com/sdk" \
  --username "admin@vsphere.local" --password "$PASSWORD" \
  -n <namespace>

oc mtv create provider --name my-ovirt --type ovirt \
  --url "https://rhv-manager.example.com/ovirt-engine/api" \
  --username "admin@internal" --password "$PASSWORD" \
  -n <namespace>

oc mtv create provider --name my-ec2 --type ec2 \
  --ec2-region us-east-1 \
  --username "$EC2_KEY" --password "$EC2_SECRET" \
  --auto-target-credentials \
  -n <namespace>

oc mtv create provider --name my-hyperv --type hyperv \
  --url "https://192.168.1.100" \
  --username Administrator --password "$PASSWORD" \
  --smb-url "//192.168.1.100/VMShare" \
  -n <namespace>
```

### 4. List providers and verify

```bash
oc mtv get provider -n <namespace>
oc mtv get provider --all-namespaces
```

### 5. Browse inventory VMs

```bash
oc mtv get inventory vm --provider my-vsphere -n <namespace>

oc mtv get inventory vm --provider my-vsphere -n <namespace> \
  --query "where name ~= 'prod-.*'"

oc mtv get inventory vm --provider my-vsphere -n <namespace> \
  --query "where powerState = 'poweredOn' and memoryMB > 4096"

oc mtv get inventory vm --provider my-vsphere -n <namespace> \
  --query "where cpuCount > 4 and len(disks) > 1"

oc mtv get inventory vm --provider my-vsphere -n <namespace> \
  --query "where name ~= 'web-.*'" --output planvms
```

### 6. Browse other inventory resources

```bash
oc mtv get inventory network --provider my-vsphere -n <namespace>
oc mtv get inventory storage --provider my-vsphere -n <namespace>
oc mtv get inventory host --provider my-vsphere -n <namespace>
oc mtv get inventory cluster --provider my-vsphere -n <namespace>
oc mtv get inventory datacenter --provider my-vsphere -n <namespace>
oc mtv get inventory datastore --provider my-vsphere -n <namespace>
```

### 7. Create a migration plan

#### Prerequisites

A plan requires an OpenShift host (target) provider in the same namespace. Verify one exists:

```bash
oc mtv get provider -n <namespace>
```

If no OpenShift provider is listed, create one:

```bash
oc mtv create provider --name host --type openshift -n <namespace>
```

#### Creating plans

Only `--name`, `--source`, and `--vms` are required. The target provider, network/storage mappings, and other settings are auto-detected. Only add optional flags when you need to override defaults.

```bash
oc mtv create plan --name my-migration --source my-vsphere \
  --vms "vm1,vm2,vm3" -n <namespace>

oc mtv create plan --name my-migration --source my-vsphere \
  --vms "where name ~= 'prod-.*'" -n <namespace>

oc mtv create plan --name my-warm --source my-vsphere \
  --vms critical-vm --migration-type warm -n <namespace>
```

Override defaults only when auto-detection doesn't suit your needs:

```bash
oc mtv create plan --name my-migration --source my-vsphere --target host \
  --vms "vm1,vm2" \
  --default-target-network default \
  --default-target-storage-class standard \
  -n <namespace>
```

#### Verify plan health

Plans referencing invalid storage classes or networks are accepted at creation time but fail at the controller level. Always verify the plan is ready after creating it:

```bash
oc mtv get plan -n <namespace>
```

If READY shows `false`, check conditions:

```bash
oc debug-queries get --resource plans --name <plan-name> --namespace <namespace> --output json --query "select name, status.conditions"
```

### 8. Start migration

```bash
oc mtv start plan --name my-migration -n <namespace>
oc mtv start plan --name "plan1,plan2" -n <namespace>
```

### 9. Monitor migration

```bash
oc mtv get plan -n <namespace>
oc mtv get plan --name my-migration -n <namespace>
oc mtv get plan --name my-migration --vms -n <namespace>
oc mtv get plan --name my-migration --disk -n <namespace>
oc mtv get plan --name my-migration --vms --disk -n <namespace>
oc mtv get plan --vms-table -n <namespace>
oc mtv get plan --vms-table --query "where planStatus = 'Failed'" -n <namespace>
```

### 10. View logs

The `health` command includes built-in log analysis. Use `--skip-logs` to disable and `--log-lines` to control how many lines per pod are analyzed:

```bash
oc mtv health -n <namespace>
oc mtv health --all-namespaces --log-lines 200
```

For targeted log inspection of specific Forklift pods, use `oc debug-queries`. First discover the operator namespace via `oc mtv health` (the output includes "Namespace: <actual-namespace>"):

```bash
oc debug-queries logs --name deployment/forklift-controller --namespace <forklift-namespace> --container main --tail 100
oc debug-queries logs --name deployment/forklift-controller --namespace <forklift-namespace> --container main --tail 100 --query "where level = 'ERROR'"
```

Before writing log queries, discover the actual field names and values:

```bash
oc debug-queries logs --name deployment/forklift-controller --namespace <forklift-namespace> --container main --tail 5 --output json
```

Full-text search when you don't know which field contains the value:

```bash
oc debug-queries logs --name deployment/forklift-controller --namespace <forklift-namespace> --container main --tail 200 --query "where raw_line ~= '.*<search-term>.*'"
```

**Note:** When using `deployment/forklift-controller` in log queries, Kubernetes resolves the pods via the deployment's selector automatically. If referencing pods directly (e.g., `--selector` or by pod name), use the labels documented in [Forklift Pod Labels](#forklift-pod-labels).

### 11. Plan lifecycle

```bash
oc mtv cancel plan --name my-migration --vms "vm1,vm2" -n <namespace>
oc mtv cutover plan --name my-warm -n <namespace>
oc mtv archive plan --name my-migration -n <namespace>
oc mtv unarchive plan --name my-migration -n <namespace>
```

### 12. Modify existing resources

```bash
oc mtv patch plan --plan-name my-migration --migration-type warm -n <namespace>
oc mtv patch plan --plan-name my-migration --target-labels "env=prod,team=platform" -n <namespace>
oc mtv patch planvm --plan-name my-migration --vm vm1 --target-name new-vm-name -n <namespace>
oc mtv patch provider --name my-vsphere --url "https://new-vcenter.example.com/sdk" -n <namespace>
```

### 13. Cleanup

```bash
oc mtv delete plan --name my-migration -n <namespace>
oc mtv delete provider --name my-vsphere -n <namespace>
```

## TSL Query Syntax (for --vms and --query flags)

Use `--query` to filter, sort, and project results server-side. Use pipe output to `jq`, `grep`, or other post-processing tools only when `--query` cannot express what you need.
The `--query` flag handles filtering, field selection, sorting, and limiting natively.

TSL (Tree Search Language) supports four optional clauses, in this order:

```
[select <field>, ...] [where <condition>] [order by <field> [asc|desc]] [limit N]
```

All clauses are optional and can be combined freely. You can use `select` alone, `where` alone, `order by` alone, `limit` alone, or any combination.

### select -- choose which fields to return

Use `select` to project only the fields you need (like SQL SELECT).
**Note:** `select` only affects table output (the default). With `--output json`, all fields are always returned regardless of `select`.

```
select name, cpuCount, memoryMB
select name, powerState, len(disks) as diskCount
select name, disks[*].capacity as diskSizes
select name, status.conditions
```

### where -- filter rows

```
where name ~= 'prod-.*'
where powerState = 'poweredOn' and memoryMB > 4096
where cpuCount > 4 and len(disks) > 1
where any(concerns[*].category = 'Critical')
where name in ['vm1', 'vm2', 'vm3']
where memoryMB between 2048 and 8192
where not (powerState = 'poweredOff')
```

### order by -- sort results

```
order by name asc
order by memoryMB desc
order by cpuCount desc
```

### limit -- cap the number of results

```
limit 10
limit 5
```

### Combining clauses

```
select name, cpuCount, memoryMB where powerState = 'poweredOn' order by memoryMB desc limit 10
where name like '%web%' order by memoryMB desc limit 10
select name, powerState where cpuCount > 4 order by name asc
where memoryMB > 4096 limit 5
select name where any(concerns[*].category = 'Critical') order by name asc limit 20
```

### Operators

- Comparison: `=`, `!=`, `<`, `<=`, `>`, `>=`
- String: `like` (% wildcard), `ilike` (case-insensitive), `~=` (regex), `~!` (regex negation)
- Logical: `and`, `or`, `not`
- Set: `in [...]`, `not in [...]`, `between X and Y`
- Array: `len(field)`, `any(field[*].sub = 'val')`, `all(field[*].sub >= N)`
- SI units: `4Gi`, `512Mi`, `1Ti`

### Common fields (vSphere)

- `name`, `id`, `powerState`, `cpuCount`, `memoryMB`, `guestId`, `firmware`
- `len(disks)`, `len(nics)`, `disks[*].capacity`, `disks[*].shared`
- `concerns[*].category` (Critical, Warning, Information)
- `path` (folder path), `host`, `storageUsed`

## Other Resources

```bash
oc mtv get mapping network -n <namespace>
oc mtv get mapping storage -n <namespace>

oc mtv create mapping network --name my-net --source my-vsphere --target host \
  --network-pairs "VM Network:default" -n <namespace>

oc mtv create mapping storage --name my-store --source my-vsphere --target host \
  --storage-pairs "datastore1:standard" -n <namespace>

oc mtv get hook -n <namespace>
oc mtv get host -n <namespace>

oc mtv describe plan --name my-migration -n <namespace>
oc mtv describe provider --name my-vsphere -n <namespace>
oc mtv describe mapping network --name my-net -n <namespace>
```

## KARL Affinity Syntax

The `create plan` and `patch plan` commands support `--target-affinity` and `--convertor-affinity` flags using KARL syntax for pod placement rules:

```
RULE_TYPE pods(selector) on TOPOLOGY [weight=N]
```

Rule types: `REQUIRE` (hard affinity), `PREFER` (soft affinity), `AVOID` (hard anti-affinity), `REPEL` (soft anti-affinity). Topology: `node`, `zone`, `region`, `rack`.

```bash
oc mtv create plan --name my-plan --source my-vsphere --vms db-vm \
  --target-affinity "REQUIRE pods(app=database) on node" \
  -n <namespace>
```

For the full KARL reference, call `oc mtv help karl`.

## Forklift Pod Labels

All Forklift pods share the label `app=forklift`. Additional distinguishing labels:

| Pod | Distinguishing label |
| --- | --- |
| `forklift-api-*` | `service=forklift-api` |
| `forklift-controller-*` | `control-plane=controller-manager` |
| `forklift-validation-*` | `service=forklift-validation` |
| `forklift-volume-populator-controller-*` | (none — only `app=forklift`) |

When referencing pods directly (not via `deployment/...`), use `app=forklift`. The label is **`app=forklift`**, not `app=forklift-controller`.

## Tips

### Preview commands with `--dry-run`

```bash
oc mtv create plan --name test --source my-vsphere --vms vm1 -n <namespace> --dry-run
```

## Self-Learning Rule

When you encounter an unfamiliar MTV command or need to verify flags, always call:

```bash
oc mtv <command> --help
oc mtv <command> <subcommand> --help
```

This ensures you use the correct and current syntax.
