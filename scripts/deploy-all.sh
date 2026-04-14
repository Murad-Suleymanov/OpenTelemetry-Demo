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

ARGOCD_BCRYPT='$2b$12$MwI8balXhgleuhQYHaf3huhKBw6KEO/B757W2.JGHHTDLwaIVYfQ.'

helm upgrade --install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  --set server.service.type=ClusterIP \
  --set "configs.params.server\.insecure=true" \
  --set dex.enabled=false \
  --set "configs.secret.argocdServerAdminPassword=${ARGOCD_BCRYPT}" \
  --wait --timeout 5m

echo "Waiting for ArgoCD server..."
kubectl wait --for=condition=Available deployment/argocd-server \
  -n argocd --timeout=180s

ARGOCD_PASS="murad7171"

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
echo " Step 5/8: Install cert-manager (Let's Encrypt TLS)"
echo "=========================================="
helm repo add jetstack https://charts.jetstack.io 2>/dev/null || true
helm repo update

helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set crds.enabled=true \
  --set featureGates="ExperimentalGatewayAPISupport=true" \
  --wait --timeout 3m

echo "Waiting for cert-manager..."
kubectl wait --for=condition=Available deployment/cert-manager \
  -n cert-manager --timeout=120s

echo ""
echo "=========================================="
echo " Step 6/8: Clone repo & apply manifests"
echo "=========================================="
rm -rf "${REPO_DIR}"
git clone "${REPO_URL}" "${REPO_DIR}"

echo "Applying MetalLB IP pool config..."
kubectl apply -f "${REPO_DIR}/gateway/metallb-config.yaml"

echo "Applying ArgoCD AppProject..."
kubectl apply -f "${REPO_DIR}/argocd/argocd-app-project.yaml"

echo ""
echo "=========================================="
echo " Step 7/8: Deploy OTel Demo via ArgoCD"
echo "=========================================="
kubectl create namespace otel-demo --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "${REPO_DIR}/apps/otel-demo-application-git.yaml"

echo "Waiting for ArgoCD to start syncing..."
sleep 10
echo "ArgoCD Application status:"
kubectl get application otel-demo -n argocd 2>/dev/null || echo "  (still initializing...)"

echo ""
echo "=========================================="
echo " Step 8/8: Apply Gateway, HTTPRoutes, TLS Certificates"
echo "=========================================="
kubectl apply -f "${REPO_DIR}/gateway/gateway.yaml"
kubectl apply -f "${REPO_DIR}/gateway/httproute.yaml"
kubectl apply -f "${REPO_DIR}/gateway/reference-grant.yaml"
kubectl apply -f "${REPO_DIR}/gateway/certificates.yaml"
# NOTE: http-redirect.yaml is NOT applied here.
# Apply it manually AFTER all certificates show READY=True:
#   kubectl get certificates -n otel-demo
#   kubectl apply -f gateway/http-redirect.yaml

echo ""
echo "Waiting for Gateway to get external IP..."
sleep 15

echo "Patching Envoy proxy externalTrafficPolicy to Cluster..."
ENVOY_SVC=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=otel-demo-gateway \
  -o jsonpath="{.items[0].metadata.name}" 2>/dev/null || echo "")
if [ -n "$ENVOY_SVC" ]; then
  kubectl patch svc "$ENVOY_SVC" -n envoy-gateway-system \
    -p '{"spec":{"externalTrafficPolicy":"Cluster"}}' 2>/dev/null || true
fi

GW_IP=$(kubectl get gateway otel-demo-gateway -n otel-demo \
  -o jsonpath="{.status.addresses[0].value}" 2>/dev/null || echo "pending")

echo "Resetting Grafana admin password..."
sleep 5
kubectl exec -n otel-demo deploy/grafana -- grafana-cli admin reset-admin-password murad7171 2>/dev/null || echo "  (Grafana not ready yet, reset password manually later)"

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
echo "   Web Store:      https://oteldemo.easysolution.work"
echo "   Grafana:        https://grafana-oteldemo.easysolution.work"
echo "   Jaeger UI:      https://jaeger-oteldemo.easysolution.work"
echo "   Load Generator: https://loadgen-oteldemo.easysolution.work"
echo "   Feature Flags:  https://flagd-oteldemo.easysolution.work"
echo "   ArgoCD:         https://argocd-oteldemo.easysolution.work"
echo ""
