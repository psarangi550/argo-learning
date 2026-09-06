#!/usr/bin/env bash
# setup-env.sh — rebuild kind + ArgoCD learning environment from scratch
set -euo pipefail

CLUSTER_NAME="dev"
ARGOCD_CHART_VERSION="8.6.0"

# ---------- 1. Install tools (skip if already present) ----------

if ! command -v kind &>/dev/null; then
  echo ">>> Installing kind..."
  curl -sLo ./kind https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64
  chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind
fi

if ! command -v kubectl &>/dev/null; then
  echo ">>> Installing kubectl..."
  curl -sLO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x kubectl && sudo mv kubectl /usr/local/bin/
fi

if ! command -v helm &>/dev/null; then
  echo ">>> Installing helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

if ! command -v argocd &>/dev/null; then
  echo ">>> Installing argocd CLI..."
  curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
  chmod +x argocd && sudo mv argocd /usr/local/bin/
fi

# ---------- 2. Create 3-node kind cluster ----------

if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  echo ">>> kind cluster '${CLUSTER_NAME}' already exists, skipping."
else
  echo ">>> Creating kind cluster '${CLUSTER_NAME}' (1 CP + 2 workers)..."
  cat <<EOF | kind create cluster --config -
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${CLUSTER_NAME}
nodes:
  - role: control-plane
  - role: worker
  - role: worker
EOF
fi

kubectl cluster-info --context "kind-${CLUSTER_NAME}"

# ---------- 3. Install ArgoCD via Helm ----------

if helm status argocd -n argocd &>/dev/null; then
  echo ">>> ArgoCD release already installed, skipping."
else
  echo ">>> Installing ArgoCD chart ${ARGOCD_CHART_VERSION}..."
  helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
  helm repo update
  helm upgrade --install argocd argo/argo-cd \
    --version "${ARGOCD_CHART_VERSION}" \
    --namespace argocd --create-namespace \
    --set configs.params."server\.insecure"=true
fi

echo ">>> Waiting for argocd-server to be ready..."
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s

# ---------- 4. Print credentials & next steps ----------

PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

echo ""
echo "=============================================="
echo " Environment ready!"
echo " ArgoCD admin password: ${PASSWORD}"
echo ""
echo " CLI login:"
echo "   argocd app list --port-forward --port-forward-namespace argocd"
echo ""
echo " Start the UI:"
echo "   kubectl port-forward svc/argocd-server -n argocd 8081:80"
echo "=============================================="