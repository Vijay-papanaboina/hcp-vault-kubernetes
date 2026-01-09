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
echo "[1/3] Uninstalling Helm Charts (Vault, VSO, CNPG)..."
# Vault
helm uninstall vault -n vault 2>/dev/null || true
# VSO
helm uninstall vault-secrets-operator -n vault-secrets-operator-system 2>/dev/null || true
# CloudNativePG
helm uninstall cnpg-operator -n cnpg-system 2>/dev/null || true

echo ""
echo "[2/3] Deleting Namespaces..."
# This deletes all resources within them (Deployments, Secrets, PVCs, Jobs, ConfigMaps)
kubectl delete ns vault database apps vault-secrets-operator-system cnpg-system --ignore-not-found=true --wait=true

echo ""
echo "[3/3] Deleting Persistent Volumes (PVs)..."
# PVs are cluster-level, so they must be deleted separately to free up storage
kubectl delete pv --all --ignore-not-found=true

echo ""
echo "=========================================="
echo "Cleanup Complete!"
echo "=========================================="

read -p "Do you want to stop Minikube? (y/n): " STOP_MINIKUBE
if [[ "$STOP_MINIKUBE" == "y" || "$STOP_MINIKUBE" == "Y" ]]; then
    minikube stop
fi
