#!/bin/sh
set -e
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPT_DIR}/../env.sh"
cd "${SCRIPT_DIR}"

# Download community istio (for tools/certs/Makefile.selfsigned.mk) if not present.
if [ ! -d "istio-${ISTIO_VERSION}" ]; then
  curl -L https://istio.io/downloadIstio | ISTIO_VERSION=${ISTIO_VERSION} sh -
fi

cd istio-${ISTIO_VERSION}
mkdir -p certs
cd certs
make -f ../tools/certs/Makefile.selfsigned.mk root-ca

create_cacerts_secret() {
  context=${1:?context}
  cluster=${2:?cluster}
  make -f ../tools/certs/Makefile.selfsigned.mk ${cluster}-cacerts
  kubectl --context=${context} create ns istio-system || true
  kubectl --context=${context} create secret generic cacerts -n istio-system \
    --from-file=${cluster}/ca-cert.pem \
    --from-file=${cluster}/ca-key.pem \
    --from-file=${cluster}/root-cert.pem \
    --from-file=${cluster}/cert-chain.pem
}

create_cacerts_secret ${context1} ${cluster1}
create_cacerts_secret ${context2} ${cluster2}
echo "==> cacerts installed in both clusters."
