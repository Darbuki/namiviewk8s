# CI/CD Pipeline Plan

## Overview
GitHub Actions workflows needed across all repositories to automate the build, test, and deploy cycle for the EKS environment.

---

## 1. namiview (Application Repo)

### Workflow: `build-and-push.yaml`
**Trigger:** Push to `main`, push to feature branches, PR to `main`
**Steps:**
1. Checkout code
2. Set up Docker Buildx
3. Login to DockerHub (credentials from GitHub Secrets)
4. Build Docker image with tag: `<branch>-<short-sha>` (e.g., `prod-11-04-864cb2e`)
5. Push to DockerHub (`darbuki/namiview-api`, `darbuki/namiview-ui`)
6. (Optional) Update image tag in namiviewk8s values via PR or commit

### Secrets needed:
- `DOCKERHUB_USERNAME`
- `DOCKERHUB_TOKEN`

---

## 2. namiview-charts (Helm Charts Repo)

### Workflow: `lint-and-test.yaml`
**Trigger:** PR to `main`
**Steps:**
1. Checkout code
2. Set up Helm
3. `helm lint charts/namiview-ui`
4. `helm lint charts/namiview-api`
5. `helm template` dry-run to catch rendering errors
6. (Optional) Kubeconform / kubeval for schema validation

---

## 3. namiviewk8s (GitOps Repo)

### Workflow: `validate.yaml`
**Trigger:** PR to `main`
**Steps:**
1. Checkout code
2. Validate YAML syntax for all manifests
3. Kubeconform schema validation
4. (Optional) ArgoCD diff preview

### Note:
ArgoCD handles deployment automatically on merge — no deploy workflow needed.

---

## 4. namiview-terraform (Infrastructure Repo)

### Workflow: `terraform-plan.yaml`
**Trigger:** PR to `main`
**Steps:**
1. Checkout code
2. Configure AWS credentials (OIDC with `namiview-terraform-ci` role)
3. `terraform init`
4. `terraform validate`
5. `terraform plan` — post plan output as PR comment
6. (Optional) tflint / tfsec for linting and security scanning

### Workflow: `terraform-apply.yaml`
**Trigger:** Push to `main` (after PR merge)
**Steps:**
1. Checkout code
2. Configure AWS credentials (OIDC)
3. `terraform init`
4. `terraform apply -auto-approve`

### Secrets needed:
- AWS OIDC provider already configured (`namiview-terraform-ci` role exists)

---

## Image Tag Update Strategy

When a new image is built in the namiview repo, the tag in `namiviewk8s/apps-eks/namiview-api/values.yaml` (and namiview-ui) needs to be updated. Options:

1. **Manual** — developer updates the tag in a PR to namiviewk8s
2. **Automated PR** — namiview build workflow opens a PR to namiviewk8s updating the image tag
3. **Image Updater** — ArgoCD Image Updater watches DockerHub and auto-updates (no workflow needed)

**Recommendation:** Option 3 (ArgoCD Image Updater) for full GitOps automation.

---

## Priority Order
1. namiview build-and-push (most impactful — currently manual image builds)
2. namiview-terraform plan/apply (safety net for infra changes)
3. namiview-charts lint (catch chart errors before deploy)
4. namiviewk8s validate (nice to have, ArgoCD catches most issues)
