#!/bin/sh
set -e
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPT_DIR}/env.sh"

GW_NS=ingress-gw
GW_SVC=$(kubectl --context "${context1}" -n "${GW_NS}" get svc \
  -l gateway.networking.k8s.io/gateway-name=gw -o jsonpath='{.items[0].metadata.name}')
[ -n "${GW_SVC}" ] || { echo "ERROR: gateway service not found in ${GW_NS}" >&2; exit 1; }

LOCAL_PORT=8080
kubectl --context "${context1}" -n "${GW_NS}" port-forward "svc/${GW_SVC}" ${LOCAL_PORT}:80 >/dev/null 2>&1 &
PF_PID=$!
trap 'kill ${PF_PID} 2>/dev/null || true' EXIT
sleep 3

curl_gw() {
  curl -sS -o /dev/null -w "status=%{http_code}\n" \
    -H "Host: api.example.com" "http://localhost:${LOCAL_PORT}/get"
}

echo "==> [1] North-south through kgateway (both clusters have endpoints)"
curl_gw

echo "==> [2] Failover: scale ${context1} httpbin to 0 (must be served by ${context2} over HBONE)"
kubectl --context "${context1}" -n httpbin scale deploy/httpbin --replicas=0
kubectl --context "${context1}" -n httpbin rollout status deploy/httpbin --timeout=60s || true
sleep 5
curl_gw

echo "==> [3] Restore ${context1} httpbin"
kubectl --context "${context1}" -n httpbin scale deploy/httpbin --replicas=1
kubectl --context "${context1}" -n httpbin rollout status deploy/httpbin --timeout=120s

echo "==> PASS if both [1] and [2] returned status=200."
