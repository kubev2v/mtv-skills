---
name: kubectl-virt
description: Use oc virt (or kubectl virt) to manage KubeVirt virtual machines. Use this skill when the user wants to create, start, stop, or manage VMs on OpenShift/Kubernetes.
---

# oc virt - KubeVirt VM Management

`oc virt` (or `kubectl virt`) is a plugin for managing KubeVirt virtual machines.

## Installation

> Installation, PATH setup, and shell completion: [ref-install.md](ref-install.md)

## Getting Help

Always use the built-in help for discovering subcommands and flags:

```bash
oc virt --help
oc virt <command> --help
oc virt <command> <subcommand> --help
```

## Instance Types and Preferences

Prefer using instance types over raw `--memory`/CPU settings. Instance types define
pre-configured VM sizing (CPU, memory, and compute behavior), while preferences define
OS-specific settings (boot order, device models, firmware).

### Discovering available instance types

```bash
oc get virtualmachineclusterinstancetype
oc get virtualmachineclusterpreference
```

Series include **U** (universal/general purpose), **O** (overcommitted/high density),
**CX** (compute exclusive), **M** (memory intensive), **N** (network/DPDK),
**RT** (realtime), and **D** (dedicated CPU). Sizes range from `nano` (1 vCPU) to
`8xlarge` (32 vCPUs). Naming pattern: `<series><version>.<size>` (e.g., `u1.medium`).

Preferences configure OS-specific settings (e.g., `fedora`, `rhel.9`, `windows.11.virtio`).

> Full series table, sizing table, and preferences list: [ref-types.md](ref-types.md)

### How to choose

- **Start with U series** (universal) for general workloads.
- Use **O series** if you need to pack more VMs on limited hardware (overcommits memory).
- Use **CX series** for CPU-bound workloads needing guaranteed performance.
- Use **M series** for databases or caches that need lots of memory.
- Use **D series** for enterprise apps needing dedicated CPU without hugepages.
- When a DataSource has instancetype/preference annotations, use `--infer-instancetype`
  and `--infer-preference` to pick them automatically.

## VM Disk Sources

VMs need boot disks. The `--volume-import` flag supports source types: `registry`, `ds`
(DataSource/golden image), `pvc`, `http`, `blank`, `s3`, `gcs`, and `snapshot`.

On OpenShift, golden images are available as DataSources in `openshift-virtualization-os-images`:

```bash
oc get datasource -n openshift-virtualization-os-images
```

> Full disk source table, containerdisk images, and DataSource details: [ref-types.md](ref-types.md)

## Creating VMs

The primary way to create VMs is with `oc virt create vm`. The command generates
a VirtualMachine manifest that you pipe to `oc apply`.

Prefer using `--instancetype` and `--preference` instead of `--memory`. Only fall back
to `--memory` when instance types are not available on the cluster.

### From a registry containerdisk (with instance type)

```bash
oc virt create vm \
  --name=my-fedora \
  --instancetype=u1.medium \
  --preference=fedora \
  --volume-import=type:registry,url:docker://quay.io/containerdisks/fedora:latest,size:30Gi \
  --user=fedora \
  --ssh-key="$(cat ~/.ssh/id_rsa.pub)" \
  | oc apply -f -
```

### From a cluster DataSource (inferred sizing)

```bash
oc virt create vm \
  --name=my-vm \
  --volume-import=type:ds,src:openshift-virtualization-os-images/fedora,size:30Gi \
  --infer-instancetype --infer-preference \
  --user=fedora \
  --ssh-key="$(cat ~/.ssh/id_rsa.pub)" \
  | oc apply -f -
```

### From an HTTP URL

```bash
oc virt create vm \
  --name=my-vm \
  --instancetype=u1.medium \
  --preference=fedora \
  --volume-import=type:http,url:https://example.com/my-image.qcow2,size:30Gi \
  --user=cloud-user \
  --ssh-key="$(cat ~/.ssh/id_rsa.pub)" \
  | oc apply -f -
```

### Fallback: raw memory (no instance types on cluster)

Note: `create vm` only supports `--memory`, there is no `--cpu` flag.
This is another reason to prefer instance types which set both CPU and memory.

