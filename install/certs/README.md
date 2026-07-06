# Vendored Istio cert-generation Makefiles

`Makefile.selfsigned.mk` and `common.mk` are copied verbatim from
[`istio/istio` `release-1.30` `tools/certs/`](https://github.com/istio/istio/tree/release-1.30/tools/certs)
(Apache-2.0). `00-create-shared-ca.sh` uses their `root-ca` and `<cluster>-cacerts` targets to
generate the shared root CA and the per-cluster intermediate CAs that become the `cacerts`
secrets in each cluster.

**Why vendored instead of downloaded:** the earlier version of `00-create-shared-ca.sh` ran
`curl -L https://istio.io/downloadIstio | sh -`, pulling the entire multi-hundred-MB Istio
release archive just to obtain these two Makefiles — and it did so even when the correct Solo
`istioctl` was already on `PATH`, which was confusing. Vendoring makes the repo self-contained,
removes the download, and pins the exact cert flow to a known Istio version.

Generated output goes to `_generated/` (git-ignored), not here.

To refresh from upstream:
```sh
curl -sSfLo Makefile.selfsigned.mk https://raw.githubusercontent.com/istio/istio/release-1.30/tools/certs/Makefile.selfsigned.mk
curl -sSfLo common.mk               https://raw.githubusercontent.com/istio/istio/release-1.30/tools/certs/common.mk
# then re-add the vendored-from header comment at the top of each file
```
