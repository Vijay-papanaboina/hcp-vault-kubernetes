#!/bin/bash
set -e

echo "=========================================="
echo "HCP Vault with Kubernetes - Setup Script"
echo "=========================================="
echo ""

# Check if using minikube
read -p "Are you using Minikube? (y/n): " USE_MINIKUBE

if [[ "$USE_MINIKUBE" == "y" || "$USE_MINIKUBE" == "Y" ]]; then
    echo ""
    echo "[1/7] Starting Minikube..."
    minikube start --memory=4096 --cpus=2
else
    echo ""
    echo "[1/7] Skipping Minikube (using existing cluster)..."
    echo "Current context: $(kubectl config current-context)"
fi

echo ""
echo "[2/7] Creating namespaces..."
kubectl apply -f kubernetes/00-namespaces.yaml

echo ""
echo "[3/7] Installing CloudNativePG Operator..."
kubectl apply -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.22/releases/cnpg-1.22.0.yaml
echo "Waiting for CloudNativePG operator..."
kubectl wait --for=condition=Available deployment/cnpg-controller-manager -n cnpg-system --timeout=120s

echo ""
echo "[4/7] Deploying PostgreSQL cluster..."
kubectl apply -f kubernetes/database/postgres-secrets.yaml
kubectl apply -f kubernetes/database/postgres-cluster.yaml
echo "Waiting for PostgreSQL cluster (this may take 1-2 minutes)..."
kubectl wait --for=condition=Ready cluster/postgres-cluster -n database --timeout=300s

echo ""
echo "[5/7] Installing Vault and VSO..."
helm repo add hashicorp https://helm.releases.hashicorp.com 2>/dev/null || true
helm repo update

helm install vault hashicorp/vault \
    -n vault \
    -f kubernetes/vault/vault-values-dev.yaml

kubectl apply -f kubernetes/vault/vault-rbac.yaml

echo "Waiting for Vault..."
kubectl wait --for=condition=Ready pod/vault-0 -n vault --timeout=120s

helm install vault-secrets-operator hashicorp/vault-secrets-operator \
    -n vault-secrets-operator-system \
    --create-namespace

echo "Waiting for VSO..."
sleep 10
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=vault-secrets-operator -n vault-secrets-operator-system --timeout=120s

echo ""
echo "[6/7] Configuring Vault (via Job)..."
kubectl apply -f kubernetes/vault/vault-config-cm.yaml
kubectl apply -f kubernetes/vault/vault-config-job.yaml
echo "Waiting for Vault configuration to complete..."
kubectl wait --for=condition=complete job/vault-config -n vault --timeout=120s
echo ""
echo "Vault config job logs:"
kubectl logs job/vault-config -n vault

echo ""
echo "[7/7] Deploying VSO resources and demo app..."
kubectl apply -f kubernetes/apps/

echo ""
echo "Waiting for secrets to sync (30 seconds)..."
sleep 30

echo ""
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "Checking resources:"
echo ""
echo "PostgreSQL Cluster:"
kubectl get cluster -n database
echo ""
echo "Vault:"
kubectl get pods -n vault
echo ""
echo "VSO:"
kubectl get pods -n vault-secrets-operator-system
echo ""
echo "Secrets in apps namespace:"
kubectl get secrets -n apps
echo ""
echo "VSO Resources:"
kubectl get vaultstaticsecret,vaultdynamicsecret -n apps
echo ""
echo "=========================================="
echo "To view demo app logs:"
echo "  kubectl logs -f deployment/myapp -n apps"
echo ""
echo "To access Vault UI:"
echo "  kubectl port-forward svc/vault -n vault 8200:8200"
echo "  Open: http://localhost:8200 (Token: root)"
echo "=========================================="
