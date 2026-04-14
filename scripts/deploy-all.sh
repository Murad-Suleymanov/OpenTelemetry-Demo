#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# OpenTelemetry Demo - Full Deployment Script
# Run on CONTROL-PLANE node (ubuntu-4gb-nbg1-1)
#
# Cluster: 1 master + 2 workers, 4GB RAM each, K8s v1.30.14
# Installs: Helm, ArgoCD, NGINX Gateway Fabric, OTel Demo
###############################################################################

REPO_URL="https://github.com/Murad-Suleymanov/OpenTelemetry-Demo.git"
REPO_DIR="/tmp/otel-demo-repo"

echo "=========================================="
echo " Step 1/6: Install Helm"
echo "=========================================="
if command -v helm &>/dev/null; then
  echo "Helm already installed: $(helm version --short)"
else
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  echo "Helm installed: $(helm version --short)"
fi

echo ""
echo "=========================================="
echo " Step 2/6: Install ArgoCD"
echo "=========================================="
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update

helm upgrade --install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  --set server.service.type=NodePort \
  --set server.service.nodePortHttps=30443 \
  --set "configs.params.server\.insecure=true" \
  --set dex.enabled=false \
  --wait --timeout 5m

echo "Waiting for ArgoCD server..."
kubectl wait --for=condition=Available deployment/argocd-server \
  -n argocd --timeout=180s

ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

echo ""
echo "  ArgoCD ready!"
echo "  UI: https://$(hostname -I | awk '{print $1}'):30443"
echo "  User: admin"
echo "  Pass: ${ARGOCD_PASS}"

echo ""
echo "=========================================="
echo " Step 3/6: Install NGINX Gateway Fabric (Gateway API)"
echo "=========================================="
helm install ngf oci://ghcr.io/nginx/charts/nginx-gateway-fabric \
  --create-namespace --namespace nginx-gateway \
  --wait --timeout 3m 2>/dev/null || echo "NGINX Gateway Fabric already installed, skipping..."

echo "Waiting for NGINX Gateway Fabric controller..."
kubectl wait --for=condition=Available deployment/ngf-nginx-gateway-fabric \
  -n nginx-gateway --timeout=120s

echo ""
echo "=========================================="
echo " Step 4/6: Clone repo & apply manifests"
echo "=========================================="
rm -rf "${REPO_DIR}"
git clone "${REPO_URL}" "${REPO_DIR}"

echo "Applying ArgoCD AppProject..."
kubectl apply -f "${REPO_DIR}/argocd/argocd-app-project.yaml"

echo ""
echo "=========================================="
echo " Step 5/6: Deploy OTel Demo via ArgoCD"
echo "=========================================="
kubectl create namespace otel-demo --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "${REPO_DIR}/apps/otel-demo-application-git.yaml"

echo "Waiting for ArgoCD to start syncing..."
sleep 10
echo "ArgoCD Application status:"
kubectl get application otel-demo -n argocd 2>/dev/null || echo "  (still initializing...)"

echo ""
echo "=========================================="
echo " Step 6/6: Apply Gateway + HTTPRoute"
echo "=========================================="
kubectl apply -f "${REPO_DIR}/gateway/gateway.yaml"
kubectl apply -f "${REPO_DIR}/gateway/httproute.yaml"

echo ""
echo "=========================================="
echo " Deployment initiated!"
echo "=========================================="
echo ""
echo " Monitor pods:"
echo "   kubectl get pods -n otel-demo -w"
echo ""
echo " Monitor ArgoCD sync:"
echo "   kubectl get application otel-demo -n argocd -w"
echo ""
echo " Get Gateway external IP (when ready):"
echo "   kubectl get gateway otel-demo-gateway -n otel-demo"
echo ""
echo " ArgoCD UI:"
echo "   https://$(hostname -I | awk '{print $1}'):30443"
echo "   User: admin / Pass: ${ARGOCD_PASS}"
echo ""
echo " Once Gateway gets an IP, services will be at:"
echo "   Web Store:      http://<GATEWAY_IP>/"
echo "   Grafana:        http://<GATEWAY_IP>/grafana/"
echo "   Jaeger UI:      http://<GATEWAY_IP>/jaeger/ui/"
echo "   Load Generator: http://<GATEWAY_IP>/loadgen/"
echo "   Feature Flags:  http://<GATEWAY_IP>/feature"
echo ""
