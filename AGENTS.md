# Namiview Project Guide for Agents

> **⚠️ START HERE → the project front door is `ONBOARDING.md` in the `namiview` repo.**
> Live platform = homelab **k3s** + AWS-managed services (see `namiview/docs/architecture-current.md`).
> This repo is the **GitOps source of truth**: the live app sets are **`apps-homelab/`**
> (prod) and **`apps-homelab-dev/`** (dev); the `apps/` + `bootstrap/` overlays are
> **EKS-era and dormant**, kept for revival (`namiview/docs/eks-revival.md`). Some text
> below reflects the earlier EKS/kubeadm setup — trust the `*-homelab` dirs + the front
> door for what's live. *(banner added 2026-06-20)*

This document explains the Namiview project: how to develop locally, how deployment works, and how the infrastructure is structured.

---

## Project Overview

**Namiview** is an underwater image restoration web app. Users upload photos, the app runs AI (FunieGAN) and physics-based enhancement pipelines, and results can be saved to a personal gallery.

| Repository         | Purpose |
|--------------------|---------|
| `namiview`         | Application source: FastAPI backend + React/Vite frontend |
| `namiviewk8s`      | ArgoCD apps, infrastructure as code, service monitors, dashboards |
| `namiview-charts`  | Helm charts (`namiview-api`, `namiview-ui`) |
| `namiview-base`    | Base Docker image: Python 3.12 + PyTorch CPU + system deps |

**Tech stack:**
- **Frontend:** React + Vite + Tailwind (served by nginx on port 80)
- **Backend:** FastAPI (port 8000)
- **AI:** FunieGAN (PyTorch, CPU-only)
- **Storage:** MongoDB (metadata) + MinIO (S3-compatible object storage)
- **Auth:** Google OAuth with PKCE (code_verifier in httponly cookie)
- **Deployment:** ArgoCD (GitOps), Helm charts, Kubernetes
- **Secrets:** HashiCorp Vault + External Secrets Operator
- **Monitoring:** Prometheus + Grafana + Grafana Operator
- **Ingress:** Cloudflare Tunnel (no traditional ingress controller)

---

## 1. Local Development

Development is done in the `namiview` repo using `./dev.sh`.

```bash
cd ~/namiview
./dev.sh
```

This starts:
- **FastAPI backend** on port 8000
- **React/Vite dev server** on port 8501 (matches old Streamlit port for Google OAuth)
- MongoDB + MinIO via Docker Compose

**Key rules:**
- NEVER modify `requirements.txt` manually -- use `scripts/install-api-deps.sh`
- User's venv is at `venv/` (not `.venv/`)
- Use `./venv/bin/python3 -m pip` (pip not on PATH)
- nginx in UI container is for static files ONLY -- K8s handles API routing

---

## 2. Kubernetes Architecture

Deployment is managed by **ArgoCD** using the App-of-Apps pattern. ArgoCD syncs from Git with auto-sync, prune, and self-heal enabled.

### Repositories in the deployment flow

```
namiview (source) --> GitHub Actions --> Docker Hub (darbuki/namiview-api, darbuki/namiview-ui)
                                              |
namiview-charts (Helm) <-- image tags updated in values-dev.yaml / values-prod.yaml
        |
namiviewk8s (ArgoCD apps) --> references namiview-charts --> deploys to K8s
```

### Namespaces

| Namespace          | Contents |
|--------------------|----------|
| `namiview-app`     | Production API + UI |
| `namiview-dev`     | Development API + UI |
| `namiview-infra`   | MongoDB (3-replica RS), MinIO |
| `vault`            | Vault HA cluster (3 replicas, Raft) |
| `monitoring`       | Prometheus, Grafana, AlertManager, Grafana Operator |
| `cloudflare`       | Cloudflare Tunnel (2 replicas) |
| `argocd`           | ArgoCD controller |
| `external-secrets` | External Secrets Operator |
| `kube-system`      | metrics-server |
| `local-path`       | local-path storage provisioner |

### ArgoCD Applications

**App deployments** (in `apps/`):

| Application         | Namespace     | Chart               | Branch |
|---------------------|---------------|---------------------|--------|
| `namiview-prod-api` | namiview-app  | namiview-api (main) | main   |
| `namiview-prod-ui`  | namiview-app  | namiview-ui (main)  | main   |
| `namiview-dev-api`  | namiview-dev  | namiview-api (dev)  | dev    |
| `namiview-dev-ui`   | namiview-dev  | namiview-ui (dev)   | dev    |

