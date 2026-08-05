#!/bin/bash

# Create MTV source providers from environment variables.
#
# Usage: ./create-providers.sh
#
# Set the environment variables for the providers you want to create.
# Only providers whose required variables are set will be created.
#
# Common:
#   INSECURE_SKIP_TLS=true   -- skip TLS verification instead of fetching CA certs
#
# vSphere:   GOVC_URL, GOVC_USERNAME, GOVC_PASSWORD
# oVirt/RHV: RHV_URL, RHV_USERNAME, RHV_PASSWORD
# OpenStack: OSP_URL, OSP_USERNAME, OSP_PASSWORD, OSP_DOMAIN_NAME, OSP_PROJECT_NAME, OSP_REGION_NAME
# OVA:       OVA_URL

set -euo pipefail

INSECURE_SKIP_TLS="${INSECURE_SKIP_TLS:-false}"

# TOFU warning: These helpers trust whatever certificate the endpoint presents
# during the initial fetch. On untrusted networks, obtain the CA out-of-band
# (e.g. vCenter UI download) and pass it directly via --cacert <file>.
fetch_ca_cert_tls() {
  local hostport host
  hostport=$(echo "$1" | sed -E 's|https?://||; s|/.*||')
  host="${hostport%%:*}"
  if ! echo "${hostport}" | grep -q ':'; then
    hostport="${hostport}:443"
  fi
  openssl s_client -showcerts -servername "${host}" \
    -connect "${hostport}" </dev/null 2>/dev/null \
    | awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/'
}

fetch_ca_cert_ovirt() {
  local host cert_url cert
  host=$(echo "$1" | sed -E 's|https?://||; s|[:/].*||')
  cert_url="https://${host}/ovirt-engine/services/pki-resource?resource=ca-certificate&format=X509-PEM-CA"
  cert=$(curl -sSk "${cert_url}") || {
    echo "ERROR: Failed to fetch CA certificate from ${cert_url}" >&2
    return 1
  }
  if ! echo "${cert}" | grep -q -- "-----BEGIN CERTIFICATE-----" ||
     ! echo "${cert}" | grep -q -- "-----END CERTIFICATE-----"; then
    echo "ERROR: Response from ${cert_url} is not valid PEM" >&2
    return 1
  fi
  echo "${cert}"
}

created=0

# --- vSphere ---
if [[ -n "${GOVC_URL:-}" && -n "${GOVC_USERNAME:-}" && -n "${GOVC_PASSWORD:-}" ]]; then
  echo "Creating vSphere provider..."
  if [[ "${INSECURE_SKIP_TLS}" == "true" ]]; then
    oc mtv create provider \
      --name vsphere-provider \
      --type vsphere \
      --url "https://${GOVC_URL}/sdk" \
      --username "${GOVC_USERNAME}" \
      --password "${GOVC_PASSWORD}" \
      --provider-insecure-skip-tls
  else
    oc mtv create provider \
      --name vsphere-provider \
      --type vsphere \
      --url "https://${GOVC_URL}/sdk" \
      --username "${GOVC_USERNAME}" \
      --password "${GOVC_PASSWORD}" \
      --cacert "$(fetch_ca_cert_tls "${GOVC_URL}")"
  fi
  echo "vSphere provider created."
  created=$((created + 1))
fi

# --- oVirt / RHV ---
if [[ -n "${RHV_URL:-}" && -n "${RHV_USERNAME:-}" && -n "${RHV_PASSWORD:-}" ]]; then
  echo "Creating oVirt/RHV provider..."
  if [[ "${INSECURE_SKIP_TLS}" == "true" ]]; then
    oc mtv create provider \
      --name ovirt-provider \
      --type ovirt \
      --url "${RHV_URL}" \
      --username "${RHV_USERNAME}" \
      --password "${RHV_PASSWORD}" \
      --provider-insecure-skip-tls
  else
    oc mtv create provider \
      --name ovirt-provider \
      --type ovirt \
      --url "${RHV_URL}" \
      --username "${RHV_USERNAME}" \
      --password "${RHV_PASSWORD}" \
      --cacert "$(fetch_ca_cert_ovirt "${RHV_URL}")"
  fi
  echo "oVirt/RHV provider created."
  created=$((created + 1))
fi

# --- OpenStack ---
if [[ -n "${OSP_URL:-}" && -n "${OSP_USERNAME:-}" && -n "${OSP_PASSWORD:-}" ]]; then
  echo "Creating OpenStack provider..."
  if [[ "${INSECURE_SKIP_TLS}" == "true" ]]; then
    oc mtv create provider \
      --name openstack-provider \
      --type openstack \
      --url "${OSP_URL}" \
      --username "${OSP_USERNAME}" \
      --password "${OSP_PASSWORD}" \
      --provider-domain-name "${OSP_DOMAIN_NAME:-Default}" \
      --provider-project-name "${OSP_PROJECT_NAME:-admin}" \
      --provider-region-name "${OSP_REGION_NAME:-regionOne}" \
      --provider-insecure-skip-tls
  else
    oc mtv create provider \
      --name openstack-provider \
      --type openstack \
      --url "${OSP_URL}" \
      --username "${OSP_USERNAME}" \
      --password "${OSP_PASSWORD}" \
      --provider-domain-name "${OSP_DOMAIN_NAME:-Default}" \
      --provider-project-name "${OSP_PROJECT_NAME:-admin}" \
      --provider-region-name "${OSP_REGION_NAME:-regionOne}" \
      --cacert "$(fetch_ca_cert_tls "${OSP_URL}")"
  fi
  echo "OpenStack provider created."
  created=$((created + 1))
fi

# --- OVA ---
if [[ -n "${OVA_URL:-}" ]]; then
  echo "Creating OVA provider..."
  oc mtv create provider \
    --name ova-provider \
    --type ova \
    --url "${OVA_URL}"
  echo "OVA provider created."
  created=$((created + 1))
fi

if [[ ${created} -eq 0 ]]; then
  echo "No provider environment variables found. Nothing to create." >&2
  echo "See docs/create-providers-cli.md for required variables." >&2
  exit 1
fi

echo ""
echo "Done. Created ${created} provider(s)."
