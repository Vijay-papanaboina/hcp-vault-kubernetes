#!/bin/sh
set -e

echo "Waiting for Vault to be ready..."
until vault status 2>/dev/null; do
    echo "Vault not ready, waiting..."
    sleep 2
done

echo ""
echo "=========================================="
echo "Starting Vault Configuration"
echo "=========================================="

# 1. Enable KV-v2 secrets engine (may already exist in dev mode)
echo ""
echo "[1/7] Enabling KV-v2 secrets engine..."
vault secrets enable -path=secret kv-v2 2>/dev/null || echo "  -> Already enabled"

# 2. Store static secrets (API keys)
echo ""
echo "[2/7] Storing static secrets..."
vault kv put secret/apps/myapp \
    stripe_api_key="sk_test_abc123xyz" \
    sendgrid_api_key="SG.test_key_789" \
    jwt_secret="super-secret-jwt-signing-key-2024"
echo "  -> Stored: stripe_api_key, sendgrid_api_key, jwt_secret"

# 3. Enable Kubernetes auth
echo ""
echo "[3/7] Enabling Kubernetes auth..."
vault auth enable kubernetes 2>/dev/null || echo "  -> Already enabled"

# 4. Configure Kubernetes auth
echo ""
echo "[4/7] Configuring Kubernetes auth..."
# Read Kubernetes CA cert and token from mounted service account
KUBE_CA_CERT=$(cat /var/run/secrets/kubernetes.io/serviceaccount/ca.crt)
KUBE_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)

vault write auth/kubernetes/config \
    kubernetes_host="https://kubernetes.default.svc:443" \
    disable_local_ca_jwt="false" \
    disable_iss_validation="true"

# 5. Create policy for app
echo ""
echo "[5/7] Creating myapp-policy..."
vault policy write myapp-policy - <<EOF
# Read static secrets
path "secret/data/apps/myapp" {
    capabilities = ["read"]
}

# Read dynamic database credentials
path "database/creds/myapp-role" {
    capabilities = ["read"]
}
EOF

# 6. Create role linking K8s service account to policy
echo ""
echo "[6/7] Creating Kubernetes auth role..."
vault write auth/kubernetes/role/myapp-role \
    bound_service_account_names=myapp-sa \
    bound_service_account_namespaces=apps \
    policies=myapp-policy \
    audience="vault" \
    ttl=1h

# 7. Enable and configure database secrets engine
echo ""
echo "[7/7] Configuring database secrets engine..."
vault secrets enable database 2>/dev/null || echo "  -> Already enabled"

vault write database/config/myapp-postgres \
    plugin_name=postgresql-database-plugin \
    allowed_roles="myapp-role" \
    connection_url="postgresql://{{username}}:{{password}}@postgres-cluster-rw.database.svc.cluster.local:5432/myapp?sslmode=disable" \
    username="postgres" \
    password="postgres-admin-password"

vault write database/roles/myapp-role \
    db_name=myapp-postgres \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
    revocation_statements="REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM \"{{name}}\"; DROP ROLE IF EXISTS \"{{name}}\";" \
    default_ttl="1h" \
    max_ttl="24h"

echo ""
echo "=========================================="
echo "Vault Configuration Complete!"
echo "=========================================="
echo ""
echo "Static secrets:  secret/apps/myapp"
echo "Dynamic creds:   database/creds/myapp-role"
echo "K8s auth role:   myapp-role"
echo "Policy:          myapp-policy"
echo ""