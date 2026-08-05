---
name: govc-vsphere
description: Use govc to manage VMware vSphere virtual machines. Use this skill when the user wants to create, clone, snapshot, power on/off, or manage VMs on vSphere/vCenter/ESXi.
---

# govc - vSphere VM Management

`govc` is a CLI built on the govmomi Go library for automating VMware vSphere operations.

## Installation

> Installation methods, PATH setup, and verification: [ref-install.md](ref-install.md)

## Connection Setup

Set environment variables for vCenter/ESXi connectivity:

```bash
export GOVC_URL=vcenter.example.com
export GOVC_USERNAME=admin@vsphere.local
export GOVC_PASSWORD='secret'
export GOVC_INSECURE="${GOVC_INSECURE:-false}"  # set to 'true' only for lab/test environments without valid certificates
```

Optional defaults to avoid repeating `-dc`, `-ds`, `-pool`, `-net` on every command:

```bash
export GOVC_DATACENTER=mydc
export GOVC_DATASTORE=datastore1
export GOVC_NETWORK='VM Network'
export GOVC_RESOURCE_POOL=/mydc/host/mycluster/Resources
```

Verify connectivity:

```bash
govc about
govc datacenter.info
```

## Getting Help

Always check built-in help for flags and usage:

```bash
govc -h                      # list all commands
govc <command> -h            # flags for a specific command
```

## Inventory Browsing

```bash
govc ls                                 # top-level inventory
govc ls /mydc/vm                        # VMs folder
govc ls -l /mydc/network                # networks with types
govc ls -l /mydc/datastore              # datastores with types

govc find / -type m                     # all VMs (managed entities)
govc find / -type m -name 'prod-*'      # VMs matching a name pattern
govc find / -type h                     # all hosts

govc datacenter.info
govc host.info /mydc/host/mycluster/*   # all hosts in a cluster
govc datastore.info datastore1
```

## VM Lifecycle

### Create a VM

```bash
govc vm.create -m 2048 -c 2 -g ubuntu64Guest \
  -net.adapter vmxnet3 -disk.controller pvscsi \
  -disk 20GB -ds datastore1 my-vm
```

### Clone a VM or template

```bash
govc vm.clone -vm template-vm -ds datastore1 new-vm
govc vm.clone -vm template-vm -link new-vm              # linked clone
govc vm.clone -vm template-vm -snapshot base-snap new-vm # clone from snapshot
```

### Power operations

```bash
govc vm.power -on=true my-vm          # power on
govc vm.power -s=true my-vm           # graceful guest shutdown
govc vm.power -off=true my-vm         # force power off
govc vm.power -r=true my-vm           # reset
govc vm.power -suspend=true my-vm     # suspend
```

### VM info and IP

```bash
govc vm.info my-vm
govc vm.info -r my-vm                 # include resource usage
govc vm.info -json my-vm              # JSON output
govc vm.ip my-vm                      # wait for and print guest IP
govc vm.ip -v4 -a my-vm              # IPv4 only, all NICs
```

### Modify a VM

```bash
govc vm.change -vm my-vm -m 4096             # change memory (MB)
govc vm.change -vm my-vm -c 4               # change CPU count
govc vm.change -vm my-vm -e guestinfo.data=value  # set ExtraConfig
```

### Destroy a VM

```bash
govc vm.destroy my-vm
```

> Full flag tables and additional examples: [ref-commands.md](ref-commands.md)

## Snapshots

```bash
govc snapshot.create -vm my-vm before-update   # create snapshot
govc snapshot.tree -vm my-vm                   # list snapshots
govc snapshot.tree -vm my-vm -D -i             # with dates and IDs
govc snapshot.revert -vm my-vm before-update   # revert to snapshot
govc snapshot.remove -vm my-vm before-update   # delete snapshot
govc snapshot.remove -vm my-vm '*'             # remove all snapshots
```

## Disk Management

```bash
govc vm.disk.create -vm my-vm -name my-vm/data -size 50G
govc vm.disk.attach -vm my-vm -disk my-vm/shared.vmdk -link=false
govc vm.disk.change -vm my-vm -disk.label "Hard disk 2" -size 100G
```

## Datastore Operations

```bash
govc datastore.info datastore1
govc datastore.ls
govc datastore.ls -l path/to/folder
govc datastore.upload local-file.iso remote-path.iso
govc datastore.download remote-path.iso local-file.iso
```

## OVA / OVF Import and Export

```bash
# Import an OVA
govc import.ova -folder=templates my-appliance.ova

# Import with options (thin provisioning, mark as template)
govc import.ova -options - my-appliance.ova <<EOF
{"DiskProvisioning": "thin", "MarkAsTemplate": true}
EOF

# Export a VM as OVF
govc export.ovf -vm my-vm -f=true .
```

## Templates

```bash
govc vm.markastemplate /mydc/vm/my-vm              # convert VM to template
govc vm.markasvm -host=esxi01 /mydc/vm/my-template # convert template back to VM
govc vm.clone -vm my-template -on=true new-vm       # deploy from template
```

## Guest Operations (VMware Tools required)

```bash
govc guest.run -vm my-vm /bin/uname -a
govc guest.upload -vm my-vm local.conf /etc/app.conf
govc guest.download -vm my-vm /var/log/app.log ./app.log
govc guest.ls -vm my-vm /tmp/
govc guest.mkdir -vm my-vm /opt/myapp
```

## JSON Output and Scripting

Most commands support `-json` for machine-readable output:

```bash
govc vm.info -json my-vm | jq '.virtualMachines[].guest.ipAddress'
govc find / -type m -json | jq '.[].name'
govc host.info -json /mydc/host/cluster/* | jq '.hostSystems[].summary.config.product.version'
```

## Self-Learning Rule

When you encounter an unfamiliar `govc` subcommand or need to verify flags, always run:

```bash
govc <command> -h
```

This ensures you use the correct and current syntax.