**Infrastructure** (in `infrastructure/`):

| Application          | Namespace        | Purpose |
|----------------------|------------------|---------|
| `vault-stack`        | vault            | Vault HA (Raft, 3 replicas) |
| `mongodb-stack`      | namiview-infra   | MongoDB replica set (Bitnami, 3 replicas) |
| `minio-stack`        | namiview-infra   | MinIO object storage (10Gi) |
| `monitoring-stack`   | monitoring       | kube-prometheus-stack (Prometheus + Grafana) |
| `grafana-operator`   | monitoring       | Manages Grafana dashboards via CRDs |
| `cloudflare-stack`   | cloudflare       | Cloudflare tunnel for namiview.com ingress |
| `external-secrets`   | external-secrets | ESO v1.3.1 (Vault backend) |
| `argocd-config`      | argocd           | ArgoCD TLS and configuration |
| `metrics-server`     | kube-system      | K8s resource metrics |
| `storage-provisioner`| local-path       | local-path-provisioner |

### Secrets management

All secrets are stored in Vault and synced to K8s via External Secrets Operator:
- **ClusterSecretStore:** `vault-cluster-gateway` (Kubernetes auth, mount: `kubernetes`, role: `eso-role`)
- **Vault paths:** `namiview/infra/mongodb/root`, `namiview/infra/minio/root`, `namiview/app/google-oauth`, `namiview/infra/monitoring/grafana`

### Connectivity in cluster

- MongoDB: `mongo-mongodb-0.mongo-mongodb-headless.namiview-infra.svc.cluster.local:27017` (replica set)
- MinIO: `minio.namiview-infra.svc.cluster.local:9000`
- Vault: `http://vault.vault.svc.cluster.local:8200`

---

## 3. Monitoring Stack

### Prometheus
- Helm chart: kube-prometheus-stack v81.5.0
- Retention: 5 days, 5Gi storage
- ServiceMonitors (30s interval) for: Vault, MongoDB, MinIO, ArgoCD, Cloudflare, Namiview API

### Grafana
- URL: `https://grafana.namiview.com`
- Persistence: 2Gi
- Dashboards managed by Grafana Operator (CRDs in `grafana-operator/dashboards/`)
- Dashboards: namiview-api, vault, mongodb, minio, argocd, cloudflare

### Vault telemetry (v1.21.x)
- **Top-level `telemetry` stanza** (in `server.ha.raft.config`): enables the Prometheus sink
  - `prometheus_retention_time = "1h"`
  - `disable_hostname = true`
- **Listener-level `telemetry` stanza** (inside `listener "tcp"`): controls auth
  - `unauthenticated_metrics_access = true`
- Both stanzas are required. The listener `telemetry` block only accepts `unauthenticated_metrics_access`.
- Metrics endpoint: `/v1/sys/metrics?format=prometheus`

---

## 4. How the App Works

### Backend (FastAPI)
- Entry: `main.py`
- API routes in `api/`
- Services in `services/`
- Schemas in `schemas/`
- Port 8000, health check: `/api/health`

### Frontend (React + Vite + Tailwind)
- Source in `ui/`
- Built and served by nginx on port 80
- Health check: `/healthz`

### Processing pipeline
- **AI modes:** FunieGAN with postprocessing: Natural (Low AI), Balanced (Standard), Vivid (High AI)
- **Physics modes:** Red channel recovery, dehaze (DCP), CLAHE: Physics (Light), Physics (Pro)

### Authentication
- Google OAuth with PKCE flow
- `code_verifier` stored in httponly cookie
- Session cookie middleware for gallery persistence

---

## 5. Helm Charts (namiview-charts)

### namiview-api
- Image: `darbuki/namiview-api`
- Port 8000, Prometheus metrics on port 9090
- Probes: startup (30 tries x 10s), readiness (5s), liveness (30s)
- Resources: 250m-1000m CPU, 256Mi-2Gi RAM
- PodDisruptionBudget: minAvailable 1
- Prod: 2 replicas, Dev: 1 replica

### namiview-ui
- Image: `darbuki/namiview-ui`
- Port 80 (nginx)
- Prod: 2 replicas, Dev: 1 replica

