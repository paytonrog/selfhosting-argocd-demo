# Temporal on AWS EKS (Self-Hosted) — Fail-Safe Runbook

This is the **minimal step-by-step process** to deploy Temporal successfully (without the troubleshooting history).

## Prereqs

- AWS CLI configured with SSO profile: `TemporalSelfHostingAdmin`
- Terraform, kubectl, helm installed
- You are in this repo root

## 1) Authenticate AWS SSO

```bash
aws sso login --profile TemporalSelfHostingAdmin
```

## 2) Deploy with Terraform

```bash
cd terraform-temporal-payton
terraform init
terraform plan -out tfplan
terraform apply -input=false tfplan
```

## 3) If Helm is stuck (`pending-upgrade` / "another operation in progress")

Run this once, then re-run plan/apply:

```bash
helm -n temporal history temporal
helm -n temporal rollback temporal 2 --wait --timeout 10m

terraform plan -out tfplan
terraform apply -input=false tfplan
```

## 4) Configure kubectl for EKS

```bash
aws eks update-kubeconfig \
  --region us-east-2 \
  --name payton-temporal-eks \
  --profile TemporalSelfHostingAdmin
```

## 5) Verify Temporal deployment health

```bash
helm -n temporal status temporal
kubectl -n temporal get pods -o wide
```

Expected: frontend/history/matching/worker/web/admintools all `Running`.

## 6) Verify Temporal API via tctl

```bash
ADMIN_POD=$(kubectl -n temporal get pod -l app.kubernetes.io/component=admintools -o jsonpath='{.items[0].metadata.name}')
kubectl -n temporal exec "$ADMIN_POD" -- tctl --address temporal-frontend:7233 cluster health
kubectl -n temporal exec "$ADMIN_POD" -- tctl --address temporal-frontend:7233 namespace list
```

Expected: `WorkflowService: SERVING`

## 7) Run real workflow smoke test

Use the included script:

```bash
chmod +x test-temporal-workflow.sh
./test-temporal-workflow.sh
```

Expected:
- workflow start succeeds
- workflow describe returns execution details (`Running` or progressing)

## 8) Access Temporal Web UI

```bash
kubectl -n temporal port-forward svc/temporal-web 8080:8080
```

Open: http://localhost:8080

## 9) Fix: `pq: relation "executions_visibility" does not exist`

If the Web UI shows:

- **No Workflows running in this Namespace**
- `ListWorkflowExecutions operation failed: pq: relation "executions_visibility" does not exist`

run the repair script:

```bash
chmod +x repair-temporal-visibility-schema.sh
./repair-temporal-visibility-schema.sh
```

What it does:

- reads DB connection info from Temporal's in-cluster config + secret
- runs Temporal schema setup/update for both:
  - default DB: `temporal`
  - visibility DB: `temporal_visibility`
- verifies `public.executions_visibility` exists
- restarts Temporal server pods

Then re-check:

```bash
# In one terminal
kubectl -n temporal port-forward svc/temporal-web 8080:8080

# In another terminal (optional backend check)
ADMIN_POD=$(kubectl -n temporal get pod -l app.kubernetes.io/component=admintools -o jsonpath='{.items[0].metadata.name}')
kubectl -n temporal exec "$ADMIN_POD" -- tctl --address temporal-frontend:7233 namespace list
```

Refresh http://localhost:8080 and verify workflow queries no longer fail.

## 10) Access Argo CD (internal-only)

Argo CD is installed by Terraform into namespace `argocd` with a ClusterIP service.

Port-forward the Argo CD API/UI service:

```bash
kubectl -n argocd port-forward svc/argocd-server 8081:443
```

Open:

```text
https://localhost:8081
```

Your browser may show a certificate warning because this is local port-forward over HTTPS.

Get the initial `admin` password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 --decode; echo
```

Login with:

- Username: `admin`
- Password: (output from command above)

---

## Required configuration already baked into `main.tf`

This repo is already set to the working values:

- Node type: `c6i.large`
- RDS PostgreSQL Multi-AZ
- RDS Proxy enabled
- RDS Proxy TLS required: `require_tls = true`
- Temporal SQL datastore driver: `postgres12`
- Dedicated visibility DB: `temporal_visibility` (separate from default `temporal` DB)
- Temporal SQL TLS enabled (default + visibility):
  - `tls.enabled = true`
  - `tls.serverName = <rds proxy endpoint>`
  - `tls.enableHostVerification = true`
- Prometheus/Grafana disabled for clean bootstrap in this environment
