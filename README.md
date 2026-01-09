# HCP Vault with Kubernetes - Quick Start

## Prerequisites

- Minikube or kind installed
- kubectl installed
- Helm 3.x installed

## Step-by-Step Execution

### Phase 1: Infrastructure

```bash
# Start cluster
minikube start --memory=4096 --cpus=2

# Create namespaces
kubectl apply -f kubernetes/00-namespaces.yaml

# Install CloudNativePG Operator (production-grade PostgreSQL)
kubectl apply -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.22/releases/cnpg-1.22.0.yaml

# Wait for operator to be ready
kubectl wait --for=condition=Available deployment/cnpg-controller-manager -n cnpg-system --timeout=120s

# Deploy PostgreSQL cluster (1 primary + 2 replicas)
kubectl apply -f kubernetes/database/postgres-secrets.yaml
kubectl apply -f kubernetes/database/postgres-cluster.yaml

# Wait for PostgreSQL cluster to be ready (takes 1-2 minutes)
kubectl wait --for=condition=Ready cluster/postgres-cluster -n database --timeout=300s
```

### Phase 2: Install Vault & VSO

```bash
# Add Helm repo
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# Install Vault in dev mode
helm install vault hashicorp/vault \
    -n vault \
    -f kubernetes/vault/vault-values-dev.yaml

# Apply RBAC for TokenReview access
kubectl apply -f kubernetes/vault/vault-rbac.yaml

# Wait for Vault
kubectl wait --for=condition=Ready pod/vault-0 -n vault --timeout=120s

# Install Vault Secrets Operator
helm install vault-secrets-operator hashicorp/vault-secrets-operator \
    -n vault-secrets-operator-system \
    --create-namespace
```

## 🚀 Quick Start (Interactive)

The new `deploy.sh` script handles everything. Run it and follow the prompts:

```bash
bash ./scripts/deploy.sh
```

### Vault Deployment Modes:

1.  **Dev Mode**: Starts unsealed automatically. Great for quick testing.
2.  **AWS KMS**: Production simulation using AWS KMS for auto-unseal (Phase 7).
3.  **Manual**: Production simulation. Vault starts **Sealed**. You must open it manually.

---

## 🔐 Manual Unseal Instructions (Option 3)

If you chose **Manual Mode**, follow these steps once the script pauses:

### 1. Initialize Vault

This generates your master keys and root token. **You only do this once.**

```bash
kubectl exec -ti vault-0 -n vault -- vault operator init
```

> [!IMPORTANT]
> Save the **5 Unseal Keys** and the **Initial Root Token** to a secure file. You will lose access to your data if you lose these.

### 2. Unseal the Vault

Vault needs a "quorum" (3 out of 5 keys) to open. Run this command **3 times**:

```bash
kubectl exec -ti vault-0 -n vault -- vault operator unseal
```

Paste a different **Unseal Key** each time when prompted.

### 3. Verify Status

```bash
kubectl exec -ti vault-0 -n vault -- vault status
```

Check that `Sealed` is `false` and `Initialized` is `true`.

### 4. Login (Optional)

```bash
kubectl exec -ti vault-0 -n vault -- vault login
```

Use your **Initial Root Token**.

### 5. Configure Vault (Dynamic Secrets & Auth)

Once the status is `Sealed: false`, you must configure the engines.

Because Vault CLI in WSL inherits exported variables, run these in your terminal:

```bash
# 1. Set your connection details
export VAULT_ADDR="http://<YOUR_NODE_IP>:32213"
export VAULT_TOKEN="hvs.<YOUR_ROOT_TOKEN>"

# 2. Run the configuration script
bash ./scripts/configure-vault.sh
```

> [!TIP]
> This "Inheritance" method keeps your token out of the script file itself, preventing accidental commits to Git!

---

## 🧹 Cleanup

To remove everything (including Persistent Volumes):

```bash
bash ./scripts/cleanup.sh
```

kubectl get secret myapp-api-keys -n apps -o jsonpath='{.data.stripe_api_key}' | base64 -d && echo

# Check dynamic secret content

kubectl get secret myapp-db-credentials -n apps -o jsonpath='{.data.username}' | base64 -d && echo

# Watch demo app logs

kubectl logs -f deployment/myapp -n apps

````

## Phase 7: AWS KMS (Optional)

See `kubernetes/vault/vault-values-aws.yaml` for AWS KMS configuration.

## CloudNativePG Services

The operator creates these services automatically:

| Service               | Purpose                                   |
| --------------------- | ----------------------------------------- |
| `postgres-cluster-rw` | Read-Write (connects to primary)          |
| `postgres-cluster-ro` | Read-Only (load balanced across replicas) |
| `postgres-cluster-r`  | Read (any instance)                       |

## Cleanup

```bash
helm uninstall vault-secrets-operator -n vault-secrets-operator-system
helm uninstall vault -n vault
kubectl delete -f kubernetes/apps/
kubectl delete -f kubernetes/database/
kubectl delete -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.22/releases/cnpg-1.22.0.yaml
kubectl delete -f kubernetes/00-namespaces.yaml
````