### Deployment flow
1. Push code to `namiview` repo
2. GitHub Actions builds Docker images, pushes to Docker Hub
3. Update image tags in `namiview-charts` (values-dev.yaml or values-prod.yaml)
4. ArgoCD auto-syncs from the charts repo

---

## 6. Key File Locations (namiviewk8s)

| Path | Purpose |
|------|---------|
| `apps/namiview-*.yaml` | ArgoCD Application definitions (4 files) |
| `bootstrap/` | ArgoCD bootstrap (apps-root, infrastructure-root) |
| `infrastructure/vault/values.yaml` | Vault Helm values (HA + telemetry config) |
| `infrastructure/vault/cluster-store.yaml` | ClusterSecretStore for ESO |
| `infrastructure/monitoring/values.yaml` | Prometheus + Grafana config |
| `infrastructure/monitoring/service-monitors/` | ServiceMonitor definitions |
| `infrastructure/grafana-operator/dashboards/` | Grafana dashboard CRDs |
| `infrastructure/mongodb/values.yaml` | MongoDB Helm values |
| `infrastructure/minio/values.yaml` | MinIO Helm values |
| `infrastructure/cloudflare/tunnel.yaml` | Cloudflare tunnel deployment |

---

## Quick Reference

| Task | Action |
|------|--------|
| Run locally | `cd ~/namiview && ./dev.sh` |
| Check ArgoCD apps | `argocd app list` |
| Vault status | `kubectl -n vault exec vault-0 -- vault status` |
| Prometheus targets | Port-forward Prometheus, check Status > Targets |
| Deploy new image | Update image tag in namiview-charts, push, ArgoCD syncs |
| GitHub work | Always use MCP tools (`mcp__github-projects__*`), not gh CLI |

---

## 7. EKS deployment (parallel to kubeadm above)

The EKS cluster is `namiview-prod` in `eu-west-1`, built on a refactored repo layout. Production and baseline dev should track `main`; use temporary feature branches only for isolated dev work.

### Repo split — env values moved out of `namiview-charts`

| Thing | Kubeadm (above) | EKS |
|---|---|---|
| Chart structure | `namiview-charts/charts/<app>/templates` | same |
| Env values | **inside** `namiview-charts/charts/<app>/values-{dev,prod}.yaml` (regretted) | **outside**, in `namiviewk8s/apps-eks/<app>/values.yaml` |
| Deploy = bumping image tag in… | `namiview-charts` | `namiviewk8s` |

Two-source Argo pattern: chart from `namiview-charts`, values from `namiviewk8s/apps-eks/<app>/`.

### Starting EKS dev work on a branch

When the user says "start developing dev on branch X" or similar, set only the **dev** GitOps surface to branch `X`:

1. In `namiview-terraform/envs/prod/eu-west-1/platform/terraform.tfvars`, set `argocd_dev_target_revision = "X"`. Do **not** change `argocd_target_revision` or `argocd_infrastructure_target_revision` unless explicitly asked.
2. In `namiview/.github/workflows/build-eks-dev.yml`, set `GITOPS_BRANCH: X` so dev image bumps update `namiviewk8s/apps-eks-dev/*/values.yaml` on the same branch Argo tracks.
3. In `namiviewk8s/apps-eks-dev/*.yaml`, keep chart `targetRevision: main` unless the user is also changing `namiview-charts`; if chart changes are part of the work, point only the relevant dev app chart source at the chart feature branch.
4. Apply the platform Terraform stack so live `apps-root-dev` tracks branch `X`. Prod apps and infrastructure roots should remain on `main`.

To return dev to baseline, reverse the first two changes back to `main` and apply the platform stack again.

### Three install surfaces in `infrastructure-eks/`

1. **Terraform** (`namiview-terraform/envs/prod/eu-west-1/{foundation,platform}/`) — durable platform: VPC, EKS, IAM/IRSA, ArgoCD itself, Karpenter controller, ALB controller, foundation Secrets Manager secrets.
2. **`*-app.yaml`** in `infrastructure-eks/` — Argo Applications installing upstream Helm charts (operators).
3. **`*-resources.yaml`** in `infrastructure-eks/` — Argo Applications applying plain YAML in sibling dirs (cluster-level CRs the operators consume).

### EKS Argo apps (`infrastructure-eks/`)

