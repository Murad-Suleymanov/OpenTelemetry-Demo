#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Run on EACH WORKER node
# Joins this node to the Kubernetes cluster
#
# Usage:
#   ./02-join-workers.sh <master-ip> <token> <ca-cert-hash>
#
# Example:
#   ./02-join-workers.sh 10.0.0.10 abcdef.0123456789abcdef sha256:abc123...
#
# You can get the token and hash from the master node:
#   kubeadm token create --print-join-command
###############################################################################

MASTER_IP="${1:?Usage: $0 <master-ip> <token> <ca-cert-hash>}"
TOKEN="${2:?Usage: $0 <master-ip> <token> <ca-cert-hash>}"
CA_CERT_HASH="${3:?Usage: $0 <master-ip> <token> <ca-cert-hash>}"

echo "==> Joining cluster at ${MASTER_IP}:6443..."
kubeadm join "${MASTER_IP}:6443" \
  --token "${TOKEN}" \
  --discovery-token-ca-cert-hash "${CA_CERT_HASH}"

echo "[OK] Node joined the cluster. Verify on master with: kubectl get nodes"
