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
