#!/bin/bash
set -e

echo "🔐 Setting up TRUSTED HTTPS (CA-based)..."

export KUBECONFIG=/etc/kubernetes/admin.conf

############################
# FIX PERMISSIONS
############################
sudo chmod 644 /etc/kubernetes/admin.conf || true

############################
# CREATE NAMESPACE (if needed)
############################
kubectl create namespace cert-manager >/dev/null 2>&1 || true

############################
# STEP 1 — CREATE ROOT CA (self-signed)
############################
echo "🏗️ Creating Root CA..."

kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: root-selfsigned
spec:
  selfSigned: {}
EOF

############################
# STEP 2 — CREATE CA CERTIFICATE
############################
echo "📜 Creating CA certificate..."

kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: lab-root-ca
  namespace: cert-manager
spec:
  isCA: true
  commonName: lab.local CA
  secretName: lab-root-ca-secret
  issuerRef:
    name: root-selfsigned
    kind: ClusterIssuer
EOF

############################
# WAIT CA READY
############################
echo "⏳ Waiting for CA..."
kubectl wait --for=condition=Ready certificate/lab-root-ca -n cert-manager --timeout=120s

############################
# STEP 3 — CREATE CA ISSUER
############################
echo "🔐 Creating CA issuer..."

kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: lab-ca-issuer
spec:
  ca:
    secretName: lab-root-ca-secret
EOF

############################
# STEP 4 — EXTRACT CA TO HOST
############################
echo "💾 Extracting CA to host..."

kubectl get secret lab-root-ca-secret -n cert-manager -o jsonpath="{.data.ca\.crt}" | base64 -d > lab-root-ca.crt

############################
# STEP 5 — TRUST CA ON HOST
############################
echo "🔑 Installing CA into system trust..."

sudo cp lab-root-ca.crt /usr/local/share/ca-certificates/lab-root-ca.crt
sudo update-ca-certificates

############################
# STEP 6 — CREATE GITLAB CERT
############################
echo "📜 Creating GitLab TLS cert..."

kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: gitlab-cert
  namespace: gitlab
spec:
  secretName: gitlab-tls
  issuerRef:
    name: lab-ca-issuer
    kind: ClusterIssuer
  commonName: gitlab.lab
  dnsNames:
    - gitlab.lab
EOF

############################
# WAIT CERT READY
############################
echo "⏳ Waiting for GitLab certificate..."
kubectl wait --for=condition=Ready certificate/gitlab-cert -n gitlab --timeout=120s

############################
# STEP 7 — PATCH INGRESS
############################
echo "🌐 Patching GitLab ingress..."

kubectl patch ingress gitlab-webservice-default -n gitlab \
  --type merge \
  -p '{
    "spec": {
      "tls": [
        {
          "hosts": ["gitlab.lab"],
          "secretName": "gitlab-tls"
        }
      ]
    }
  }'

############################
# DONE
############################
echo ""
echo "✅ HTTPS fully configured!"
echo ""
echo "🌐 Access:"
echo "https://gitlab.lab"
echo ""
echo "🟢 Browser should now show TRUSTED certificate (no warning)"