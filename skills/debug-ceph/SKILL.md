---
name: debug-ceph
description: >-
  Run Ceph CLI commands inside Rook/ODF mon pods to debug and reclaim storage
  on OpenShift. Use when Ceph is HEALTH_ERR/OSD_FULL, PVCs are Pending, PVs are
  stuck Terminating/Released, CSI cannot provision or delete volumes, or the
  user asks to exec into Ceph, run ceph commands, or clean storage.
---

# Debug Ceph (mon shell)

Use this skill when metrics/CR status are not enough and you need a real
`ceph` / `rbd` CLI against the live cluster. Prefer this over guessing from
PVC events alone when OSDs are full or volume deletes are stuck.

For lighter, metrics-first checks see also **check-ceph-health**.

## Required tools

- `oc` / `kubectl` with access to `openshift-storage`
- Cluster-admin (or equivalent) to exec into Rook mon pods

Optional helpers (secure version-pinned install):

```bash
curl -sSLO https://raw.githubusercontent.com/kubev2v/mtv-skills/main/tools/install-tools.sh
curl -sSL  https://raw.githubusercontent.com/kubev2v/mtv-skills/main/SHA256SUMS | shasum -a 256 --check --ignore-missing
bash install-tools.sh kubectl-debug-queries kubectl-metrics && rm install-tools.sh
```

## Important: how to run Ceph commands

Bare `ceph -s` inside the mon container usually **fails**:

- mon: cannot resolve monitors (`SRV _ceph-mon._tcp`)
- mgr: auth method mismatch / permission denied

Always pass **mon endpoints** and the **mon keyring**.

### Helper (copy into your shell)

```bash
NS=openshift-storage
MON_POD=$(oc -n "$NS" get pods -l app=rook-ceph-mon \
  -o jsonpath='{.items[0].metadata.name}')

# Prefer CSI/monitor list from the endpoints ConfigMap (stable)
MONS=$(oc -n "$NS" get configmap rook-ceph-mon-endpoints \
  -o jsonpath='{.data.csi-cluster-config-json}' \
  | jq -r '.[0].monitors | join(",")')

# Fallback if jq/csi JSON is unavailable: data=a=IP:PORT,b=IP:PORT,...
if [ -z "$MONS" ] || [ "$MONS" = "null" ]; then
  MONS=$(oc -n "$NS" get configmap rook-ceph-mon-endpoints \
    -o jsonpath='{.data.data}' \
    | tr ',' '\n' | sed 's/^[a-z]=//' | paste -sd',' -)
fi

ceph() {
  oc -n "$NS" exec "$MON_POD" -c mon -- \
    ceph -m "$MONS" \
      --keyring /etc/ceph/keyring-store/keyring \
      --conf /etc/ceph/ceph.conf \
      "$@"
}

rbd() {
  oc -n "$NS" exec "$MON_POD" -c mon -- \
    rbd -m "$MONS" \
      --keyring /etc/ceph/keyring-store/keyring \
      --conf /etc/ceph/ceph.conf \
      "$@"
}
```

Notes:

- `ROOK_CEPH_MON_HOST` on the mon pod is often a `secretKeyRef` — do **not**
  rely on `jsonpath` of `.value` (it is empty). Use the ConfigMap above.
- Keyring path in Rook/ODF mon pods: `/etc/ceph/keyring-store/keyring`
- Config: `/etc/ceph/ceph.conf`
- Some commands (`ceph osd df tree`, large `rbd ls`) can hang when the cluster
  is full. Prefer bounded waits (background + kill) if a command stalls >20s.

### Optional: rook-ceph-tools

If a tools Deployment exists (`app=rook-ceph-tools`), you can exec there
instead. Many QE clusters do **not** ship it; mon+keyring is enough.

```bash
oc -n openshift-storage get pods -l app=rook-ceph-tools
# Enable via StorageCluster if your ODF version supports it:
# oc -n openshift-storage patch storagecluster ocs-storagecluster --type=merge \
#   -p '{"spec":{"enableTools":true}}'
```

---

## 1. Quick triage with Ceph CLI

```bash
ceph -s
ceph health detail
ceph df
ceph osd dump | grep -E 'full_ratio|nearfull|backfillfull|flags '
```

Interpret:

| Signal | Meaning |
|--------|---------|
| `HEALTH_ERR` + `OSD_FULL` | OSDs at/above `full_ratio` (default **0.85**). New writes/provisioning blocked. |
| `POOL_FULL` / `MAX AVAIL 0 B` | Pools refuse allocations even if `ceph df` still shows some AVAIL. |
| `usage: X used, Y avail` with `%RAW USED ≈ 85+` | Classic full-threshold stuck state. |
| `pgs: ... active+clean` | Data path is healthy; problem is capacity, not PG repair. |

Also check Kubernetes view:

```bash
oc get cephcluster -n openshift-storage \
  -o jsonpath='{.items[0].status.ceph.health}{"\n"}{.items[0].status.ceph.details}{"\n"}'

oc get pv --no-headers | awk '{print $5}' | sort | uniq -c
oc get pvc -A --no-headers | awk '{print $1,$3}' | sort | uniq -c
```

