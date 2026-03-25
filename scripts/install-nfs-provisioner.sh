#!/bin/bash
set -e
############################
# RUN THIS SCRIPT IN K8SMASTER
############################
NAMESPACE="default"
RELEASE_NAME="nfs-client"
HELM_REPO_NAME="nfs-subdir-external-provisioner"
HELM_REPO_URL="https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/"
NFS_SERVER="192.168.56.11"
NFS_PATH="/srv/nfs/k8s"

echo "🚀 Installing NFS Dynamic Provisioner..."

############################
# CHECK KUBECTL
############################
if ! command -v kubectl >/dev/null 2>&1; then
  echo "❌ kubectl not found. Run this on k8smaster."
  exit 1
fi

############################
# WAIT FOR CLUSTER READY
############################
echo "⏳ Waiting for Kubernetes cluster..."

until kubectl get nodes >/dev/null 2>&1; do
  sleep 5
done

echo "⏳ Waiting for all nodes to be Ready..."

until kubectl get nodes | grep -q " Ready"; do
  sleep 5
done

############################
# INSTALL HELM IF NEEDED
############################
if ! command -v helm >/dev/null 2>&1; then
  echo "📦 Installing Helm..."
  sudo snap install helm --classic
else
  echo "✅ Helm already installed"
fi

############################
# ADD HELM REPO
############################
if ! helm repo list | grep -q "$HELM_REPO_NAME"; then
  echo "📦 Adding Helm repo..."
  helm repo add $HELM_REPO_NAME $HELM_REPO_URL
fi

helm repo update

############################
# INSTALL OR UPGRADE
############################
if helm list -n $NAMESPACE | grep -q $RELEASE_NAME; then
  echo "🔄 Upgrading existing release..."
  helm upgrade $RELEASE_NAME $HELM_REPO_NAME/nfs-subdir-external-provisioner \
    --namespace $NAMESPACE \
    --set nfs.server=$NFS_SERVER \
    --set nfs.path=$NFS_PATH \
    --set storageClass.name=nfs-client \
    --set storageClass.defaultClass=true
else
  echo "📦 Installing new release..."
  helm install $RELEASE_NAME $HELM_REPO_NAME/nfs-subdir-external-provisioner \
    --namespace $NAMESPACE \
    --set nfs.server=$NFS_SERVER \
    --set nfs.path=$NFS_PATH \
    --set storageClass.name=nfs-client \
    --set storageClass.defaultClass=true
fi

############################
# VERIFY
############################
echo "⏳ Waiting for provisioner pod..."

kubectl rollout status deployment/$RELEASE_NAME-nfs-subdir-external-provisioner

echo "📊 StorageClasses:"
kubectl get storageclass

echo "📊 Pods:"
kubectl get pods

echo "✅ NFS Dynamic Provisioner installed successfully!"