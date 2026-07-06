#!/bin/sh
set -e
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPT_DIR}/../env.sh"
cd "${SCRIPT_DIR}"

# Optional pre-check (baseline only). This runs BEFORE the east-west gateways and peers are
# created below, so it is EXPECTED to report "no configured eastwest gateways / no configured
# peers" and exit non-zero with "multicluster check found issues". That is normal on an
# unlinked environment; `|| true` ignores it. The post-link check (see the final message) is
# the one that should pass.
echo "==> Pre-link baseline check (EXPECTED to fail: no gateways/peers configured yet)..."
istioctl multicluster check --contexts="${context1},${context2}" || true

create_ew_gateway() {
  context=${1:?context}
  cluster=${2:?cluster}
  kubectl create namespace ${EASTWEST_NAMESPACE} --context ${context} --dry-run=client -o yaml \
    | kubectl --context ${context} apply -f -
  # Default LoadBalancer service. MetalLB (01-install-metallb.sh) assigns it a reachable
  # ingress IP from the vmnet-shared segment, which `istioctl multicluster link` requires.
  istioctl multicluster expose --namespace ${EASTWEST_NAMESPACE} --context ${context} --generate \
    > ew-gateway-${cluster}.yaml
  kubectl apply -f ew-gateway-${cluster}.yaml --context ${context}
}

create_ew_gateway ${context1} ${cluster1}
create_ew_gateway ${context2} ${cluster2}

# Wait for each east-west gateway to be programmed AND to receive a LoadBalancer IP from
# MetalLB before linking — link reads that ingress IP as the peer east-west address.
wait_for_lb_ip() {
  context=${1:?context}
  kubectl --context ${context} -n ${EASTWEST_NAMESPACE} rollout status deploy/istio-eastwest --timeout=120s || true
  echo "Waiting for east-west LoadBalancer IP in ${context}..."
  for _ in $(seq 1 30); do
    ip=$(kubectl --context ${context} -n ${EASTWEST_NAMESPACE} \
      get svc istio-eastwest -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    if [ -n "$ip" ]; then echo "  ${context} east-west LB IP: $ip"; return 0; fi
    sleep 2
  done
  echo "  ERROR: no LoadBalancer IP assigned in ${context} (is MetalLB running?)" >&2
  return 1
}

wait_for_lb_ip ${context1}
wait_for_lb_ip ${context2}

# Link over the LoadBalancer addresses (default service type).
istioctl multicluster link \
  --namespace ${EASTWEST_NAMESPACE} \
  --contexts="${context1},${context2}"

echo "==> Clusters linked. Run: istioctl multicluster check --contexts=${context1},${context2}"
