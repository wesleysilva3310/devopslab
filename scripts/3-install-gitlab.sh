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
sleep 10

############################
# CREATE NAMESPACE
############################
kubectl create namespace gitlab

############################
# INSTALL GITLAB (FIXED)
############################
echo "📦 Installing GitLab..."

helm install gitlab gitlab/gitlab \
  -n gitlab \
  \
  --set global.hosts.domain=lab \
  --set global.hosts.externalIP=192.168.56.12 \
  \
  --set global.ingress.class=nginx \
  \
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
# WAIT
############################
echo "⏳ Waiting for GitLab pods..."

kubectl wait --for=condition=Ready pods --all -n gitlab --timeout=900s || true

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
kubectl get secret gitlab-gitlab-initial-root-password -n gitlab -o jsonpath="{.data.password}" | base64 -d
echo ""

echo ""
echo "🌐 Access GitLab:"
echo "https://gitlab.lab"
echo ""
