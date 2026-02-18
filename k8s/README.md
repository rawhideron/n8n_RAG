# n8n RAG Platform — Kubernetes Deployment

Converts the Docker Compose setup into a Kubernetes deployment for
**rawhideron.duckdns.org**, with Let's Encrypt TLS, Keycloak SSO, and
`oauth2-proxy` protecting the n8n UI.

---

## Architecture

```
Internet
   │  HTTPS
   ▼
nginx-ingress  (rawhideron.duckdns.org)
   ├── /auth/*        ──► Keycloak          (OIDC provider, self-registration)
   ├── /oauth2/*      ──► oauth2-proxy      (auth callback, login flow)
   └── /n8n/*         ──► n8n               (protected — Keycloak login required)
                              │
                    ┌─────────┼──────────┐
                    ▼         ▼          ▼
                PostgreSQL  Qdrant    Ollama (CPU)
```

### Namespace

All resources live in the **`google-rag`** namespace.

> **Note:** Kubernetes namespace names must follow RFC 1123 — no underscores.
> `google_rag` becomes `google-rag`.

### Auth flow

1. User visits `https://rawhideron.duckdns.org/n8n/`
2. nginx checks authentication via oauth2-proxy (`/oauth2/auth`)
3. If not authenticated → redirect to Keycloak login page (`/auth/`)
4. User registers (self-registration is enabled) or logs in
5. Keycloak issues OIDC token → oauth2-proxy sets a session cookie
6. nginx forwards the request to n8n
7. **Within n8n**, the owner/admin controls what the user can do:
   - New users get a `n8n-viewer` Keycloak role automatically
   - Admin shares the *Local RAG AI Agent* workflow as **Read-only**
   - Admin promotes users to execute workflows in the n8n UI

---

## Prerequisites

| Requirement | Details |
|---|---|
| Kubernetes ≥ 1.25 | Any CNCF-conformant cluster (k3s, RKE2, GKE, EKS, AKS…) |
| kubectl | Installed and configured for your cluster |
| **nginx-ingress-controller** | `helm install ingress-nginx ingress-nginx/ingress-nginx` |
| **cert-manager** | `helm install cert-manager jetstack/cert-manager --set installCRDs=true` |
| Ports 80 & 443 | Reachable from the internet for Let's Encrypt HTTP-01 |
| DuckDNS configured | `rawhideron.duckdns.org` → cluster LoadBalancer IP |

### Install dependencies (if not already installed)

```bash
# nginx-ingress
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace

# cert-manager
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set installCRDs=true
```

---

## Deployment Steps

### 1. Clone & enter the project root

```bash
cd /path/to/n8n_RAG    # Run all kubectl commands from the project root
```

> **Important:** `kustomization.yaml` is at the **project root**, not inside
> `k8s/`. This allows kustomize to read the `n8n/demo-data/` workflow and
> credential files from the same directory tree.

### 2. Set your Let's Encrypt email

Edit [k8s/cert-manager/cluster-issuer.yaml](k8s/cert-manager/cluster-issuer.yaml)
and replace `your-email@example.com` with your real email address.

### 3. Configure secrets

```bash
# From the project root
cp .env.secrets.example .env.secrets
```

Open `.env.secrets` and fill in real values:

| Key | Description |
|---|---|
| `POSTGRES_USER` | PostgreSQL superuser (e.g. `root`) |
| `POSTGRES_PASSWORD` | Strong password for PostgreSQL |
| `POSTGRES_DB` | n8n database name (e.g. `n8n`) |
| `N8N_ENCRYPTION_KEY` | 64-char hex — `openssl rand -hex 32` |
| `N8N_USER_MANAGEMENT_JWT_SECRET` | 64-char hex — `openssl rand -hex 32` |
| `KEYCLOAK_ADMIN` | Keycloak admin username |
| `KEYCLOAK_ADMIN_PASSWORD` | Strong password for Keycloak admin |
| `OAUTH2_PROXY_CLIENT_SECRET` | **Must match** `secret` in [keycloak/realm-configmap.yaml](keycloak/realm-configmap.yaml) |
| `OAUTH2_PROXY_COOKIE_SECRET` | 32-byte base64 — `openssl rand -base64 32 \| tr -d '\n'` |

### 4. Set the oauth2-proxy client secret in Keycloak realm

The Keycloak realm JSON embeds a client secret placeholder.
Open [keycloak/realm-configmap.yaml](keycloak/realm-configmap.yaml) and
change every occurrence of `CHANGE_ME_OAUTH2_PROXY_SECRET` to the same
value you put in `OAUTH2_PROXY_CLIENT_SECRET` in `.env.secrets`.

```bash
# Example: generate a secret first, then replace in both places
SECRET=$(openssl rand -hex 20)
echo "OAUTH2_PROXY_CLIENT_SECRET=$SECRET" >> .env.secrets
sed -i "s/CHANGE_ME_OAUTH2_PROXY_SECRET/$SECRET/" k8s/keycloak/realm-configmap.yaml
```

### 5. Deploy the ClusterIssuer (cluster-scoped, run once)

```bash
kubectl apply -f k8s/cert-manager/cluster-issuer.yaml
```

### 6. Deploy everything with kustomize (run from project root)

```bash
kubectl apply -k .
```

