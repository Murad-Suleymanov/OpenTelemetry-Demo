# OpenTelemetry Demo - Kubernetes Deployment with ArgoCD

Deploys the [OpenTelemetry Demo](https://opentelemetry.io/docs/demo/architecture/)
on a Kubernetes cluster (1 master + 2 workers) using ArgoCD for GitOps-based delivery.

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│                    ArgoCD (GitOps)                        │
│              watches Helm chart + values                  │
│                        │                                 │
│    ┌───────────────────┼───────────────────┐             │
│    ▼                   ▼                   ▼             │
│ ┌─────────┐     ┌─────────────┐     ┌──────────┐        │
│ │ Master  │     │  Worker-1   │     │ Worker-2 │        │
│ │ Node    │     │  Node       │     │  Node    │        │
│ │         │     │             │     │          │        │
│ │ ArgoCD  │     │ OTel Demo   │     │ OTel Demo│        │
│ │ Control │     │ Services    │     │ Services │        │
│ │ Plane   │     │ Collector   │     │ Collector│        │
│ └─────────┘     └─────────────┘     └──────────┘        │
└──────────────────────────────────────────────────────────┘
```

## Prerequisites

| Component  | Version |
|------------|---------|
| OS         | Ubuntu 22.04+ / Debian 12+ / RHEL 9+ |
| Kubernetes | 1.31.x  |
| Helm       | 3.14+   |
| RAM        | 6 GB per worker node (minimum) |
| CPU        | 2 vCPU per node (minimum) |

## Directory Structure

```
k8s-otel-demo/
├── README.md
├── cluster-setup/
│   ├── kubeadm-config.yaml        # kubeadm ClusterConfiguration
│   └── containerd-config.toml     # containerd runtime config
├── argocd/
│   ├── namespace.yaml             # ArgoCD namespace
│   ├── argocd-values.yaml         # Helm values for ArgoCD
│   └── argocd-app-project.yaml    # ArgoCD AppProject for OTel Demo
├── otel-demo/
│   └── values.yaml                # Custom Helm values for OTel Demo
├── apps/
│   ├── otel-demo-application.yaml      # ArgoCD Application (inline values)
│   └── otel-demo-application-git.yaml  # ArgoCD Application (Git-sourced values)
└── scripts/
    ├── 00-prereqs-all-nodes.sh    # Install containerd, kubeadm, kubelet
    ├── 01-init-master.sh          # Initialize control plane
    ├── 02-join-workers.sh         # Join worker nodes
    ├── 03-install-argocd.sh       # Install ArgoCD via Helm
    └── 04-deploy-otel-demo.sh     # Deploy OTel Demo via ArgoCD
```

## Deployment Steps

### Step 1: Prepare All Nodes

Run on **all 3 nodes** (master + worker1 + worker2):

```bash
sudo bash scripts/00-prereqs-all-nodes.sh
```

> Edit `cluster-setup/kubeadm-config.yaml` first to set your master node IP
> in `localAPIEndpoint.advertiseAddress` and `certSANs`.

### Step 2: Initialize Master Node

Run on the **master node** only:

```bash
sudo bash scripts/01-init-master.sh
```

Save the `kubeadm join` command from the output.

### Step 3: Join Worker Nodes

Run on **each worker node**:

```bash
sudo bash scripts/02-join-workers.sh <MASTER_IP> <TOKEN> <CA_CERT_HASH>
```

Or use the join command from Step 2 directly.

Verify on master:

```bash
kubectl get nodes
# NAME       STATUS   ROLES           AGE   VERSION
# master     Ready    control-plane   5m    v1.31.x
# worker-1   Ready    <none>          2m    v1.31.x
# worker-2   Ready    <none>          2m    v1.31.x
```

### Step 4: Install ArgoCD

Run on the **master node**:

```bash
bash scripts/03-install-argocd.sh
```

Access the ArgoCD UI:

```bash
# Port-forward
kubectl port-forward svc/argocd-server -n argocd 8443:443

# Or via NodePort
https://<any-node-ip>:30443

# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### Step 5: Deploy OpenTelemetry Demo

```bash
# Create the AppProject
kubectl apply -f argocd/argocd-app-project.yaml

# Deploy the application
bash scripts/04-deploy-otel-demo.sh
```

Monitor the deployment:

```bash
kubectl get application otel-demo -n argocd
kubectl get pods -n otel-demo -w
```

### Step 6: Access Services

```bash
kubectl port-forward svc/frontend-proxy 8080:8080 -n otel-demo
```

Or via NodePort (configured at 30080):

| Service         | URL                                        |
|-----------------|--------------------------------------------|
| Web Store       | `http://<node-ip>:30080/`                  |
| Grafana         | `http://<node-ip>:30080/grafana/`          |
| Jaeger UI       | `http://<node-ip>:30080/jaeger/ui/`        |
| Load Generator  | `http://<node-ip>:30080/loadgen/`          |
| Feature Flags   | `http://<node-ip>:30080/feature`           |

## Customization

### Using Git-Sourced Values (Recommended for Production)

1. Push this repo to your Git server
2. Edit `apps/otel-demo-application-git.yaml`:
   - Replace `<YOUR_GIT_REPO_URL>` with your repo URL
   - Replace `<YOUR_BRANCH>` with your branch name
3. Apply:

```bash
kubectl apply -f apps/otel-demo-application-git.yaml
```

### Disabling Heavy Components

To reduce resource usage, disable optional services in `otel-demo/values.yaml`:

```yaml
components:
  load-generator:
    enabled: false
  llm:
    enabled: false

opensearch:
  enabled: false
```

### Node Affinity

Worker nodes are used for demo workloads via pod anti-affinity. To pin specific
services to specific workers, add `nodeSelector` per component:

```yaml
components:
  kafka:
    schedulingRules:
      nodeSelector:
        kubernetes.io/hostname: worker-1
```

## Helm Chart Reference

- **Chart**: `open-telemetry/opentelemetry-demo`
- **Version**: `0.40.3`
- **App Version**: `2.2.0`
- **Repo**: https://github.com/open-telemetry/opentelemetry-helm-charts
- **Docs**: https://opentelemetry.io/docs/demo/kubernetes-deployment/
