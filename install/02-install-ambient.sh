#!/bin/sh
set -e
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPT_DIR}/../env.sh"

install_gwapi() {
  context=${1:?context}
  kubectl --context ${context} apply --server-side -f \
    https://github.com/kubernetes-sigs/gateway-api/releases/download/${K8S_GW_API_VERSION}/experimental-install.yaml
}

install_base() {
  context=${1:?context}
  helm upgrade --install istio-base oci://${HELM_REPO}/base \
    --namespace istio-system --create-namespace --kube-context ${context} \
    --version ${ISTIO_IMAGE} -f - <<EOF
defaultRevision: ""
profile: ambient
EOF
}

install_istiod() {
  context=${1:?context}
  cluster=${2:?cluster}
  helm upgrade --install istiod oci://${HELM_REPO}/istiod \
    --namespace istio-system --kube-context ${context} \
    --version ${ISTIO_IMAGE} -f - <<EOF
env:
  PILOT_ENABLE_IP_AUTOALLOCATE: "true"
  PILOT_SKIP_VALIDATE_TRUST_DOMAIN: "true"
  DISABLE_LEGACY_MULTICLUSTER: "true"
global:
  hub: ${REPO}
  multiCluster:
    clusterName: ${cluster}
  network: ${cluster}
  proxy:
    clusterDomain: cluster.local
  tag: ${ISTIO_IMAGE}
meshConfig:
  accessLogFile: /dev/stdout
  defaultConfig:
    proxyMetadata:
      ISTIO_META_DNS_CAPTURE: "true"
  trustDomain: "${cluster}.local"
pilot:
  cni:
    namespace: istio-system
    enabled: true
platforms:
  peering:
    enabled: true
profile: ambient
license:
  value: ${SOLO_ISTIO_LICENSE_KEY}
EOF
}

install_cni() {
  context=${1:?context}
  helm upgrade --install istio-cni oci://${HELM_REPO}/cni \
    --namespace istio-system --kube-context ${context} \
    --version ${ISTIO_IMAGE} -f - <<EOF
ambient:
  dnsCapture: true
  # The minikube vfkit ISO kernel lacks CONFIG_IPV6_MULTIPLE_TABLES, so the ambient CNI
  # agent cannot program IPv6 policy-routing rules for in-pod redirection ("failed to
  # configure netlink rule: address family not supported"). Disable ambient IPv6.
  ipv6: false
excludeNamespaces:
  - istio-system
  - kube-system
global:
  hub: ${REPO}
  tag: ${ISTIO_IMAGE}
profile: ambient
EOF
}

install_ztunnel() {
  context=${1:?context}
  cluster=${2:?cluster}
  helm upgrade --install ztunnel oci://${HELM_REPO}/ztunnel \
    --namespace istio-system --kube-context ${context} \
    --version ${ISTIO_IMAGE} -f - <<EOF
configValidation: true
enabled: true
env:
  L7_ENABLED: "true"
  SKIP_VALIDATE_TRUST_DOMAIN: "true"
  # Match cni.ambient.ipv6=false: this kernel has no IPv6 policy routing, so ztunnel must
  # not attempt to bind/redirect over IPv6.
  IPV6_ENABLED: "false"
hub: ${REPO}
istioNamespace: istio-system
multiCluster:
  clusterName: ${cluster}
namespace: istio-system
network: ${cluster}
profile: ambient
proxy:
  clusterDomain: cluster.local
tag: ${ISTIO_IMAGE}
terminationGracePeriodSeconds: 29
variant: distroless
EOF
}

for pair in "${context1} ${cluster1}" "${context2} ${cluster2}"; do
  set -- $pair; ctx=$1; cl=$2
  echo "==> Installing ambient control plane in ${ctx} (network ${cl})"
  install_gwapi ${ctx}
  install_base ${ctx}
  install_istiod ${ctx} ${cl}
  install_cni ${ctx}
  install_ztunnel ${ctx} ${cl}
  kubectl label namespace istio-system --context ${ctx} --overwrite topology.istio.io/network=${cl}
done

echo "==> Ambient control plane installed in both clusters."
