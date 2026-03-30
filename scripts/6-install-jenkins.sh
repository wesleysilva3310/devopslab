#!/bin/bash
set -e

echo "🚀 Installing Jenkins..."

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
kubectl create namespace jenkins >/dev/null 2>&1 || true

############################
# HELM REPO
############################
echo "📦 Adding Jenkins repo..."
helm repo add jenkins https://charts.jenkins.io
helm repo update

############################
# CLEAN PREVIOUS INSTALL
############################
echo "🧹 Cleaning previous Jenkins..."
helm uninstall jenkins -n jenkins >/dev/null 2>&1 || true

############################
# INSTALL JENKINS
############################
echo "📦 Installing Jenkins..."

helm install jenkins jenkins/jenkins \
  -n jenkins \
  --set controller.adminUser=admin \
  --set controller.adminPassword=admin \
  \
  --set controller.persistence.enabled=true \
  --set controller.persistence.size=10Gi \
  \
  --set controller.serviceType=ClusterIP \
  \
  --set controller.ingress.enabled=true \
  --set controller.ingress.ingressClassName=nginx \
  --set controller.ingress.hostName=jenkins.lab \
  \
  --set controller.ingress.tls[0].hosts[0]=jenkins.lab \
  --set controller.ingress.tls[0].secretName=jenkins-tls

############################
# CREATE TLS CERT
############################
echo "🔐 Creating TLS certificate..."

kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: jenkins-cert
  namespace: jenkins
spec:
  secretName: jenkins-tls
  issuerRef:
    name: lab-ca-issuer
    kind: ClusterIssuer
  commonName: jenkins.lab
  dnsNames:
    - jenkins.lab
EOF

############################
# WAIT FOR POD
############################
echo "⏳ Waiting for Jenkins pod..."

kubectl wait --for=condition=Ready pod \
  -l app.kubernetes.io/component=jenkins-controller \
  -n jenkins \
  --timeout=600s || true

############################
# INFO
############################
echo ""
echo "📊 Pods:"
kubectl get pods -n jenkins

echo ""
echo "🌐 Ingress:"
kubectl get ingress -n jenkins

echo ""
echo "🔑 Login:"
echo "user: admin"
echo "pass: admin"
echo ""
echo "🌐 Access:"
echo "https://jenkins.lab"
echo ""