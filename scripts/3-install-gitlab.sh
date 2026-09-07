#!/bin/bash
set -e

echo "🚀 Installing GitLab (clean + stable)..."

export KUBECONFIG=/etc/kubernetes/admin.conf

############################
# FIX KUBECONFIG PERMISSION
############################
sudo chmod 644 /etc/kubernetes/admin.conf || true

############################
# WAIT FOR KUBERNETES API
############################
echo "⏳ Waiting for Kubernetes API..."

until kubectl get nodes >/dev/null 2>&1; do
  echo "Waiting for API..."
  sleep 5
done

############################
# WAIT FOR ALL NODES
############################
echo "⏳ Waiting for all nodes Ready..."

until [ "$(kubectl get nodes --no-headers | grep -c ' Ready')" -ge 3 ]; do
  kubectl get nodes
  sleep 5
done

echo "✅ All nodes are Ready."

############################
# HELM
############################
if ! command -v helm >/dev/null 2>&1; then
  echo "📦 Installing Helm..."
  sudo snap install helm --classic
fi

############################
# HELM REPOSITORY
############################
echo "📦 Adding Helm repos..."

helm repo add gitlab https://charts.gitlab.io 2>/dev/null || true
helm repo update

############################
# CLEAN PREVIOUS GITLAB
############################
echo "🧹 Cleaning previous GitLab installation..."

helm uninstall gitlab -n gitlab >/dev/null 2>&1 || true

kubectl delete namespace gitlab --ignore-not-found

echo "⏳ Waiting for namespace deletion..."

while kubectl get namespace gitlab >/dev/null 2>&1; do
  sleep 3
done

############################
# CREATE GITLAB NAMESPACE
############################
echo "📁 Creating GitLab namespace..."

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
  --set gitlab-runner.install=false \
  \
  --set installCertmanager=false

############################
# WAIT FOR GITLAB WORKLOADS
############################
echo ""
echo "⏳ Waiting for GitLab workloads..."

TIMEOUT=900
ELAPSED=0

while true; do

  NOT_READY=$(
    kubectl get pods -n gitlab --no-headers 2>/dev/null |
    awk '$3 != "Running" && $3 != "Completed" {count++} END {print count+0}'
  )

  if [ "$NOT_READY" -eq 0 ]; then
    echo "✅ All GitLab workloads are Running or Completed."
    break
  fi

  if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
    echo "⚠️ Timeout waiting for GitLab workloads."
    echo ""
    kubectl get pods -n gitlab
    break
  fi

  echo "⏳ Still waiting... ($ELAPSED/$TIMEOUT seconds)"

  kubectl get pods -n gitlab

  sleep 10

  ELAPSED=$((ELAPSED + 10))

done

############################
# SHOW PODS
############################
echo ""
echo "📊 GitLab Pods:"
kubectl get pods -n gitlab

############################
# SHOW INGRESS
############################
echo ""
echo "🌐 GitLab Ingress:"
kubectl get ingress -n gitlab

############################
# ROOT PASSWORD
############################
echo ""
echo "🔑 Root password:"

kubectl get secret \
  gitlab-gitlab-initial-root-password \
  -n gitlab \
  -o jsonpath="{.data.password}" \
  | base64 -d

echo ""

############################
# VERIFY CERT-MANAGER IS NOT
# INSTALLED BY GITLAB
############################
echo ""
echo "🔎 Checking GitLab cert-manager..."

if kubectl get deployment gitlab-certmanager -n gitlab >/dev/null 2>&1; then
  echo "⚠️ WARNING: GitLab cert-manager is still present."
else
  echo "✅ GitLab is NOT installing its own cert-manager."
fi

############################
# DONE
############################
echo ""
echo "========================================"
echo "✅ GITLAB INSTALLATION FINISHED"
echo "========================================"
echo ""
echo "📦 GitLab Chart: 9.3.6"
echo "📦 GitLab version: 18.3.6"
echo ""
echo "🌐 Access:"
echo "https://gitlab.lab"
echo ""
echo "🔐 cert-manager:"
echo "External / centralized installation"
echo ""
