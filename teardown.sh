#!/bin/sh
# Remove everything created by setup.sh, leaving the installed + linked multi-cluster mesh
# (install/00-04 output: istio-system, MetalLB, east-west gateways, the link, kgateway-system)
# intact. Use this to reset the workload/gateway layer so you can re-run ./setup.sh with a
# different configuration. To delete the clusters entirely, use ./destroy-clusters.sh instead.
set -e
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPT_DIR}/env.sh"

echo "==> Removing north-south route + gateway (cluster-1: ${context1})"
kubectl --context "${context1}" delete -f "${SCRIPT_DIR}/routes/httpbin-httproute.yaml" --ignore-not-found
# Deleting the ingress-gw namespace removes the Gateway, its EnterpriseKgatewayParameters, and
# the auto-provisioned proxy Deployment/Service in one shot (all created by setup.sh).
kubectl --context "${context1}" delete namespace ingress-gw --ignore-not-found
# setup.sh labeled the default namespace so the route could attach; undo it.
kubectl --context "${context1}" label namespace default shared-gateway-access- 2>/dev/null || true

echo "==> Removing global backend from both clusters"
# Deleting the httpbin namespace removes the Deployment/Service/ServiceAccount and the
# solo.io/service-scope=global label; istiod then garbage-collects the autogen
# httpbin.httpbin.mesh.internal ServiceEntry in istio-system automatically.
for ctx in "${context1}" "${context2}"; do
  kubectl --context "${ctx}" delete namespace httpbin --ignore-not-found
done

# Wait for istiod to drop the auto-generated global ServiceEntry so a fresh setup.sh starts clean.
echo "==> Waiting for the autogen ServiceEntry to be garbage-collected..."
kubectl --context "${context1}" -n istio-system wait --for=delete serviceentry/autogen.httpbin.httpbin --timeout=60s 2>/dev/null || true

echo "==> Reset complete. The linked mesh is intact; re-run ./setup.sh to deploy a configuration."
