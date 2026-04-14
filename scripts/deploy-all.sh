#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# OpenTelemetry Demo - Full Deployment Script
# Run on CONTROL-PLANE node (ubuntu-4gb-nbg1-1)
#
# Cluster: 1 master + 2 workers, 4GB RAM each, K8s v1.30.14
# Installs: Helm, MetalLB, ArgoCD, Envoy Gateway, OTel Demo
###############################################################################

REPO_URL="https://github.com/Murad-Suleymanov/OpenTelemetry-Demo.git"
REPO_DIR="/tmp/otel-demo-repo"

echo "=========================================="
echo " Step 1/7: Install Helm"
echo "=========================================="
if command -v helm &>/dev/null; then
  echo "Helm already installed: $(helm version --short)"
else
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  echo "Helm installed: $(helm version --short)"
fi

echo ""
echo "=========================================="
echo " Step 2/7: Install MetalLB"
echo "=========================================="
helm repo add metallb https://metallb.github.io/metallb 2>/dev/null || true
helm repo update

helm upgrade --install metallb metallb/metallb \
  --namespace metallb-system --create-namespace \
  --wait --timeout 3m

echo "Waiting for MetalLB controller..."
kubectl wait --for=condition=Available deployment/metallb-controller \
  -n metallb-system --timeout=120s

echo "Waiting for MetalLB speaker pods..."
kubectl rollout status daemonset/metallb-speaker -n metallb-system --timeout=120s

echo ""
echo "=========================================="
echo " Step 3/7: Install ArgoCD"
echo "=========================================="
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update

helm upgrade --install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  --set server.service.type=LoadBalancer \
  --set "configs.params.server\.insecure=true" \
  --set dex.enabled=false \
  --wait --timeout 5m

echo "Waiting for ArgoCD server..."
kubectl wait --for=condition=Available deployment/argocd-server \
  -n argocd --timeout=180s

ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

ARGOCD_IP=$(kubectl get svc argocd-server -n argocd \
  -o jsonpath="{.status.loadBalancer.ingress[0].ip}" 2>/dev/null || echo "pending")

echo ""
echo "  ArgoCD ready!"
echo "  UI: https://${ARGOCD_IP}"
echo "  User: admin"
echo "  Pass: ${ARGOCD_PASS}"

echo ""
echo "=========================================="
echo " Step 4/7: Install Envoy Gateway (Gateway API)"
echo "=========================================="
helm install eg oci://docker.io/envoyproxy/gateway-helm \
  --version v1.3.0 \
  --namespace envoy-gateway-system --create-namespace \
  --wait --timeout 3m 2>/dev/null || echo "Envoy Gateway already installed, skipping..."

echo "Waiting for Envoy Gateway controller..."
kubectl wait --for=condition=Available deployment/envoy-gateway \
  -n envoy-gateway-system --timeout=120s

echo ""
echo "=========================================="
echo " Step 5/7: Clone repo & apply manifests"
echo "=========================================="
rm -rf "${REPO_DIR}"
git clone "${REPO_URL}" "${REPO_DIR}"

echo "Applying MetalLB IP pool config..."
kubectl apply -f "${REPO_DIR}/gateway/metallb-config.yaml"

echo "Applying ArgoCD AppProject..."
kubectl apply -f "${REPO_DIR}/argocd/argocd-app-project.yaml"

echo ""
echo "=========================================="
echo " Step 6/7: Deploy OTel Demo via ArgoCD"
echo "=========================================="
kubectl create namespace otel-demo --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "${REPO_DIR}/apps/otel-demo-application-git.yaml"

echo "Waiting for ArgoCD to start syncing..."
sleep 10
echo "ArgoCD Application status:"
kubectl get application otel-demo -n argocd 2>/dev/null || echo "  (still initializing...)"

echo ""
echo "=========================================="
echo " Step 7/7: Apply Gateway + HTTPRoute"
echo "=========================================="
kubectl apply -f "${REPO_DIR}/gateway/gateway.yaml"
kubectl apply -f "${REPO_DIR}/gateway/httproute.yaml"

echo ""
echo "Waiting for Gateway to get external IP..."
sleep 15
GW_IP=$(kubectl get gateway otel-demo-gateway -n otel-demo \
  -o jsonpath="{.status.addresses[0].value}" 2>/dev/null || echo "pending")

echo ""
echo "=========================================="
echo " Deployment initiated!"
echo "=========================================="
echo ""
echo " Gateway IP: ${GW_IP}"
echo ""
echo " Monitor pods:"
echo "   kubectl get pods -n otel-demo -w"
echo ""
echo " Monitor ArgoCD sync:"
echo "   kubectl get application otel-demo -n argocd -w"
echo ""
echo " ArgoCD UI:"
echo "   https://${ARGOCD_IP}"
echo "   User: admin / Pass: ${ARGOCD_PASS}"
echo ""
echo " Services (once pods are ready):"
echo "   Web Store:      http://${GW_IP}/"
echo "   Grafana:        http://${GW_IP}/grafana/"
echo "   Jaeger UI:      http://${GW_IP}/jaeger/ui/"
echo "   Load Generator: http://${GW_IP}/loadgen/"
echo "   Feature Flags:  http://${GW_IP}/feature"
echo ""
