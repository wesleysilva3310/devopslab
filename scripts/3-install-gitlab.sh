#!/bin/bash
set -e

echo "🚀 Installing GitLab (clean + stable)..."

export KUBECONFIG=/etc/kubernetes/admin.conf

############################
# FIX KUBECONFIG PERMISSION
############################
sudo chmod 644 /etc/kubernetes/admin.conf || true

############################
# WAIT FOR CLUSTER
############################
echo "⏳ Waiting for Kubernetes API..."

until kubectl get nodes >/dev/null 2>&1; do
  echo "Waiting for API..."
  sleep 5
done

echo "⏳ Waiting for all nodes Ready..."

until [ "$(kubectl get nodes --no-headers | grep -c ' Ready')" -ge 3 ]; do
  kubectl get nodes
  sleep 5
done

############################
# HELM
############################
if ! command -v helm >/dev/null 2>&1; then
  echo "📦 Installing Helm..."
  sudo snap install helm --classic
fi

############################
# REPOS
############################
echo "📦 Adding Helm repos..."

helm repo add gitlab https://charts.gitlab.io 2>/dev/null || true
helm repo update

############################
# CLEAN OLD INSTALL
############################
echo "🧹 Cleaning previous GitLab install..."

helm uninstall gitlab -n gitlab >/dev/null 2>&1 || true

kubectl delete namespace gitlab --ignore-not-found

echo "⏳ Waiting namespace deletion..."

while kubectl get namespace gitlab >/dev/null 2>&1; do
  sleep 3
done

############################
# CREATE NAMESPACE
############################
kubectl create namespace gitlab

############################
# INSTALL GITLAB
############################
echo "📦 Installing GitLab Chart 9.3.6..."

helm install gitlab gitlab/gitlab \
  --version 9.3.6 \
  -n gitlab \
  \
  --set global.hosts.domain=lab \
  --set global.hosts.externalIP=192.168.56.12 \
  \
  --set global.ingress.class=nginx \
  --set global.ingress.configureCertmanager=false \
  \
  --set nginx-ingress.enabled=false \
  \
  --set global.storageClass=nfs-client \
  \
  --set global.edition=ce \
  \
  --set prometheus.install=false \
  --set grafana.enabled=false \
  \
  --set gitlab-runner.install=false

############################
# WAIT FOR GITLAB
############################
echo "⏳ Waiting for GitLab workloads..."

echo "⏳ Waiting for GitLab webservice..."

kubectl wait \
  --for=condition=Ready \
  pod \
  -l app=webservice \
  -n gitlab \
  --timeout=900s || true

echo "⏳ Waiting for GitLab pods to become Running..."

TIMEOUT=900
ELAPSED=0

while true; do

  NOT_READY=$(kubectl get pods -n gitlab --no-headers 2>/dev/null | \
    awk '$3 != "Running" && $3 != "Completed" {count++} END {print count+0}')

  if [ "$NOT_READY" -eq 0 ]; then
    echo "✅ All GitLab workloads are Running or Completed."
    break
  fi

  if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
    echo "⚠️ Timeout waiting for GitLab workloads."
    break
  fi

  echo "⏳ Still waiting... ($ELAPSED/$TIMEOUT seconds)"
  kubectl get pods -n gitlab
  sleep 10
  ELAPSED=$((ELAPSED + 10))

done

############################
# INFO
############################
echo ""
echo "📊 Pods:"
kubectl get pods -n gitlab

echo ""
echo "🌐 Ingress:"
kubectl get ingress -n gitlab

echo ""
echo "🔑 Root password:"

kubectl get secret \
  gitlab-gitlab-initial-root-password \
  -n gitlab \
  -o jsonpath="{.data.password}" \
  | base64 -d

echo ""

echo ""
echo "🌐 Access GitLab:"
echo "https://gitlab.lab"
echo ""

echo "✅ GitLab installation finished."
