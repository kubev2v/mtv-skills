# Provider Creation Commands

Use these `oc mtv create provider` commands in the generated test script.
Pick the block that matches the provider type for the scenario.

## vSphere (insecure)

```bash
oc mtv create provider --name "${PROVIDER}" --type vsphere \
  --url "https://${GOVC_URL}/sdk" \
  --username "${GOVC_USERNAME}" \
  --password "${GOVC_PASSWORD}" \
  --provider-insecure-skip-tls \
  -n "${NS}"
```

## vSphere (with CA cert)

```bash
oc mtv create provider --name "${PROVIDER}" --type vsphere \
  --url "https://${GOVC_URL}/sdk" \
  --username "${GOVC_USERNAME}" \
  --password "${GOVC_PASSWORD}" \
  --cacert "$(fetch_ca_cert "${GOVC_URL}")" \
  -n "${NS}"
```

## oVirt / RHV

```bash
oc mtv create provider --name "${PROVIDER}" --type ovirt \
  --url "${RHV_URL}" \
  --username "${RHV_USERNAME}" \
  --password "${RHV_PASSWORD}" \
  --cacert "$(fetch_ca_cert "${RHV_URL}")" \
  -n "${NS}"
```

## OpenStack

```bash
oc mtv create provider --name "${PROVIDER}" --type openstack \
  --url "${OSP_URL}" \
  --username "${OSP_USERNAME}" \
  --password "${OSP_PASSWORD}" \
  --provider-domain-name "${OSP_DOMAIN_NAME}" \
  --provider-project-name "${OSP_PROJECT_NAME}" \
  --provider-region-name "${OSP_REGION_NAME}" \
  --cacert "$(fetch_ca_cert "${OSP_URL}")" \
  -n "${NS}"
```

## OVA

```bash
oc mtv create provider --name "${PROVIDER}" --type ova \
  --url "${OVA_URL}" \
  -n "${NS}"
```

## Remote OpenShift (source)

```bash
oc mtv create provider --name "${PROVIDER}" --type openshift \
  --url "${SOURCE_OCP_URL}" \
  --provider-token "${SOURCE_OCP_TOKEN}" \
  --provider-insecure-skip-tls \
  -n "${NS}"
```

The remote OpenShift cluster is typically the **source** (where VMs live). Use the
`SOURCE_` prefix for its env vars to distinguish from the local cluster running MTV.
Use with the local OpenShift provider (below) which serves as the target.

## HyperV

```bash
oc mtv create provider --name "${PROVIDER}" --type hyperv \
  --url "${HV_URL}" \
  --username "${HV_USERNAME}" \
  --password "${HV_PASSWORD}" \
  --smb-url "${HV_SMB_URL}" \
  --provider-insecure-skip-tls \
  -n "${NS}"
```

## EC2

```bash
oc mtv create provider --name "${PROVIDER}" --type ec2 \
  --ec2-region "${EC2_REGION}" \
  --target-access-key-id "${EC2_ACCESS_KEY_ID}" \
  --target-secret-access-key "${EC2_SECRET_ACCESS_KEY}" \
  --target-az "${EC2_TARGET_AZ}" \
  --target-region "${EC2_TARGET_REGION}" \
  -n "${NS}"
```

## OpenShift (local cluster)

```bash
oc mtv create provider --name host --type openshift -n "${NS}"
```

The local OpenShift provider auto-detects the current cluster and needs no URL or token.
It is typically the target but can serve as the source when the remote OpenShift is the target.
