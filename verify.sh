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
  curl -sS -o /dev/null -w "%{http_code}" --max-time 5 \
    -H "Host: api.example.com" "http://localhost:${LOCAL_PORT}/get"
}

echo "==> [1] North-south through kgateway (both clusters have endpoints)"
code=$(curl_gw); echo "    status=${code}"
[ "${code}" = "200" ] || { echo "FAIL: expected 200 north-south, got ${code}" >&2; exit 1; }

echo "==> [2] Cross-cluster failover: scale ${context1} httpbin to 0"
kubectl --context "${context1}" -n httpbin scale deploy/httpbin --replicas=0
kubectl --context "${context1}" -n httpbin rollout status deploy/httpbin --timeout=60s || true

# Poll until the kgateway proxy fails over to the remote cluster. enterprise-kgateway keeps
# routing to the terminating LOCAL endpoint until istiod removes it from EDS (~30s observed),
# so this is a wait-for-condition, not a fixed sleep. See README "Observed behavior".
FAILOVER_TIMEOUT=120
echo "    Waiting for failover to ${context2} over HBONE (timeout ${FAILOVER_TIMEOUT}s)..."
elapsed=0; code=""
while [ "${elapsed}" -le "${FAILOVER_TIMEOUT}" ]; do
  code=$(curl_gw)
  if [ "${code}" = "200" ]; then
    echo "    status=200 after ~${elapsed}s (served by ${context2} over HBONE)"
    break
  fi
  sleep 3; elapsed=$((elapsed+3))
done

echo "==> [3] Restore ${context1} httpbin"
kubectl --context "${context1}" -n httpbin scale deploy/httpbin --replicas=1
kubectl --context "${context1}" -n httpbin rollout status deploy/httpbin --timeout=120s

if [ "${code}" = "200" ]; then
  echo "==> PASS: north-south served; cross-cluster failover succeeded after ~${elapsed}s."
else
  echo "==> FAIL: no failover within ${FAILOVER_TIMEOUT}s (last status=${code})." >&2
  exit 1
fi
