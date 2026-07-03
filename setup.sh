#!/bin/sh
set -e
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPT_DIR}/env.sh"

# 1. Deploy the global backend to BOTH clusters (ambient-captured, service-scope=global).
deploy_backend() {
  context=${1:?context}
  kubectl --context "${context}" create namespace httpbin --dry-run=client -o yaml \
    | kubectl --context "${context}" apply -f -
  kubectl --context "${context}" label namespace httpbin --overwrite istio.io/dataplane-mode=ambient
  kubectl --context "${context}" apply -f "${SCRIPT_DIR}/apps/httpbin.yaml"
  kubectl --context "${context}" -n httpbin rollout status deploy/httpbin --timeout=120s
  # Same name/ns in both clusters + this label -> auto-generated httpbin.httpbin.mesh.internal.
  kubectl --context "${context}" label service httpbin -n httpbin --overwrite solo.io/service-scope=global
}
deploy_backend "${context1}"
deploy_backend "${context2}"
echo "==> Global backend deployed in both clusters."

# 2. kgateway proxy runs in ingress-gw; join it to the ambient mesh so its egress to the
#    global backend goes over HBONE/ztunnel. Label BEFORE the proxy pod is created. (cluster-1)
kubectl --context "${context1}" create namespace ingress-gw --dry-run=client -o yaml \
  | kubectl --context "${context1}" apply -f -
kubectl --context "${context1}" label namespace ingress-gw --overwrite istio.io/dataplane-mode=ambient

# 3. Allow HTTPRoutes from the default namespace to attach to the Gateway.
kubectl --context "${context1}" label namespace default --overwrite shared-gateway-access="true"

# 4. Apply the Gateway, its parameters, and the route (cluster-1).
kubectl --context "${context1}" apply -f "${SCRIPT_DIR}/gateways/gw-parameters.yaml"
kubectl --context "${context1}" apply -f "${SCRIPT_DIR}/gateways/gw.yaml"
kubectl --context "${context1}" apply -f "${SCRIPT_DIR}/routes/httpbin-httproute.yaml"

echo "==> Setup complete. Run ./verify.sh"
