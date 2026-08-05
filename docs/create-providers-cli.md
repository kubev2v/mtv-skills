# Creating Providers with the MTV CLI

Quick-start commands for creating MTV source providers using `oc mtv` (or `kubectl mtv`).
Each example fetches the CA certificate with `openssl` instead of skipping TLS verification.

## Environment Variables

Set the variables for the providers you need before running the commands below.

### vSphere

```bash
export GOVC_URL="https://vcenter.example.com"        # includes scheme, no path
export GOVC_USERNAME="administrator@vsphere.local"
export GOVC_PASSWORD="secret"
```

### oVirt / RHV

```bash
export RHV_URL="https://rhv-manager.example.com/ovirt-engine/api"  # full URL with path
export RHV_USERNAME="admin@internal"
export RHV_PASSWORD="secret"
```

### OpenStack

```bash
export OSP_URL="https://keystone.example.com:13000/v3"  # full URL with port and path
export OSP_USERNAME="admin"
export OSP_PASSWORD="secret"
export OSP_DOMAIN_NAME="Default"
export OSP_PROJECT_NAME="admin"
export OSP_REGION_NAME="one"
```

### OVA

```bash
export OVA_URL="10.8.3.97:/srv/examples"  # ip:/path
```

---

## Helper: Fetch CA Certificate

> **Security note (TOFU):** This helper performs trust-on-first-use. It trusts
> whatever certificate the endpoint presents during the initial fetch. On untrusted
> networks, obtain the CA certificate out-of-band (e.g. download from the vCenter UI,
> or the RHV engine PKI page over a pre-verified channel) and pass it directly via
> `--cacert <file>` instead of using this helper.

A reusable function that extracts the full certificate chain from any HTTPS endpoint.
Handles URLs with custom ports (e.g. `:13000`) and defaults to 443 when none is specified.

```bash
fetch_ca_cert() {
  local hostport
  hostport=$(echo "$1" | sed -E 's|https?://||; s|/.*||')
  if ! echo "${hostport}" | grep -q ':'; then
    hostport="${hostport}:443"
  fi
  openssl s_client -showcerts -connect "${hostport}" </dev/null 2>/dev/null \
    | awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/'
}
```

---

## vSphere Provider

The `GOVC_URL` does not include `/sdk`, so it is appended here.

```bash
oc mtv create provider \
  --name vsphere-provider \
  --type vsphere \
  --url "${GOVC_URL}/sdk" \
  --username "${GOVC_USERNAME}" \
  --password "${GOVC_PASSWORD}" \
  --cacert "$(fetch_ca_cert "${GOVC_URL}")"
```

### Verify the certificate first (optional)

```bash
curl --cacert <(fetch_ca_cert "${GOVC_URL}") "${GOVC_URL}/sdk" -o /dev/null -w "%{http_code}\n"
```

---

## oVirt / RHV Provider

The `RHV_URL` already contains the full path (`/ovirt-engine/api`), so it is passed directly.

```bash
oc mtv create provider \
  --name ovirt-provider \
  --type ovirt \
  --url "${RHV_URL}" \
  --username "${RHV_USERNAME}" \
  --password "${RHV_PASSWORD}" \
  --cacert "$(fetch_ca_cert "${RHV_URL}")"
```

---

## OpenStack Provider

The `OSP_URL` already contains the port and path (e.g. `:13000/v3`), so it is passed directly.

```bash
oc mtv create provider \
  --name openstack-provider \
  --type openstack \
  --url "${OSP_URL}" \
  --username "${OSP_USERNAME}" \
  --password "${OSP_PASSWORD}" \
  --provider-domain-name "${OSP_DOMAIN_NAME}" \
  --provider-project-name "${OSP_PROJECT_NAME}" \
  --provider-region-name "${OSP_REGION_NAME}" \
  --cacert "$(fetch_ca_cert "${OSP_URL}")"
```

---

## OVA Provider

OVA providers point to an NFS export path and do not require credentials or TLS certificates.
The `OVA_URL` is in `ip:/path` format.

```bash
oc mtv create provider \
  --name ova-provider \
  --type ova \
  --url "${OVA_URL}"
```

---

## Using a File Instead of an Inline String

If you prefer to pass a file, use the `@` prefix:

```bash
fetch_ca_cert "${GOVC_URL}" > vsphere-ca.pem

oc mtv create provider \
  --name vsphere-provider \
  --type vsphere \
  --url "${GOVC_URL}/sdk" \
  --username "${GOVC_USERNAME}" \
  --password "${GOVC_PASSWORD}" \
  --cacert @vsphere-ca.pem
```

---

## Skipping TLS (not recommended)

For development or testing only, you can skip certificate verification entirely:

```bash
oc mtv create provider \
  --name vsphere-dev \
  --type vsphere \
  --url "${GOVC_URL}/sdk" \
  --username "${GOVC_USERNAME}" \
  --password "${GOVC_PASSWORD}" \
  --provider-insecure-skip-tls
```

The `--provider-insecure-skip-tls` flag works with all provider types that use TLS
(vsphere, ovirt, openstack).

> **Tip:** RHV also publishes its CA at a well-known PKI endpoint.
> You can fetch it directly without `openssl`:
>
> ```bash
> RHV_HOST=$(echo "${RHV_URL}" | sed -E 's|https?://||; s|/.*||')
> oc mtv create provider \
>   --name ovirt-provider \
>   --type ovirt \
>   --url "${RHV_URL}" \
>   --username "${RHV_USERNAME}" \
>   --password "${RHV_PASSWORD}" \
>   --cacert "$(curl -sk "https://${RHV_HOST}/ovirt-engine/services/pki-resource?resource=ca-certificate&format=X509-PEM-CA")"
> ```
