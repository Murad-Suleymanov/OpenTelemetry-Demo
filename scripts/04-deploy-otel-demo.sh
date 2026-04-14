#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Run on MASTER node (where kubectl is configured)
# Deploys OpenTelemetry Demo via ArgoCD Application
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS_DIR="${SCRIPT_DIR}/../apps"

echo "==> Creating otel-demo namespace..."
kubectl create namespace otel-demo --dry-run=client -o yaml | kubectl apply -f -

echo "==> Applying ArgoCD Application for OpenTelemetry Demo..."
kubectl apply -f "${APPS_DIR}/otel-demo-application.yaml"

echo "==> Waiting for ArgoCD to sync the application..."
echo "    (This may take several minutes as all microservices start up)"

sleep 10

echo ""
echo "============================================================"
echo "  OpenTelemetry Demo deployment initiated via ArgoCD!"
echo ""
echo "  Monitor sync status:"
echo "    kubectl get application otel-demo -n argocd"
echo "    argocd app get otel-demo"
echo ""
echo "  Access services (after sync completes):"
echo "    kubectl port-forward svc/frontend-proxy 8080:8080 -n otel-demo"
echo ""
echo "    Web Store:      http://localhost:8080/"
echo "    Grafana:        http://localhost:8080/grafana/"
echo "    Jaeger UI:      http://localhost:8080/jaeger/ui/"
echo "    Load Generator: http://localhost:8080/loadgen/"
echo "    Feature Flags:  http://localhost:8080/feature"
echo "============================================================"
