#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Run on MASTER node only
# Initializes the Kubernetes control plane
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/../cluster-setup"

echo "==> Initializing Kubernetes control plane..."
kubeadm init --config "${CONFIG_DIR}/kubeadm-config.yaml" --upload-certs | tee /tmp/kubeadm-init.log

echo "==> Setting up kubeconfig for current user..."
mkdir -p "$HOME/.kube"
cp -f /etc/kubernetes/admin.conf "$HOME/.kube/config"
chown "$(id -u):$(id -g)" "$HOME/.kube/config"

echo "==> Installing Flannel CNI..."
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

echo "==> Waiting for control plane pods to become ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s

echo ""
echo "============================================================"
echo "  IMPORTANT: Save the 'kubeadm join' command from above!"
echo "  Run it on both worker nodes."
echo "============================================================"
echo ""
echo "  Or generate a new join token:"
echo "    kubeadm token create --print-join-command"
echo ""
