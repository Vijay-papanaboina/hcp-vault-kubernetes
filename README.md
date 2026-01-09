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

### Phase 3-4: Configure Vault (Automated via Job)

```bash
# Apply config script and job
kubectl apply -f kubernetes/vault/vault-config-cm.yaml
kubectl apply -f kubernetes/vault/vault-config-job.yaml

# Wait for configuration to complete
kubectl wait --for=condition=complete job/vault-config -n vault --timeout=120s

# Check job logs
kubectl logs job/vault-config -n vault
```

### Phase 5: Deploy VSO Resources & App

```bash
# Deploy all app resources
kubectl apply -f kubernetes/apps/

# Wait for secrets to sync (may take 30-60 seconds)
sleep 30

# Check secrets were created
kubectl get secrets -n apps
```

### Phase 6: Verify

```bash
# Check PostgreSQL cluster status (should show 3 instances)
kubectl get cluster -n database
kubectl get pods -n database

# Check static secret content
kubectl get secret myapp-api-keys -n apps -o jsonpath='{.data.stripe_api_key}' | base64 -d && echo

# Check dynamic secret content
kubectl get secret myapp-db-credentials -n apps -o jsonpath='{.data.username}' | base64 -d && echo

# Watch demo app logs
kubectl logs -f deployment/myapp -n apps
```

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
```
