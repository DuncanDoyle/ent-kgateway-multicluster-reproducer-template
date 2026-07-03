#!/bin/sh
# Shared environment for the enterprise-kgateway ambient multicluster reproducer.

# --- Istio (Solo) ---
export ISTIO_VERSION=1.30.2
export ISTIO_IMAGE=${ISTIO_VERSION}-solo
# Keyless Solo repos (Istio 1.29+). Do NOT use the legacy gloo-mesh/istio-<KEY> repos.
export REPO=us-docker.pkg.dev/soloio-img/istio
export HELM_REPO=us-docker.pkg.dev/soloio-img/istio-helm

# --- Cluster / network identity (context name doubles as network identity) ---
export cluster1=mc-1
export context1=mc-1
export cluster2=mc-2
export context2=mc-2
export EASTWEST_NAMESPACE=istio-eastwest
export METALLB_VERSION=v0.14.9

# --- Kubernetes Gateway API ---
export K8S_GW_API_VERSION=v1.4.0

# --- Enterprise kgateway (SEFK) ---
# NOTE: SEFK 2.2.x officially supports Istio 1.25-1.29. We run 1.30.2-solo (above the
# documented matrix) to reuse the proven ambient-multicluster foundation. Expected to work
# (kgateway OSS targets 1.30 APIs) but NOT a supported customer combination.
export ENT_KGATEWAY_VERSION=2.2.4
export ENT_KGATEWAY_SYSTEM_NAMESPACE=kgateway-system
export ENT_KGATEWAY_CRDS_URL=oci://us-docker.pkg.dev/solo-public/enterprise-kgateway/charts/enterprise-kgateway-crds
export ENT_KGATEWAY_URL=oci://us-docker.pkg.dev/solo-public/enterprise-kgateway/charts/enterprise-kgateway

# --- License guards ---
if [ -z "$SOLO_ISTIO_LICENSE_KEY" ]; then
  echo "ERROR: SOLO_ISTIO_LICENSE_KEY is not set (Enterprise Solo Istio license)." >&2
  return 1 2>/dev/null || exit 1
fi
if [ -z "$ENT_KGATEWAY_LICENSE_KEY" ]; then
  echo "ERROR: ENT_KGATEWAY_LICENSE_KEY is not set (Solo Enterprise for kgateway license)." >&2
  return 1 2>/dev/null || exit 1
fi
