#!/bin/sh
set -e
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPT_DIR}/../env.sh"

# Generate the shared root CA + per-cluster intermediate CAs using Istio's cert Makefiles,
# vendored under install/certs/ (see install/certs/README.md). We do NOT download the Istio
# release archive: the Solo istioctl on PATH is a prerequisite, and these two Makefiles are the
# only artefacts that step needed. Generated output goes to the git-ignored _generated/ dir.
CERTS_MK="${SCRIPT_DIR}/certs/Makefile.selfsigned.mk"
WORKDIR="${SCRIPT_DIR}/certs/_generated"
mkdir -p "${WORKDIR}"
cd "${WORKDIR}"
make -f "${CERTS_MK}" root-ca

create_cacerts_secret() {
  context=${1:?context}
  cluster=${2:?cluster}
  make -f "${CERTS_MK}" ${cluster}-cacerts
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
