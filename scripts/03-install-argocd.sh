#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Run on MASTER node (where kubectl is configured)
# Installs ArgoCD via Helm
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARGOCD_DIR="${SCRIPT_DIR}/../argocd"

echo "==> Installing Helm (if not present)..."
if ! command -v helm &>/dev/null; then
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

echo "==> Adding ArgoCD Helm repo..."
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

echo "==> Installing ArgoCD..."
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --values "${ARGOCD_DIR}/argocd-values.yaml" \
  --wait --timeout 5m

echo "==> Waiting for ArgoCD server to be ready..."
kubectl wait --for=condition=Available deployment/argocd-server \
  -n argocd --timeout=180s

echo ""
echo "==> Retrieving initial admin password..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

echo ""
echo "============================================================"
echo "  ArgoCD installed successfully!"
echo ""
echo "  Access UI:"
echo "    kubectl port-forward svc/argocd-server -n argocd 8443:443"
echo "    https://localhost:8443"
echo ""
echo "  Or via NodePort:"
echo "    https://<any-node-ip>:30443"
echo ""
echo "  Username: admin"
echo "  Password: ${ARGOCD_PASSWORD}"
echo ""
echo "  Change password:"
echo "    argocd login localhost:8443 --insecure"
echo "    argocd account update-password"
echo "============================================================"
