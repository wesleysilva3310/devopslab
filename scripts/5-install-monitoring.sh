#!/bin/bash
set -e

echo "🚀 Installing kube-prometheus-stack..."

export KUBECONFIG=/etc/kubernetes/admin.conf

############################
# FIX PERMISSIONS
############################
sudo chmod 644 /etc/kubernetes/admin.conf || true

############################
# WAIT FOR CLUSTER
############################
echo "⏳ Waiting for Kubernetes API..."
until kubectl get nodes >/dev/null 2>&1; do
  sleep 5
done

echo "⏳ Waiting for nodes Ready..."
until [ "$(kubectl get nodes --no-headers | grep -c ' Ready')" -ge 3 ]; do
  sleep 5
done

############################
# NAMESPACE
############################
kubectl create namespace monitoring >/dev/null 2>&1 || true

############################
# HELM REPO
############################
echo "📦 Adding Prometheus repo..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

############################
# CLEAN PREVIOUS INSTALL
############################
echo "🧹 Cleaning previous install..."
helm uninstall monitoring -n monitoring >/dev/null 2>&1 || true

############################
# INSTALL STACK
############################
echo "📦 Installing monitoring stack..."

helm install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --set grafana.adminPassword=admin \
  \
  --set grafana.persistence.enabled=true \
  --set grafana.persistence.size=5Gi \
  \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.accessModes[0]=ReadWriteOnce \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=10Gi \
  \
  --set alertmanager.alertmanagerSpec.storage.volumeClaimTemplate.spec.accessModes[0]=ReadWriteOnce \
  --set alertmanager.alertmanagerSpec.storage.volumeClaimTemplate.spec.resources.requests.storage=5Gi \
  \
  --set grafana.ingress.enabled=true \
  --set grafana.ingress.ingressClassName=nginx \
  --set grafana.ingress.hosts[0]=grafana.lab \
  --set grafana.ingress.tls[0].hosts[0]=grafana.lab \
  --set grafana.ingress.tls[0].secretName=grafana-tls \
  \
  --set prometheus.ingress.enabled=true \
  --set prometheus.ingress.ingressClassName=nginx \
  --set prometheus.ingress.hosts[0]=prometheus.lab \
  --set prometheus.ingress.tls[0].hosts[0]=prometheus.lab \
  --set prometheus.ingress.tls[0].secretName=prometheus-tls \
  \
  --set alertmanager.ingress.enabled=true \
  --set alertmanager.ingress.ingressClassName=nginx \
  --set alertmanager.ingress.hosts[0]=alertmanager.lab \
  --set alertmanager.ingress.tls[0].hosts[0]=alertmanager.lab \
  --set alertmanager.ingress.tls[0].secretName=alertmanager-tls

############################
# CREATE CERTIFICATES
############################
echo "🔐 Creating TLS certificates..."

kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: grafana-cert
  namespace: monitoring
spec:
  secretName: grafana-tls
  issuerRef:
    name: lab-ca-issuer
    kind: ClusterIssuer
  commonName: grafana.lab
  dnsNames:
    - grafana.lab
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: prometheus-cert
  namespace: monitoring
spec:
  secretName: prometheus-tls
  issuerRef:
    name: lab-ca-issuer
    kind: ClusterIssuer
  commonName: prometheus.lab
  dnsNames:
    - prometheus.lab
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: alertmanager-cert
  namespace: monitoring
spec:
  secretName: alertmanager-tls
  issuerRef:
    name: lab-ca-issuer
    kind: ClusterIssuer
  commonName: alertmanager.lab
  dnsNames:
    - alertmanager.lab
EOF

############################
# WAIT FOR PODS
############################
echo "⏳ Waiting for monitoring pods..."

kubectl wait --for=condition=Ready pods --all -n monitoring --timeout=600s || true

############################
# INFO
############################
echo ""
echo "📊 Pods:"
kubectl get pods -n monitoring

echo ""
echo "🌐 Ingress:"
kubectl get ingress -n monitoring

echo ""
echo "🔑 Grafana login:"
echo "user: admin"
echo "pass: admin"
echo ""
echo "🌐 Access:"
echo "https://grafana.lab"
echo "https://prometheus.lab"
echo "https://alertmanager.lab"
echo ""