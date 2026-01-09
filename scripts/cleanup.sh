#!/bin/bash
set -e

echo "=========================================="
echo "HCP Vault with Kubernetes - Cleanup Script"
echo "=========================================="
echo ""

read -p "Are you sure you want to delete all resources? (y/n): " CONFIRM

if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "[1/6] Deleting app resources..."
kubectl delete -f kubernetes/apps/ --ignore-not-found=true

echo ""
echo "[2/6] Deleting Vault config job..."
kubectl delete -f kubernetes/vault/vault-config-job.yaml --ignore-not-found=true
kubectl delete -f kubernetes/vault/vault-config-cm.yaml --ignore-not-found=true

echo ""
echo "[3/6] Uninstalling Vault Secrets Operator..."
helm uninstall vault-secrets-operator -n vault-secrets-operator-system 2>/dev/null || true

echo ""
echo "[4/6] Uninstalling Vault..."
kubectl delete -f kubernetes/vault/vault-rbac.yaml --ignore-not-found=true
helm uninstall vault -n vault 2>/dev/null || true

echo ""
echo "[5/6] Deleting PostgreSQL cluster..."
kubectl delete -f kubernetes/database/postgres-cluster.yaml --ignore-not-found=true
kubectl delete -f kubernetes/database/postgres-secrets.yaml --ignore-not-found=true

echo ""
echo "[6/6] Deleting CloudNativePG Operator..."
kubectl delete -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.22/releases/cnpg-1.22.0.yaml --ignore-not-found=true

echo ""
echo "Deleting namespaces..."
kubectl delete -f kubernetes/00-namespaces.yaml --ignore-not-found=true

echo ""
echo "=========================================="
echo "Cleanup Complete!"
echo "=========================================="

read -p "Do you want to stop Minikube? (y/n): " STOP_MINIKUBE
if [[ "$STOP_MINIKUBE" == "y" || "$STOP_MINIKUBE" == "Y" ]]; then
    minikube stop
fi