Kustomize will:
- Create the `google-rag` namespace
- Generate Secrets from `.env.secrets`
- Generate ConfigMaps from workflow/credential JSON files
- Deploy all services in the correct order

### 7. Wait for the PostgreSQL init Job

The `postgres-init` Job creates the `keycloak` database.
Keycloak will not start until this completes.

```bash
kubectl -n google-rag wait --for=condition=complete job/postgres-init --timeout=120s
```

### 8. Wait for Keycloak

```bash
kubectl -n google-rag rollout status deployment/keycloak --timeout=300s
```

### 9. Pull Ollama models (long download — ~2.5 GB)

```bash
kubectl -n google-rag wait --for=condition=complete job/ollama-model-init --timeout=1800s
```

### 10. Run the n8n demo-data import

```bash
kubectl -n google-rag wait --for=condition=complete job/n8n-import --timeout=120s
```

### 11. Verify

```bash
kubectl -n google-rag get pods
kubectl -n google-rag get ingress
kubectl -n google-rag get certificate
```

All pods should be `Running`, certificate should be `Ready: True`.

---

## Post-deployment: Configure n8n Permissions

Once all services are running:

### First n8n login

1. Go to `https://rawhideron.duckdns.org/n8n/`
2. Keycloak redirects you to login — click **Register** if you don't have an account
3. After registration, you are redirected back to n8n
4. n8n will ask you to create an **owner** account (first-time setup)
5. This becomes the n8n admin

### Share the Local RAG AI Agent workflow (view-only)

1. Log into n8n as the owner
2. Open the **Local RAG AI Agent** workflow
3. Click **⋯ (menu)** → **Share**
4. Set access to **All members — Viewer** (read-only)
5. Save

New users who register via Keycloak can now view but not execute the workflow.

### Authorize users to execute workflows

1. In n8n admin panel: **Settings** → **Users**
2. Find the user, click **Edit**
3. Change their role to **Member** (or **Admin**)
4. In Keycloak admin (`/auth/admin`): optionally add them to the `n8n-executors` group

---

## Keycloak Roles

| Role | Who has it | Access |
|---|---|---|
| `n8n-viewer` | All new registrants (default) | Can log into n8n if admin shares workflows |
| `n8n-executor` | Members of `n8n-executors` group | Signals authorization; n8n admin must also grant execution |

The roles are informational and used for group-based access control.
Actual workflow execution is controlled by n8n's own permission system.

---

## Useful Commands

```bash
# Check all resources
kubectl -n google-rag get all

# View n8n logs
kubectl -n google-rag logs -l app=n8n -f

# View Keycloak logs
kubectl -n google-rag logs -l app=keycloak -f

# View oauth2-proxy logs
kubectl -n google-rag logs -l app=oauth2-proxy -f

# Restart n8n
kubectl -n google-rag rollout restart deployment/n8n

# Re-run the n8n import job (if needed — run from project root)
kubectl -n google-rag delete job n8n-import
kubectl -n google-rag apply -f k8s/n8n/import-job.yaml

# Check TLS certificate status
kubectl -n google-rag describe certificate n8n-rag-tls

# Check cert-manager logs
kubectl -n cert-manager logs -l app=cert-manager -f
```

---

## Storage

| PVC | Size | Used by |
|---|---|---|
| `postgres-storage` | 10 Gi | PostgreSQL data |
| `n8n-storage` | 5 Gi | n8n config, credentials |
| `n8n-shared` | 10 Gi | Files shared with n8n workflows |
| `qdrant-storage` | 20 Gi | Vector embeddings |
| `ollama-storage` | 30 Gi | LLM model weights |

Adjust sizes in the respective `pvc.yaml` files before first deployment.
Set `storageClassName` if your cluster requires a specific class.

---

## GPU Support for Ollama

To use a GPU node, uncomment the GPU sections in
[ollama/deployment.yaml](ollama/deployment.yaml):

```yaml
resources:
  limits:
    nvidia.com/gpu: "1"
```

And install the NVIDIA device plugin in your cluster.

---

## Troubleshooting

### Certificate not issued
- Confirm ports 80/443 are open from the internet
- Check: `kubectl describe challenge -n google-rag`
- Verify DuckDNS points to the correct LoadBalancer IP

### Keycloak won't start
- Check the `postgres-init` Job completed: `kubectl -n google-rag get jobs`
- Check Keycloak logs: `kubectl -n google-rag logs -l app=keycloak`

### oauth2-proxy login loop
- Ensure the `OAUTH2_PROXY_CLIENT_SECRET` in `.env.secrets` matches
  the `secret` field in `keycloak/realm-configmap.yaml`
- Ensure the redirect URI in Keycloak matches exactly:
  `https://rawhideron.duckdns.org/oauth2/callback`

### n8n shows blank page / 404
- Confirm `N8N_PATH=/n8n/` and `WEBHOOK_URL` are set correctly in
  [n8n/configmap.yaml](n8n/configmap.yaml)
- Check that the ingress `/n8n` path routes to the n8n service

### Models not available in workflows
- Check the Ollama model init Job: `kubectl -n google-rag logs job/ollama-model-init`
- Re-run: `kubectl -n google-rag delete job ollama-model-init && kubectl apply -f ollama/model-init-job.yaml`
