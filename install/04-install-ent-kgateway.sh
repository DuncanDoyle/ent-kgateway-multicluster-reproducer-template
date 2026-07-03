#!/bin/sh
set -e
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPT_DIR}/../env.sh"

# K8s Gateway API — experimental channel (enterprise CRDs require it).
kubectl --context "${context1}" apply --server-side -f \
  "https://github.com/kubernetes-sigs/gateway-api/releases/download/${K8S_GW_API_VERSION}/experimental-install.yaml"

echo "==> Installing enterprise-kgateway CRDs ${ENT_KGATEWAY_VERSION} in ${context1}"
helm upgrade --install enterprise-kgateway-crds "${ENT_KGATEWAY_CRDS_URL}" \
  --kube-context "${context1}" \
  --version "${ENT_KGATEWAY_VERSION}" \
  --namespace "${ENT_KGATEWAY_SYSTEM_NAMESPACE}" --create-namespace \
  --set installExtAuthCRDs=true \
  --set installRateLimitCRDs=true \
  --set installEnterpriseListenerSetCRD=true

echo "==> Installing enterprise-kgateway ${ENT_KGATEWAY_VERSION} in ${context1}"
helm upgrade --install enterprise-kgateway "${ENT_KGATEWAY_URL}" \
  --kube-context "${context1}" \
  --version "${ENT_KGATEWAY_VERSION}" \
  --namespace "${ENT_KGATEWAY_SYSTEM_NAMESPACE}" --create-namespace \
  --set-string licensing.licenseKey="${ENT_KGATEWAY_LICENSE_KEY}" \
  -f "${SCRIPT_DIR}/enterprise-kgateway-values.yaml"

kubectl --context "${context1}" -n "${ENT_KGATEWAY_SYSTEM_NAMESPACE}" \
  wait --for=condition=Available deploy --all --timeout=180s
echo "==> enterprise-kgateway installed in ${context1}."