```bash
oc virt create vm \
  --name=my-vm \
  --memory=2Gi \
  --run-strategy=Always \
  --volume-import=type:registry,url:docker://quay.io/containerdisks/fedora:latest,size:30Gi \
  --user=fedora \
  --ssh-key="$(cat ~/.ssh/id_rsa.pub)" \
  | oc apply -f -
```

### Key flags for `create vm`

- `--name` - VM name
- `--instancetype` - Instance type (e.g., `u1.medium`). Preferred over `--memory`.
- `--preference` - OS preference (e.g., `fedora`, `rhel.9`, `windows.11.virtio`)
- `--infer-instancetype` - Infer instancetype from the first boot disk annotations (default: true)
- `--infer-preference` - Infer preference from the first boot disk annotations (default: true)
- `--memory` - Guest memory fallback when no instance types available (e.g., 2Gi, 4Gi)
- `--run-strategy` - RunStrategy: Always, Manual, Halted, RerunOnFailure
- `--volume-import` - Import a volume (see Disk Sources table above). Can be repeated.
- `--volume-containerdisk` - Ephemeral containerdisk (not persisted). Format: `src:<image>`
- `--volume-pvc` - Use existing PVC directly (no clone). Format: `src:<pvc-name>`
- `--user` - Cloud-init user
- `--ssh-key` - SSH public key for cloud-init

### Important notes

- `oc virt create vm` outputs YAML to stdout - you must pipe it to `oc apply -f -`
- `--instancetype` is mutually exclusive with `--memory` -- use one or the other
- `--infer-instancetype` and `--infer-preference` default to true, so they work automatically when the boot disk DataSource has the right annotations
- The command does NOT set accessModes or storageClassName on the DataVolume. CDI infers these from the StorageProfile of the default StorageClass.
- If no default StorageClass is set, DataVolumes will get stuck with:
  `ErrClaimNotValid: PVC spec is missing accessMode and no storageClass to choose profile`
- Fix: ensure a default StorageClass exists:
  `oc annotate storageclass <name> storageclass.kubernetes.io/is-default-class=true`

### Creating multiple VMs (loop pattern)

```bash
SSH_KEY="$(cat ~/.ssh/id_rsa.pub)"
for i in 1 2 3 4; do
  oc virt create vm \
    --name="test-vm-${i}" \
    --instancetype=u1.medium \
    --preference=fedora \
    --volume-import=type:registry,url:docker://quay.io/containerdisks/fedora:latest,size:30Gi \
    --user=fedora \
    --ssh-key="$SSH_KEY" \
    | oc apply -f -
done
```

## SSH Access

There are multiple ways to access a VM over SSH, depending on the use case.

### Method 1: virtctl ssh (quick access via API server)

The simplest method. Tunnels SSH through the Kubernetes API server -- no service needed.
Best for troubleshooting and occasional access. Not recommended for high-traffic or production use
as it adds load to the API server.

```bash
# SSH into a VM (uses your default SSH key)
oc virt ssh fedora@my-vm

# Specify identity file
oc virt ssh fedora@my-vm --identity-file=~/.ssh/id_rsa

# Run a command
oc virt ssh fedora@my-vm --command="uname -a"

# SCP files to/from a VM
oc virt scp myfile.bin fedora@vmi/my-vm:myfile.bin
oc virt scp fedora@vmi/my-vm:remote-file.bin ./local-file.bin
oc virt scp --recursive ~/mydir/ fedora@vmi/my-vm:./mydir
```

Other methods include port-forward (SSH config integration), NodePort Service
(external access), ClusterIP Service (cluster-internal access), and secondary networks.

> Methods 2-5 with full examples: [ref-types.md](ref-types.md)

## Common VM Operations

For any command you are unsure about, run `oc virt <command> --help` first.

```bash
# List VMs
oc get vm
oc get vm -n <namespace>

# Start/stop/restart
oc virt start <vm-name>
oc virt stop <vm-name>
oc virt restart <vm-name>

# Pause/unpause
oc virt pause vm <vm-name>
oc virt unpause vm <vm-name>

# Console access
oc virt console <vm-name>
oc virt vnc <vm-name>

# Migration (live migrate)
oc virt migrate <vm-name>

# Get VM details
oc describe vm <vm-name>
oc get vmi <vm-name>
```

## Self-Learning Rule

When you encounter an unfamiliar `oc virt` subcommand or need to verify flags, always run:

```bash
oc virt <command> --help
```

This ensures you use the correct and current syntax.
