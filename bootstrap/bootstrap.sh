#!/bin/bash
#
# One-time bootstrap for a fresh cluster. After this, git is the source of truth:
# Argo CD watches apps/ and applies everything in it.
#
# Prerequisites: microk8s (or any cluster) running, kubectl and helm installed,
# kubeconfig pointing at the cluster. See bootstrap/Readme.md for the full steps,
# including restoring the Sealed Secrets key before the first sync.
#
set -euo pipefail
cd "$(dirname "$0")/.."

ARGOCD_CHART_VERSION="10.10.3"   # Argo CD v3.5.5

echo "==> Installing Argo CD ${ARGOCD_CHART_VERSION}"
helm repo add argo https://argoproj.github.io/argo-helm --force-update >/dev/null
helm repo update argo >/dev/null
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --version "${ARGOCD_CHART_VERSION}" \
  --values argocd/values.yaml \
  --wait

echo "==> Handing argocd/config (projects and the ApplicationSet) over to Argo CD"
kubectl apply -f argocd/root-app.yaml

echo
echo "Done. Argo CD UI: https://192.168.1.208 (user: admin)"
echo "Initial admin password:"
echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
