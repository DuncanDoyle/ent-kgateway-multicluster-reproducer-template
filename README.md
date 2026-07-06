# Enterprise kgateway — Istio Ambient Multicluster Reproducer Template

Self-contained template that stands up a two-cluster Solo Istio **Ambient multicluster** mesh
with **enterprise kgateway** (SEFK) in cluster-1, and demonstrates kgateway routing north-south
to a **global** service that fails over cross-cluster over HBONE.

> ⚠️ **Version note:** SEFK 2.2.x officially supports Istio 1.25–1.29. This template runs Solo
> Istio **1.30.2-solo** (one minor above the documented matrix) to reuse a proven ambient
> multicluster foundation. It is expected to work but is **not a supported customer combination**.
>
> **Gateway API version (`K8S_GW_API_VERSION` in `env.sh`) must track the kgateway controller.**
> SEFK 2.2.x is built on kgateway OSS **2.3.x** (SEFK 2.2.4 → OSS v2.3.5), which pins GW API
> **v1.5.1** — so the template installs v1.5.1. If you bump the SEFK version, re-check the OSS base
> in `gloo-gateway`'s `go.mod` and its `sigs.k8s.io/gateway-api` pin, and update this value.

## Prerequisites

- Two **empty** vfkit minikube clusters on `vmnet-shared`:
  ```sh
  minikube-create-multicluster-vfkit.sh mc      # creates mc-1 and mc-2
  ```
- Solo `istioctl` on PATH (community istioctl lacks `multicluster`):
  ```sh
  bash <(curl -sSfL https://raw.githubusercontent.com/solo-io/doc-examples/main/istio/install-istioctl.sh)
  export PATH=${HOME}/.istioctl/bin:${PATH}
  ```
- Licenses:
  ```sh
  export SOLO_ISTIO_LICENSE_KEY=<solo istio license>
  export ENT_KGATEWAY_LICENSE_KEY=<enterprise kgateway license>
  ```

## Run in order

```sh
. ./env.sh
./install/00-create-shared-ca.sh     # shared root CA + cacerts in both clusters
./install/01-install-metallb.sh      # MetalLB; east-west LB ingress IP = each node's own IP
./install/02-install-ambient.sh      # istiod/cni/ztunnel (ambient IPv6 disabled)
./install/03-link-clusters.sh        # east-west gateways (LoadBalancer) + multicluster link
./install/04-install-ent-kgateway.sh # enterprise kgateway 2.2.4 in cluster-1
./setup.sh                           # global backend (both clusters) + Gateway/route (cluster-1)
./verify.sh                          # SUCCESS GATE: north-south 200, then failover 200
```

Teardown: `./teardown.sh` (deletes both minikube profiles).

## How it works

- **Shared root CA:** multi-primary ambient multicluster requires both clusters to trust a common
  root CA, so `00-create-shared-ca.sh` generates one root CA plus a per-cluster intermediate and
  installs them as the `cacerts` secret in each `istio-system` **before** istiod starts. It does
  this with Istio's standard `tools/certs` Makefiles, which are **vendored** under `install/certs/`
  (see `install/certs/README.md`) — the script does *not* download the Istio release archive. Your
  Solo `istioctl` on `PATH` is a prerequisite and is used unchanged by the later steps.
- **Global service:** httpbin is deployed to the `httpbin` namespace in both clusters, the ns is
  ambient-enrolled (`istio.io/dataplane-mode=ambient`), and the Service is labeled
  `solo.io/service-scope=global` → auto-generates the `httpbin.httpbin.mesh.internal` ServiceEntry.
- **kgateway → global service:** the Gateway's proxy runs in `ingress-gw`, which is ambient-enrolled
  so its egress uses HBONE. `KGW_ENABLE_ISTIO_INTEGRATION=true` lets the HTTPRoute target the
  `Hostname` backend `httpbin.httpbin.mesh.internal`.
- **North-south access:** the proxy Service is `ClusterIP`; `verify.sh` uses `kubectl port-forward`
  (MetalLB's only reachable IP — the node IP `/32` — is used by the east-west gateway).

## Observed behavior: ~30s failover gap through the gateway

When the **last local (cluster-1) endpoint** of the global service terminates, the
enterprise-kgateway proxy keeps routing to the dead local endpoint for **~30s** before failing
over to the healthy remote (cluster-2) endpoint over HBONE. During that window every request
through the gateway returns **503**. An in-mesh **ztunnel client fails over immediately** (stays
200 throughout) — so this gap is specific to the L7 gateway path, not the mesh.

Root cause: the auto-generated global ServiceEntry carries `traffic-distribution: PreferNetwork`,
and the kgateway backend cluster has **no outlier detection / active health-checking**, so the
terminating local endpoint stays in the Envoy load-balancing set (marked `healthy`) and keeps
receiving 100% of traffic until istiod removes it from EDS (~30s). `verify.sh` therefore
waits-for-condition and reports the measured failover time rather than asserting instant failover.

## vfkit/minikube gotchas (already handled by the scripts)

- **`link` needs a LoadBalancer, not NodePort** → MetalLB (`01`).
- **MetalLB VIPs don't traverse `vmnet-shared`** → pool = each cluster's own node IP `/32` (`01`).
- **Ambient IPv6 must be off** (ISO kernel lacks `CONFIG_IPV6_MULTIPLE_TABLES`) → `cni.ambient.ipv6=false`
  + ztunnel `IPV6_ENABLED=false` (`02`).