Importer / virt pods Pending with `unbound immediate PersistentVolumeClaims`
almost always means PVCs cannot bind because RBD provisioning is blocked.

---

## 2. Per-OSD checks (optional)

```bash
ceph osd df          # may be slow when full
ceph health detail   # lists which osd.N is full

for osd in 0 1 2; do
  POD=$(oc -n openshift-storage get pods -l "ceph-osd-id=${osd}" \
    -o jsonpath='{.items[0].metadata.name}')
  echo "=== osd.${osd} pod=${POD} ==="
  oc -n openshift-storage exec "$POD" -c osd -- df -h
done
```

Container root filesystem free space is **not** the Ceph OSD capacity.
Trust `ceph df` / `OSD_FULL` over `df` on the pod overlay.

---

## 3. Clean storage (reclaim capacity)

### 3a. Find reclaimable Kubernetes volumes

```bash
# Released PVs still holding Ceph RBD images
oc get pv --field-selector=status.phase=Released

# Deletes stuck on CSI finalizers (common when Ceph is full)
oc get pv --no-headers | awk '$5=="Terminating"{print $1,$2,$5}'

# Pending PVCs waiting on provisioner
oc get pvc -A --field-selector=status.phase=Pending
```

Typical MTV leftover claim names look like:

- `test/plan-*-disk-*`
- `test/prime-*` (CDI prime PVCs)

### 3b. Delete safe leftovers (plans first)

Prefer deleting MTV plans so controllers release owned DVs/PVCs:

```bash
oc mtv delete plan --name <plan> -n <namespace>
```

Then delete orphaned Released PVs (reclaimPolicy is usually `Delete`):

```bash
RELEASED=$(oc get pv --no-headers | awk '$5=="Released"{print $1}')
# Review the list first!
echo "$RELEASED"
oc delete pv $RELEASED
```

### 3c. Unblock stuck deletes when Ceph is FULL

If PVs stay `Terminating` with finalizers such as:

- `external-provisioner.volume.kubernetes.io/finalizer`
- `external-attacher/openshift-storage-rbd-csi-ceph-com`

CSI cannot finish RBD deletion while OSDs are full → chicken-and-egg.

**Temporarily raise full ratios** (ask the user before changing cluster safety
thresholds), wait for deletes, then reset:

```bash
# Current ratios
ceph osd dump | grep -E 'full_ratio|nearfull|backfillfull'

# Unblock (example values used in QE when stuck at 85%)
ceph osd set-full-ratio 0.95
ceph osd set-nearfull-ratio 0.90
ceph osd set-backfillfull-ratio 0.92

ceph -s
ceph health detail

# Watch PVs leave Terminating
watch -n5 'oc get pv --no-headers | awk "{print \$5}" | sort | uniq -c'

# After Terminating count is 0 and HEALTH recovers:
ceph osd set-full-ratio 0.85
ceph osd set-nearfull-ratio 0.75
ceph osd set-backfillfull-ratio 0.80
```

Only remove PV finalizers manually as a last resort after confirming the
backing RBD image is gone (or the PV is orphaned with no image). Prefer
raising the full ratio and letting CSI complete deletion.

### 3d. Inspect / delete orphan RBD images (advanced)

```bash
# List images in the ODF block pool (can be large/slow)
rbd ls -l ocs-storagecluster-cephblockpool | head

# Disk usage for a specific image
rbd du ocs-storagecluster-cephblockpool/<image>

# Delete an orphan image ONLY if no PV/PVC still references it
# rbd rm ocs-storagecluster-cephblockpool/<image>
```

Cross-check image IDs against PV `.spec.csi.volumeAttributes` /
`volumeHandle` before removing anything.

---

## 4. Verify recovery

```bash
ceph -s
ceph df
ceph health detail

oc get pv --no-headers | awk '{print $5}' | sort | uniq -c
oc get pvc -A --no-headers | awk '{print $3}' | sort | uniq -c
```

Success looks like:

- `HEALTH_OK` or `HEALTH_WARN` without `OSD_FULL`
- Block pool `MAX AVAIL` > 0
- No flood of `ProvisioningFailed` / `ExternalProvisioning` on new PVCs
- New importer pods schedule (PVCs Bound)

---

## 5. MTV / migration context

When MTV migrations fail with Pending importer pods:

1. Confirm Ceph with this skill (`ceph -s`, `OSD_FULL`).
2. Clean Released/Terminating PVs from prior plan runs (section 3).
3. Re-run only after `MAX AVAIL` is non-zero.
4. Prefer smaller plans (fewer disks) on small QE ODF clusters (~200 GiB raw).

Related skills: **check-ceph-health**, **troubleshoot-virt**, **kubectl-mtv**.

---

## Self-Learning Rule

Before unfamiliar flags:

```bash
ceph --help
ceph osd --help
rbd --help
oc -n openshift-storage get cephcluster -o yaml | head
```
