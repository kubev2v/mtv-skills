# oc virt Reference - Instance Types, Disk Sources, SSH Methods

Instance type tables, VM disk source types, containerdisk images, cluster DataSources, and additional SSH access methods.

See the main [SKILL.md](SKILL.md) for VM creation workflows and common operations.

---

## Instance Type Series

| Series | Name | Use Case | CPU | Memory Ratio | Key Features |
|--------|------|----------|-----|--------------|--------------|
| **U** | Universal | General purpose | Burstable | 1:4 | Good default for most workloads |
| **O** | Overcommitted | Higher density | Burstable | 1:4 | Memory overcommitted for more VMs per node |
| **CX** | Compute Exclusive | Compute intensive | Dedicated | 1:2 | Hugepages, vNUMA, isolated emulator threads |
| **M** | Memory | Memory intensive | Burstable | 1:8 | Hugepages, high memory per vCPU |
| **N** | Network | DPDK/VNFs | Dedicated | 1:2 | Hugepages, requires DPDK-capable nodes |
| **RT** | Realtime | Realtime apps | Dedicated | 1:4 | Hugepages, isolated emulator threads |
| **D** | Dedicated | Predictable compute | Dedicated | 1:4 | Dedicated CPU, isolated emulator threads |

## Instance Type Sizing

Each series comes in standard sizes:

| Size | vCPUs | Example (U series memory) |
|------|-------|--------------------------|
| nano | 1 | 512Mi |
| micro | 1 | 1Gi |
| small | 1 | 2Gi |
| medium | 1 | 4Gi |
| large | 2 | 8Gi |
| xlarge | 4 | 16Gi |
| 2xlarge | 8 | 32Gi |
| 4xlarge | 16 | 64Gi |
| 8xlarge | 32 | 128Gi |

Naming pattern: `<series><version>.<size>` (e.g., `u1.medium`, `cx1.xlarge`, `m1.2xlarge`).

## Preferences

Preferences configure OS-specific settings (boot order, device models, firmware). Common ones:

- `fedora`, `centos.stream9`, `centos.stream10`, `ubuntu`, `debian`
- `rhel.9`, `rhel.10`, `rhel.8`, `rhel.7`
- `windows.11.virtio`, `windows.2k22.virtio`, `windows.10.virtio`
- `opensuse.tumbleweed`, `opensuse.leap`, `sles`

---

## VM Disk Sources

The `--volume-import` flag on `oc virt create vm` supports these source types:

| Type | Description | Example |
|------|-------------|---------|
| `registry` | Container disk from a registry | `type:registry,url:docker://quay.io/containerdisks/fedora:latest,size:30Gi` |
| `ds` | DataSource (cluster golden image) | `type:ds,src:fedora,size:30Gi` or `type:ds,src:my-ns/my-ds` |
| `pvc` | Clone an existing PVC | `type:pvc,src:my-ns/my-pvc,size:30Gi` |
| `http` | Download from HTTP/HTTPS URL | `type:http,url:https://example.com/disk.qcow2,size:30Gi` |
| `blank` | Empty disk | `type:blank,size:50Gi` |
| `s3` | Download from S3 | `type:s3,url:s3://bucket/disk.qcow2,size:30Gi` |
| `gcs` | Download from GCS | `type:gcs,url:gcs://bucket/disk.qcow2,size:30Gi` |
| `snapshot` | Clone from VolumeSnapshot | `type:snapshot,src:my-ns/my-snap,size:30Gi` |

## Upstream Containerdisk Images (quay.io/containerdisks)

Official KubeVirt containerdisks maintained at `quay.io/containerdisks`:

- `quay.io/containerdisks/fedora` (amd64, arm64, s390x)
- `quay.io/containerdisks/centos-stream` (amd64, arm64, s390x)
- `quay.io/containerdisks/ubuntu` (amd64, arm64, s390x)
- `quay.io/containerdisks/debian` (amd64, arm64)
- `quay.io/containerdisks/opensuse-tumbleweed` (amd64, s390x)
- `quay.io/containerdisks/opensuse-leap` (amd64, arm64)

Use with tag for specific versions (e.g., `quay.io/containerdisks/fedora:41`).

## Cluster DataSources (Golden Images)

On OpenShift, golden images are pre-imported as DataSources and kept updated
via DataImportCron jobs. These live in the `openshift-virtualization-os-images`
namespace and can be used directly as boot sources without downloading anything.

```bash
oc get datasource -n openshift-virtualization-os-images
```

---

## SSH Access Methods 2-5

Method 1 (virtctl ssh) is in the main [SKILL.md](SKILL.md). These are alternative methods.

### Method 2: virtctl port-forward (SSH config integration)

Forwards a local port through the API server. Useful for integrating with your
`~/.ssh/config`. Same API server caveat as Method 1.

```bash
oc virt port-forward vm/my-vm 2222:22

# Then in another terminal
ssh -p 2222 fedora@127.0.0.1
```

### Method 3: NodePort Service (external access without cloud LB)

Creates a Kubernetes Service that maps the VM's SSH port to a high port (30000-32767)
on every cluster node. You can then SSH from outside the cluster using any node's IP
and the assigned port. Works on any cluster (bare metal, cloud, etc.).

```bash
oc virt expose vm my-vm --name=my-vm-ssh --port=22 --type=NodePort

oc get svc my-vm-ssh
# Example output:
#   NAME        TYPE       CLUSTER-IP    EXTERNAL-IP   PORT(S)        AGE
#   my-vm-ssh   NodePort   10.96.0.123   <none>        22:31245/TCP   5s

# SSH using any cluster node IP and the assigned NodePort
ssh -p 31245 fedora@<any-node-ip>

# To find node IPs:
oc get nodes -o wide
```

### Method 4: ClusterIP Service (access from within the cluster)

For access from other pods/VMs inside the same cluster only. Not reachable from outside.

```bash
oc virt expose vm my-vm --name=my-vm-ssh --port=22 --type=ClusterIP
# Connect from another pod in the cluster:
ssh fedora@my-vm-ssh.<namespace>.svc.cluster.local
```

### Method 5: Secondary network

Attach the VM to a secondary network (bridge, SR-IOV) where it gets a DHCP address.
Connect directly to that IP. This requires network infrastructure setup (not covered here).
