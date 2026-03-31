# namiviewk8s

Kubernetes infrastructure and ArgoCD GitOps configuration for the Namiview platform. Manages 16+ applications across 10 namespaces on a bare-metal kubeadm cluster.

| Service | URL |
|---|---|
| Application | [namiview.com](https://namiview.com) |
| Monitoring | [grafana.namiview.com](https://grafana.namiview.com) |
| GitOps | [argocd.namiview.com](https://argocd.namiview.com) |

---

## Cluster

3-node bare-metal cluster provisioned with kubeadm (not managed Kubernetes):

| Node | Role | OS |
|------|------|----|
| k8s-master | control-plane | Ubuntu 24.04, K8s v1.35.0 |
| k8s-worker1 | worker | Ubuntu 24.04, K8s v1.35.0 |
| k8s-worker2 | worker | Ubuntu 24.04, K8s v1.35.0 |

## Architecture

Uses the ArgoCD **app-of-apps** pattern:

```
bootstrap/
  ├── ArgoCD HA installation (v3.3.0)
  ├── infrastructure-root  -->  infrastructure/*-app.yaml  (11 infra apps)
  └── apps-root            -->  apps/*.yaml                (4 namiview apps)
```

All applications use **auto-sync + prune + self-heal** -- the cluster continuously reconciles to match Git.

## Namespace Layout

| Namespace | Contents |
|-----------|----------|
| `namiview-app` | Production API (2 replicas) + UI (2 replicas) |
| `namiview-dev` | Development API + UI (1 replica each) |
| `namiview-infra` | MongoDB 3-replica set + MinIO object storage |
| `vault` | Vault HA cluster (3-node Raft) |
| `monitoring` | Prometheus, Grafana, Grafana Operator, AlertManager |
| `cloudflare` | Cloudflare Tunnel (2 replicas) |
| `argocd` | ArgoCD controller + HA Redis |
| `external-secrets` | External Secrets Operator |
| `kube-system` | CoreDNS, metrics-server, kube-proxy |
| `local-path-storage` | Rancher local-path-provisioner |

## Infrastructure Components

| Component | Version | Configuration |
|-----------|---------|--------------|
| HashiCorp Vault | Helm 0.32.0 | HA Raft (3 replicas), 3Gi storage per node |
| MongoDB | Bitnami 18.3.0 | Replica set (3 replicas), 3Gi storage per node |
| MinIO | Bitnami 17.0.21 | Single node, 10Gi, console disabled |
| Prometheus | kube-prometheus-stack 81.5.0 | 5-day retention, 5Gi storage |
| Grafana | (via kube-prometheus-stack) | HTTPS, persistent 2Gi, 7 dashboards |
| Grafana Operator | 5.22.2 | Manages dashboards via CRDs |
| Cloudflare Tunnel | cloudflared:latest | Replaces traditional ingress controller |
| External Secrets Operator | 1.3.1 | Vault KV v2 backend, 1h refresh |
| metrics-server | 3.13.0 | Resource metrics for HPA/VPA |
| local-path-provisioner | (Rancher upstream) | Default StorageClass, Retain policy |

## Secrets Management

```
Vault (HA Raft) --> External Secrets Operator --> Kubernetes Secrets --> Pods
```

All secrets are stored in Vault and synced to Kubernetes via ExternalSecret CRs with a ClusterSecretStore. No credentials in Git. Refresh interval: 1 hour.

## Monitoring

7 ServiceMonitors scrape metrics from Vault, MongoDB, MinIO, ArgoCD (x3 endpoints), and Cloudflare Tunnel. 7 Grafana dashboards (1 custom application dashboard + 6 community dashboards) are managed as GrafanaDashboard CRDs via the Grafana Operator.

## Ingress

Cloudflare Tunnel provides zero-trust ingress without a traditional ingress controller. Two replicas run in the `cloudflare` namespace, routing external traffic to internal services. TLS certificates are managed through Cloudflare and distributed via Vault.

## Repository Structure

```
apps/               ArgoCD Application manifests (prod/dev x api/ui)
bootstrap/          ArgoCD installation and app-of-apps roots
infrastructure/     Infrastructure services (vault, mongodb, minio, monitoring, etc.)
  ├── <service>/    Kustomization + Helm values + external secrets
  ├── <service>-app.yaml   ArgoCD Application definition
  └── monitoring/service-monitors/   Prometheus scrape targets
```

## Related Repositories

| Repository | Purpose |
|---|---|
| [namiview](https://github.com/Darbuki/namiview) | Application source (FastAPI + React) |
| [namiview-charts](https://github.com/Darbuki/namiview-charts) | Helm charts with multi-environment values |
| [namiview-base](https://github.com/Darbuki/namiview-base) | Base Docker image (Python 3.12 + PyTorch CPU) |
