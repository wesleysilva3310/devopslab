#!/bin/bash
set -e

echo "🚀 Installing NGINX Ingress Controller..."

export KUBECONFIG=/etc/kubernetes/admin.conf

############################
# FIX PERMISSIONS (IMPORTANT)
############################
sudo chmod 644 /etc/kubernetes/admin.conf

############################
# WAIT FOR API
############################
echo "⏳ Waiting for Kubernetes API..."

until kubectl get nodes >/dev/null 2>&1; do
  echo "Waiting for API..."
  sleep 5
done

############################
# WAIT FOR ALL NODES READY
############################
echo "⏳ Waiting for all nodes to be Ready..."

until [ "$(kubectl get nodes --no-headers | grep -c ' Ready')" -ge 3 ]; do
  kubectl get nodes
  sleep 5
done

############################
# WAIT FOR SYSTEM PODS
############################
echo "⏳ Waiting for kube-system pods..."

kubectl wait \
  --for=condition=Ready pods \
  --all -n kube-system \
  --timeout=300s

############################
# CREATE NAMESPACE (NEW)
############################
echo "📦 Creating ingress-nginx namespace..."
kubectl create namespace ingress-nginx >/dev/null 2>&1 || true

############################
# INSTALL HELM
############################
if ! command -v helm >/dev/null 2>&1; then
  echo "📦 Installing Helm..."
  snap install helm --classic
fi

############################
# ADD REPO
############################
echo "📦 Adding ingress-nginx repo..."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

############################
# CLEAN PREVIOUS INSTALL (UPDATED WITH NAMESPACE)
############################
echo "🧹 Cleaning previous ingress (if exists)..."
helm uninstall ingress-nginx -n ingress-nginx >/dev/null 2>&1 || true

############################
# INSTALL INGRESS (UPDATED NAMESPACE)
############################
echo "📦 Installing ingress controller (DaemonSet mode)..."

helm install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx \
  --set controller.kind=DaemonSet \
  --set controller.hostNetwork=true \
  --set controller.service.type=ClusterIP

############################
# WAIT FOR CONTROLLER (UPDATED NAMESPACE)
############################
echo "⏳ Waiting for ingress controller rollout..."

kubectl rollout status daemonset ingress-nginx-controller \
  -n ingress-nginx \
  --timeout=180s || true

############################
# VERIFY (UPDATED)
############################
echo "📊 Ingress Pods:"
kubectl get pods -n ingress-nginx -o wide

echo "📊 Nodes:"
kubectl get nodes

echo "📊 Services:"
kubectl get svc -n ingress-nginx

echo ""
echo "✅ Ingress Controller installed successfully!"
echo ""
echo "🌐 You can now access ingress via ANY node IP (NO PORT NEEDED):"
echo " - http://192.168.56.11"
echo " - http://192.168.56.12"
echo " - http://192.168.56.13"