#!/bin/sh
# Install MetalLB in both clusters so the east-west gateway LoadBalancer services get a
# reachable ingress IP. Required because `istioctl multicluster link` refuses to link
# unless the east-west gateway (istio.io/expose-istiod) is a LoadBalancer with an address;
# NodePort peering alone does not satisfy that check on bare minikube.
set -e
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPT_DIR}/../env.sh"

install_metallb() {
  context=${1:?context}
  # Use this cluster's OWN node IP as the /32 pool. vmnet-shared drops non-DHCP VIPs, so a
  # normal pool IP is unreachable from the peer VM; the node IP is the only reachable one.
  node_ip=$(minikube ip -p "${context}")
  pool="${node_ip}/32"
  echo "==> Installing MetalLB in ${context} (L2 pool ${pool}, = node IP)"
  kubectl --context "${context}" apply -f \
    "https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/config/manifests/metallb-native.yaml"

  # The controller (and its validating webhook) must be up before we apply the pool CRs,
  # otherwise the IPAddressPool is rejected by the webhook.
  kubectl --context "${context}" -n metallb-system rollout status deploy/controller --timeout=180s
  kubectl --context "${context}" -n metallb-system rollout status daemonset/speaker --timeout=180s

  # Pool is this cluster's own node IP, so the two clusters' pools are inherently distinct
  # and each announced IP is reachable across vmnet-shared.
  kubectl --context "${context}" apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: eastwest-pool
  namespace: metallb-system
spec:
  addresses:
  - ${pool}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: eastwest-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - eastwest-pool
EOF
}

install_metallb "${context1}"
install_metallb "${context2}"

echo "==> MetalLB installed in both clusters."
