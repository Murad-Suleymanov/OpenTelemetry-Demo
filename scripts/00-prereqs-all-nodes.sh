#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Run this script on ALL nodes (master + worker1 + worker2)
# Prerequisites: Ubuntu 22.04+ / Debian 12+ / RHEL 9+ with root access
###############################################################################

echo "==> Disabling swap..."
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

echo "==> Loading kernel modules..."
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

echo "==> Setting sysctl params..."
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

echo "==> Installing containerd..."
apt-get update -qq
apt-get install -y -qq containerd apt-transport-https ca-certificates curl gnupg

mkdir -p /etc/containerd
cp "$(dirname "$0")/../cluster-setup/containerd-config.toml" /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

echo "==> Adding Kubernetes apt repository..."
KUBE_VERSION="1.31"
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${KUBE_VERSION}/deb/Release.key" \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBE_VERSION}/deb/ /" \
  | tee /etc/apt/sources.list.d/kubernetes.list

echo "==> Installing kubeadm, kubelet, kubectl..."
apt-get update -qq
apt-get install -y -qq kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

echo "==> Enabling kubelet..."
systemctl enable --now kubelet

echo "[OK] Prerequisites installed. Proceed with cluster init (master) or join (workers)."