| Argo App | Chart / Source | What it installs |
|---|---|---|
| `external-secrets` (eso-app.yaml) | charts.external-secrets.io | ESO; resources file holds `ClusterSecretStore` for AWS Secrets Manager |
| `monitoring-stack` (monitoring-app.yaml) | prometheus-community kube-prometheus-stack | Prometheus + Grafana + Alertmanager; `alertmanagerConfigMatcherStrategy: None` patched in so cross-namespace `AlertmanagerConfig` CRDs match cluster-wide |
| `keda` (keda-app.yaml) | kedacore.github.io/charts | KEDA operator + metricServer; both expose `/metrics` to Prometheus via ServiceMonitor |
| `tailscale-operator` (tailscale-app.yaml) | pkgs.tailscale.com/helmcharts | Tailscale operator; reads `operator-oauth` Secret synced by ESO from foundation; the `Connector` CRD in `tailscale/connector.yaml` advertises the VPC CIDR so kubectl works against the private EKS endpoint without flipping public |
| `karpenter-resources.yaml` | (controller via TF) | NodePool + EC2NodeClass |
| `arc-controller` / `arc-runner-set` / `arc-runner-set-terraform` | actions-runner-controller | GH Actions runners in-cluster (the terraform pool is for namiview-terraform CI) |

### EKS workload apps (`apps-eks/`)

`namiview-api` (FastAPI, ServiceMonitor + dashboard), `namiview-ui` (nginx, no metrics yet), `namiview-triage` (the AI agent — webhook receiver for Alertmanager). Both api and ui have KEDA `ScaledObject`s (memory utilization, gated on `autoscaling.enabled`).

### Tailscale VPN access — how the loop closes

EKS API endpoint is private (`endpoint_public_access = false`). The Tailscale operator runs in `tailscale` namespace; the `Connector` CRD spawns a subnet-router pod that advertises `10.0.0.0/16` to the tailnet. Devices appear in Tailscale admin as `namiview-operator` (the operator's identity) and `namiview-vpc-router` (the route advertiser). After approving the route once in the admin UI, kubectl from any tailnet member resolves the private endpoint over Tailscale.

### KEDA on the workload apps

`ScaledObject`s live **in the chart** (`namiview-charts/charts/<app>/templates/scaledobject.yaml`), gated by `autoscaling.enabled`. EKS values flip it on. Same pattern as `AlertmanagerConfig` for the triage agent — the operator is infra, but per-app CRs ship with the app.

**Memory scaler is a poor signal for Python.** Python doesn't release memory back to the OS, so idle usage ≈ `requests.memory`, which puts utilization at ~97% against a 70% target — KEDA scales to `maxReplicas` and stays. Fix is either generous `requests.memory` headroom (currently 512Mi for api so idle ~250Mi sits at ~49%) or switch to a Prometheus RPS trigger. The api's `/metrics` endpoint is already scraped, so Prometheus RPS is the right next step.

### Adding a new operator → AppProject whitelist papercut

Every operator that ships a cluster-scoped resource (APIService, IngressClass, custom CRD instances) needs adding to the `namiview` AppProject's `clusterResourceWhitelist` in `namiview-terraform/envs/prod/eu-west-1/platform/argocd-bootstrap.tf`. Symptom: Argo error `<group>:<Kind> is not permitted in project namiview`. Fix is one line + targeted apply:

```bash
terraform apply -target=kubernetes_manifest.argocd_project
```

The current whitelist already covers: namespaces, cluster RBAC, CRDs, webhooks, StorageClasses, Karpenter NodePool/EC2NodeClass, KEDA's APIService, Tailscale's IngressClass + Connector + ProxyClass + DNSConfig.

### Foundation-layer secrets pattern (decoupled from platform layer)

Durable secrets live in `namiview-terraform/envs/prod/eu-west-1/foundation/secrets.tf` with `prevent_destroy = true`. Naming convention: `${cluster_name}/<purpose>`. The platform-layer ESO IAM policy grants `secretsmanager:GetSecretValue` by ARN **name pattern** (e.g., `:secret:namiview-prod/tailscale-operator-oauth-*`), not via `terraform_remote_state` — the contract is the secret name. When adding a foundation secret, also add its ARN pattern to `platform/secrets.tf::aws_iam_role_policy.eso_secrets_access`.

---

*Last updated: Apr 2026 — added EKS section. Pre-EKS kubeadm content above is still valid.*
