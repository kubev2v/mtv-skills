# Skills Quick Reference

Short description of each skill — what it does, when it kicks in, and what triggers it.

---

### [mcp-setup](../skills/mcp-setup/SKILL.md)

Installs and configures the CLI plugins (`oc mtv`, `oc metrics`, `oc debug-queries`).

**When used:** CLI tools are missing or the user asks to set up / install the tools.
**Triggered by:** "install the CLI plugins", "set up the tools", or when another skill detects a missing dependency.

---

### [check-ocp-health](../skills/check-ocp-health/SKILL.md)

Runs a general OpenShift cluster health check — nodes, operators, pods, etcd, networking, certificates.

**When used:** The cluster is unhealthy, nodes are NotReady, operators are degraded, pods are crashing, or a general diagnosis is needed.
**Triggered by:** "check cluster health", "why are nodes NotReady", "operators degraded", "pods crashing".

---

### [check-ceph-health](../skills/check-ceph-health/SKILL.md)

Diagnoses Ceph/ODF storage health — OSDs, placement groups, capacity, CSI provisioners, PVCs.

**When used:** PVCs are stuck in Pending, storage provisioning fails, Ceph is degraded or full, or storage needs diagnosis.
**Triggered by:** "is Ceph healthy", "PVC stuck Pending", "OSDs full", "storage not provisioning".

---

### [troubleshoot-virt](../skills/troubleshoot-virt/SKILL.md)

Troubleshoots stuck VMs and migrations in OpenShift Virtualization and MTV/Forklift.

**When used:** VMs won't start, DataVolumes are stuck, migrations fail, or cluster resources are exhausted.
**Triggered by:** "VM won't start", "DataVolume stuck", "migration failed", "virt-launcher pod error".

---

### [mtv-test](../skills/mtv-test/SKILL.md)

Generates bash e2e verification scripts for MTV/Forklift bugs and features through a guided multi-step workflow (gather context, write test plan, get approval, generate script, run and refine).

**When used:** The user wants to create a test, verify a bug fix, or build an e2e verification script.
**Triggered by:** "write a test for MTV-4911", "create a verification script", "test this bug fix", or any Jira ticket (MTV-NNN) mentioned together with testing.

---

### [observe-metrics](../skills/observe-metrics/SKILL.md)

Queries Prometheus/Thanos metrics — metric discovery, instant queries, range queries, and gnuplot charts.

**When used:** The user wants to check cluster metrics, monitor network traffic, storage I/O, pod resource usage, or VM migration throughput.
**Triggered by:** "show me network traffic", "plot CPU usage", "discover metrics for ceph", "migration throughput chart".

---

### [govc-vsphere](../skills/govc-vsphere/SKILL.md)

Manages VMware vSphere virtual machines using the `govc` CLI — create, clone, snapshot, power on/off, disk and datastore operations.

**When used:** The user wants to create, clone, snapshot, power-manage, or inspect VMs on vSphere/vCenter/ESXi.
**Triggered by:** "create a VM on vSphere", "snapshot this VM", "power off the VM", "list VMs in vCenter".

---

### [kubectl-mtv](../skills/kubectl-mtv/SKILL.md)

Runs end-to-end VM migrations from vSphere, oVirt, OpenStack, OVA, EC2, or HyperV into OpenShift Virtualization (KubeVirt) using the `oc mtv` CLI.

**When used:** The user wants to create providers, browse source inventory, create migration plans, start migrations, or monitor progress.
**Triggered by:** "migrate my VMs from vSphere", "create a migration plan", "list inventory VMs", "check migration status".

---

### [kubectl-virt](../skills/kubectl-virt/SKILL.md)

Creates and manages KubeVirt virtual machines on OpenShift/Kubernetes — create, start, stop, SSH, console, live-migrate.

**When used:** The user wants to create, start, stop, or access VMs running on OpenShift Virtualization.
**Triggered by:** "create a Fedora VM", "start the VM", "SSH into my VM", "stop all VMs".
